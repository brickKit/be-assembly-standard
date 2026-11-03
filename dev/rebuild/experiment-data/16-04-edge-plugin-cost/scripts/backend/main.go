// The measurement's backend: answers 200 with a small JSON body; on /b and /c it requires the injected token
// (the precondition that the session layer did its work), answering 401 otherwise.
package main

import (
	"net/http"
	"os"
	"strings"
)

func main() {
	token, _ := os.ReadFile(os.Args[1])
	want := "Bearer " + string(token)
	body := []byte(`{"id":"0190f3a1-0000-7000-8000-000000000001","status":"ok"}`)
	h := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasPrefix(r.URL.Path, "/a") && r.Header.Get("Authorization") != want {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write(body)
	})
	panic(http.ListenAndServe(os.Args[2], h))
}
