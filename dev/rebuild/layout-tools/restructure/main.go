// restructure plans and applies a flat Go package's split into packages, from a mapping file -> package, with go/types:
// objects used across the new package boundaries are exported (renamed at every definition and use) and qualified
// where used from another package; methods on the receiver type (default Module) become functions taking the shared
// base (*core.Base) first, their calls rewritten; the receiver's field rt becomes RT on the base. Entry files (package
// "" in the mapping) keep their methods; calls from them use m.b. Method values (not calls) are reported, not changed.
//
// Usage: restructure -dir <package dir> -map <file:pkg,...> [-recv Module] [-apply]
package main

import (
	"flag"
	"fmt"
	"go/ast"
	"go/token"
	"go/types"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"unicode"

	"golang.org/x/tools/go/packages"
)

type edit struct {
	start, end int
	text       string
}

func export(n string) string {
	for _, pre := range []string{"uuid", "id", "url", "sql", "json", "http"} {
		if strings.HasPrefix(n, pre) && (len(n) == len(pre) || unicode.IsUpper([]rune(n)[len(pre)])) {
			return strings.ToUpper(pre) + n[len(pre):]
		}
	}
	r := []rune(n)
	r[0] = unicode.ToUpper(r[0])
	return string(r)
}

func main() {
	dir := flag.String("dir", ".", "the package directory")
	mapping := flag.String("map", "", "file:pkg,...; pkg empty = the entry package")
	recv := flag.String("recv", "Module", "the receiver type whose methods become functions")
	apply := flag.Bool("apply", false, "write the edits")
	renameFlag := flag.String("rename", "", "old=new,...: methods renamed as they become functions (a type has the name)")
	tests := flag.Bool("tests", false, "include the test files (the in-package test variant)")
	tags := flag.String("tags", "", "build tags")
	entryName := flag.String("entry", "", "the entry package's name, to qualify its objects used from new packages")
	flag.Parse()
	pkgOf := map[string]string{}
	for _, kv := range strings.Split(*mapping, ",") {
		f, p, _ := strings.Cut(kv, ":")
		pkgOf[f] = p
	}
	cfg := &packages.Config{Mode: packages.NeedName | packages.NeedFiles | packages.NeedSyntax | packages.NeedTypes |
		packages.NeedTypesInfo | packages.NeedImports | packages.NeedDeps, Dir: *dir, Tests: *tests}
	if *tags != "" {
		cfg.BuildFlags = []string{"-tags=" + *tags}
	}
	pkgs, err := packages.Load(cfg, ".")
	if err != nil {
		fmt.Fprintln(os.Stderr, "load:", err)
		os.Exit(1)
	}
	var p *packages.Package
	for _, c := range pkgs {
		if !*tests && len(pkgs) == 1 || *tests && strings.HasSuffix(c.ID, ".test]") {
			p = c
		}
	}
	if p == nil || len(p.Errors) > 0 {
		fmt.Fprintln(os.Stderr, "load: no package, or errors:", p)
		os.Exit(1)
	}
	fset := p.Fset
	if os.Getenv("RESTRUCTURE_DEBUG") != "" {
		for _, c := range pkgs {
			fmt.Fprintln(os.Stderr, "PKG", c.ID, len(c.Syntax))
		}
		for _, f := range p.Syntax {
			fmt.Fprintln(os.Stderr, "FILE", fset.Position(f.Pos()).Filename)
		}
	}
	fileOf := func(pos token.Pos) string { return filepath.Base(fset.Position(pos).Filename) }
	newPkg := func(pos token.Pos) (string, bool) {
		pk, ok := pkgOf[fileOf(pos)]
		return pk, ok
	}
	recvType := p.Types.Scope().Lookup(*recv)
	isRecvMethod := func(obj types.Object) bool {
		f, ok := obj.(*types.Func)
		if !ok {
			return false
		}
		sig := f.Type().(*types.Signature)
		if sig.Recv() == nil {
			return false
		}
		t := sig.Recv().Type()
		if pt, ok := t.(*types.Pointer); ok {
			t = pt.Elem()
		}
		return recvType != nil && types.Identical(t, recvType.Type())
	}
	ownField := func(v *types.Var) bool {
		if recvType == nil {
			return false
		}
		st, ok := recvType.Type().Underlying().(*types.Struct)
		if !ok {
			return false
		}
		for i := 0; i < st.NumFields(); i++ {
			if st.Field(i) == v {
				return true
			}
		}
		return false
	}
	// which package-level objects and receiver methods are used across the new boundaries
	needExport := map[types.Object]bool{}
	for id, obj := range p.TypesInfo.Uses {
		if obj == nil || obj.Pkg() != p.Types {
			continue
		}
		pkgLevel := obj.Parent() == p.Types.Scope()
		member := false
		if v, ok := obj.(*types.Var); ok && v.IsField() {
			member = true
		}
		if f, ok := obj.(*types.Func); ok && f.Type().(*types.Signature).Recv() != nil && !isRecvMethod(obj) {
			member = true
		}
		if !pkgLevel && !isRecvMethod(obj) && !member {
			continue
		}
		up, ok1 := newPkg(id.Pos())
		dp, ok2 := newPkg(obj.Pos())
		if !ok1 || !ok2 {
			fmt.Fprintln(os.Stderr, "unmapped file:", fileOf(id.Pos()), fileOf(obj.Pos()))
			os.Exit(1)
		}
		if v, ok := obj.(*types.Var); ok && v.IsField() && recvType != nil {
			if st, ok := recvType.Type().Underlying().(*types.Struct); ok {
				own := false
				for i := 0; i < st.NumFields(); i++ {
					own = own || st.Field(i) == v
				}
				if own { // the receiver's own fields: rt becomes the base's RT, nothing else is shared
					continue
				}
			}
		}
		if up != dp && !obj.Exported() {
			needExport[obj] = true
		}
	}
	renames := map[string]string{}
	for _, kv := range strings.Split(*renameFlag, ",") {
		if o, nw, ok := strings.Cut(kv, "="); ok {
			renames[o] = nw
		}
	}
	nameOf := func(obj types.Object) string {
		name := obj.Name()
		if r, ok := renames[name]; ok && isRecvMethod(obj) {
			name = r
		}
		if needExport[obj] {
			return export(name)
		}
		return name
	}
	// collisions within a destination package
	seen := map[string]types.Object{}
	var all []types.Object
	for _, name := range p.Types.Scope().Names() {
		all = append(all, p.Types.Scope().Lookup(name))
	}
	if recvType != nil {
		mset := types.NewMethodSet(types.NewPointer(recvType.Type()))
		for i := 0; i < mset.Len(); i++ {
			if dp, _ := newPkg(mset.At(i).Obj().Pos()); dp != "" {
				all = append(all, mset.At(i).Obj())
			}
		}
	}
	for _, obj := range all {
		dp, _ := newPkg(obj.Pos())
		k := dp + "." + nameOf(obj)
		if o, dup := seen[k]; dup {
			fmt.Fprintf(os.Stderr, "collision in %s: %s and %s\n", dp, o.Name(), obj.Name())
		}
		seen[k] = obj
	}
	edits := map[string][]edit{}
	add := func(pos, end token.Pos, text string) {
		f := fset.Position(pos).Filename
		edits[f] = append(edits[f], edit{fset.Position(pos).Offset, fset.Position(end).Offset, text})
	}
	qual := func(useFile string, obj types.Object) string {
		up := pkgOf[filepath.Base(useFile)]
		dp, _ := newPkg(obj.Pos())
		if up != dp && dp != "" {
			return dp + "."
		}
		if up != dp && dp == "" && *entryName != "" {
			return *entryName + "."
		}
		return ""
	}
	var reports []string
	var fieldDefs []*ast.Ident
	for _, f := range p.Syntax {
		fname := fset.Position(f.Pos()).Filename
		entry := pkgOf[filepath.Base(fname)] == ""
		handled := map[*ast.Ident]bool{}
		// method declarations on the receiver outside the entry: func (m *Module) x(a) -> func x(m *core.Base, a)
		for _, d := range f.Decls {
			fd, ok := d.(*ast.FuncDecl)
			if !ok || fd.Recv == nil || entry {
				continue
			}
			obj := p.TypesInfo.Defs[fd.Name]
			if !isRecvMethod(obj) {
				continue
			}
			rname := "m"
			if len(fd.Recv.List[0].Names) > 0 {
				rname = fd.Recv.List[0].Names[0].Name
			}
			add(fd.Recv.Pos(), fd.Name.End(), nameOf(obj))
			handled[fd.Name] = true
			params := fd.Type.Params
			first := rname + " *core.Base"
			if len(params.List) > 0 {
				first += ", "
			}
			add(params.Opening+1, params.Opening+1, first)
			// unnamed parameters cannot follow the named base: name them _
			for _, fl := range params.List {
				if len(fl.Names) == 0 {
					add(fl.Type.Pos(), fl.Type.Pos(), "_ ")
				}
			}
		}
		ast.Inspect(f, func(n ast.Node) bool {
			switch n := n.(type) {
			case *ast.CallExpr:
				sel, ok := n.Fun.(*ast.SelectorExpr)
				if !ok {
					return true
				}
				obj := p.TypesInfo.Uses[sel.Sel]
				if obj == nil || !isRecvMethod(obj) {
					return true
				}
				dp, _ := newPkg(obj.Pos())
				if dp == "" { // a method that stays on the entry type
					return true
				}
				base := exprString(fset, sel.X)
				if entry {
					base += ".b"
				}
				sep := ", "
				if len(n.Args) == 0 {
					sep = ""
				}
				add(n.Fun.Pos(), n.Lparen+1, qual(fname, obj)+nameOf(obj)+"("+base+sep)
				handled[sel.Sel] = true
			case *ast.SelectorExpr:
				obj := p.TypesInfo.Uses[n.Sel]
				if obj == nil {
					return true
				}
				if v, ok := obj.(*types.Var); ok && v.IsField() && v.Name() == "rt" && !entry && ownField(v) {
					add(n.Sel.Pos(), n.Sel.End(), "RT")
				}
			}
			return true
		})
		ast.Inspect(f, func(n ast.Node) bool {
			id, ok := n.(*ast.Ident)
			if !ok || handled[id] {
				return true
			}
			if obj := p.TypesInfo.Defs[id]; obj != nil && needExport[obj] {
				if obj.Parent() == p.Types.Scope() {
					add(id.Pos(), id.End(), nameOf(obj))
					return true
				}
				if v, ok := obj.(*types.Var); ok && v.IsField() {
					add(id.Pos(), id.End(), nameOf(obj))
					fieldDefs = append(fieldDefs, id)
					return true
				}
				if _, ok := obj.(*types.Func); ok {
					add(id.Pos(), id.End(), nameOf(obj))
					return true
				}
			}
			if obj := p.TypesInfo.Uses[id]; obj != nil && needExport[obj] && obj.Parent() != p.Types.Scope() && !isRecvMethod(obj) {
				add(id.Pos(), id.End(), nameOf(obj))
				return true
			}
			obj := p.TypesInfo.Uses[id]
			if obj == nil || obj.Pkg() != p.Types || obj == recvType {
				return true
			}
			if isRecvMethod(obj) {
				if dp, _ := newPkg(obj.Pos()); dp != "" {
					reports = append(reports, fmt.Sprintf("%s: method value %s", fset.Position(id.Pos()), obj.Name()))
				}
				return true
			}
			if obj.Parent() != p.Types.Scope() {
				return true
			}
			q := qual(fname, obj)
			if q != "" || needExport[obj] {
				add(id.Pos(), id.End(), q+nameOf(obj))
			}
			return true
		})
	}
	for _, f := range p.Syntax {
		ast.Inspect(f, func(n ast.Node) bool {
			fl, ok := n.(*ast.Field)
			if !ok || fl.Tag != nil {
				return true
			}
			for _, nm := range fl.Names {
				for _, d := range fieldDefs {
					if d == nm {
						add(fl.End(), fl.End(), " `json:\"-\"`")
						return true
					}
				}
			}
			return true
		})
	}
	var exported []string
	for o := range needExport {
		exported = append(exported, fmt.Sprintf("%s %s -> %s", fileOf(o.Pos()), o.Name(), nameOf(o)))
	}
	sort.Strings(exported)
	fmt.Println("EXPORTED", len(exported))
	for _, e := range exported {
		fmt.Println("  ", e)
	}
	sort.Strings(reports)
	fmt.Println("METHOD VALUES (wire by hand)", len(reports))
	for _, r := range reports {
		fmt.Println("  ", r)
	}
	if !*apply {
		return
	}
	for f, es := range edits {
		data, err := os.ReadFile(f)
		if err != nil {
			panic(err)
		}
		uniq := map[edit]bool{}
		var dedup []edit
		for _, e := range es {
			if !uniq[e] {
				uniq[e] = true
				dedup = append(dedup, e)
			}
		}
		es = dedup
		sort.Slice(es, func(i, j int) bool { return es[i].start > es[j].start })
		out := string(data)
		last := len(out) + 1
		var prev edit
		for _, e := range es {
			if e.end > last {
				fmt.Fprintln(os.Stderr, "overlap in", f, e, "with", prev)
				os.Exit(1)
			}
			prev = e
			out = out[:e.start] + e.text + out[e.end:]
			last = e.start
		}
		if err := os.WriteFile(f, []byte(out), 0o644); err != nil {
			panic(err)
		}
	}
}

func exprString(fset *token.FileSet, e ast.Expr) string {
	switch e := e.(type) {
	case *ast.Ident:
		return e.Name
	case *ast.SelectorExpr:
		return exprString(fset, e.X) + "." + e.Sel.Name
	}
	return "?"
}
