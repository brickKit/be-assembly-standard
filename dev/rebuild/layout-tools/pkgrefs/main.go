package main

// pkgrefs prints, for each file of a package, the package-level names it uses that another file declares.
import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

func main() {
	dir := os.Args[1]
	fset := token.NewFileSet()
	pkgs, err := parser.ParseDir(fset, dir, func(fi os.FileInfo) bool { return !strings.HasSuffix(fi.Name(), "_test.go") }, 0)
	if err != nil {
		panic(err)
	}
	for _, p := range pkgs {
		declared := map[string]string{}
		for name, f := range p.Files {
			for _, d := range f.Decls {
				switch d := d.(type) {
				case *ast.FuncDecl:
					if d.Recv == nil {
						declared[d.Name.Name] = filepath.Base(name)
					} else if recvIsModule(d.Recv) {
						declared["m."+d.Name.Name] = filepath.Base(name)
					}
				case *ast.GenDecl:
					for _, s := range d.Specs {
						switch s := s.(type) {
						case *ast.TypeSpec:
							declared[s.Name.Name] = filepath.Base(name)
						case *ast.ValueSpec:
							for _, n := range s.Names {
								declared[n.Name] = filepath.Base(name)
							}
						}
					}
				}
			}
		}
		files := []string{}
		for name := range p.Files {
			files = append(files, name)
		}
		sort.Strings(files)
		for _, name := range files {
			f := p.Files[name]
			uses := map[string]map[string]bool{}
			ast.Inspect(f, func(n ast.Node) bool {
				if se, ok := n.(*ast.SelectorExpr); ok {
					if x, ok := se.X.(*ast.Ident); ok && x.Name == "m" {
						if from, ok := declared["m."+se.Sel.Name]; ok && from != filepath.Base(name) {
							if uses[from] == nil {
								uses[from] = map[string]bool{}
							}
							uses[from]["m."+se.Sel.Name] = true
						}
					}
				}
				if id, ok := n.(*ast.Ident); ok && id.Obj == nil {
					if from, ok := declared[id.Name]; ok && from != filepath.Base(name) {
						if uses[from] == nil {
							uses[from] = map[string]bool{}
						}
						uses[from][id.Name] = true
					}
				}
				return true
			})
			fmt.Printf("== %s\n", filepath.Base(name))
			froms := []string{}
			for k := range uses {
				froms = append(froms, k)
			}
			sort.Strings(froms)
			for _, k := range froms {
				ns := []string{}
				for n := range uses[k] {
					ns = append(ns, n)
				}
				sort.Strings(ns)
				fmt.Printf("   %s: %s\n", k, strings.Join(ns, " "))
			}
		}
	}
}

// recvIsModule: a method of Module (the flat package's receiver), by value or pointer.
func recvIsModule(r *ast.FieldList) bool {
	if r == nil || len(r.List) != 1 {
		return false
	}
	t := r.List[0].Type
	if st, ok := t.(*ast.StarExpr); ok {
		t = st.X
	}
	id, ok := t.(*ast.Ident)
	return ok && id.Name == "Module"
}
