// Package edgesession is the measurement's Yaegi middleware: the work an edge session layer does on every request
// with a cache hit (read the session cookie, hash it, look the token up, inject it), nothing else.
package edgesession

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"strings"
	"sync"
)

// Config is the middleware's configuration: the token cached for the measurement's one session.
type Config struct {
	Token string `json:"token,omitempty"`
}

// CreateConfig returns the default configuration.
func CreateConfig() *Config { return &Config{} }

var cache sync.Map // session hash -> token

type mw struct{ next http.Handler }

// New builds the middleware.
func New(_ context.Context, next http.Handler, cfg *Config, _ string) (http.Handler, error) {
	sum := sha256.Sum256([]byte("measurement-session-cookie"))
	cache.Store(hex.EncodeToString(sum[:]), strings.Repeat(cfg.Token, 1))
	return &mw{next: next}, nil
}

func (m *mw) ServeHTTP(w http.ResponseWriter, r *http.Request) {
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
	m.next.ServeHTTP(w, r)
}
