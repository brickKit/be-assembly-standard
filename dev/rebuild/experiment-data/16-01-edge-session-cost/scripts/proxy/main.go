// The measurement's sidecar: the same per-request work as the plugin, then a reverse proxy to Traefik's inner
// entrypoint (the hairpin a sidecar behind a generated router needs).
package main

import (
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"sync"
	"time"
)

var cache sync.Map

func main() {
	token, _ := os.ReadFile(os.Args[1])
	sum := sha256.Sum256([]byte("measurement-session-cookie"))
	cache.Store(hex.EncodeToString(sum[:]), string(token))
	target, _ := url.Parse(os.Args[2])
	rp := httputil.NewSingleHostReverseProxy(target)
	rp.Transport = &http.Transport{MaxIdleConns: 1024, MaxIdleConnsPerHost: 1024, IdleConnTimeout: 90 * time.Second}
	h := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ck, err := r.Cookie("be_session")
		if err != nil {
			http.Error(w, "no session", http.StatusUnauthorized)
			return
		}
		sum := sha256.Sum256([]byte(ck.Value))
		tok, ok := cache.Load(hex.EncodeToString(sum[:]))
		if !ok {
			http.Error(w, "no token", http.StatusUnauthorized)
			return
		}
		r.Header.Set("Authorization", "Bearer "+tok.(string))
		rp.ServeHTTP(w, r)
	})
	srv := &http.Server{Addr: os.Args[3], Handler: h}
	panic(srv.ListenAndServe())
}
