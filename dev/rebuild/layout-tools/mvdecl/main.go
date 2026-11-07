// mvdecl moves top-level declarations (with their doc comments) from one Go file to another in the same directory.
// Usage: mvdecl <from.go> <to.go> NAME [NAME ...]; a name inside a const/var group moves the whole group.
package main

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"sort"
	"strings"
)

func main() {
	src, dst, names := os.Args[1], os.Args[2], os.Args[3:]
	data, err := os.ReadFile(src)
	if err != nil {
		panic(err)
	}
	fset := token.NewFileSet()
	f, err := parser.ParseFile(fset, src, data, parser.ParseComments)
	if err != nil {
		panic(err)
	}
	type rng struct{ s, e int }
	var picks []rng
	for _, n := range names {
		found := false
		for _, d := range f.Decls {
			var doc *ast.CommentGroup
			match := false
			switch d := d.(type) {
			case *ast.FuncDecl:
				doc, match = d.Doc, d.Name.Name == n
			case *ast.GenDecl:
				doc = d.Doc
				for _, s := range d.Specs {
					switch s := s.(type) {
					case *ast.TypeSpec:
						match = match || s.Name.Name == n
					case *ast.ValueSpec:
						for _, id := range s.Names {
							match = match || id.Name == n
						}
					}
				}
			}
			if !match {
				continue
			}
			start := d.Pos()
			if doc != nil {
				start = doc.Pos()
			}
			picks = append(picks, rng{fset.Position(start).Offset, fset.Position(d.End()).Offset})
			found = true
			break
		}
		if !found {
			fmt.Fprintln(os.Stderr, "not found:", n)
			os.Exit(1)
		}
	}
	sort.Slice(picks, func(i, j int) bool { return picks[i].s > picks[j].s })
	var moved []string
	out := string(data)
	seen := map[int]bool{}
	for _, p := range picks {
		if seen[p.s] {
			continue
		}
		seen[p.s] = true
		moved = append([]string{out[p.s:p.e]}, moved...)
		out = out[:p.s] + out[p.e:]
	}
	if err := os.WriteFile(src, []byte(out), 0o644); err != nil {
		panic(err)
	}
	var head string
	if old, err := os.ReadFile(dst); err == nil {
		head = strings.TrimRight(string(old), "\n") + "\n"
	} else {
		head = "package " + f.Name.Name + "\n"
	}
	if err := os.WriteFile(dst, []byte(head+"\n"+strings.Join(moved, "\n\n")+"\n"), 0o644); err != nil {
		panic(err)
	}
}
