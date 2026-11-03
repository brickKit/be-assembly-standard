// Package spike answers two questions about Traefik's Yaegi plugins (foundations item 2, T2): can one call a gRPC
// unary method over mTLS with only the standard library (gRPC framing over HTTP/2 written by hand), and does the
// package's state survive a dynamic configuration reload (each reload calls New again)?
package spike

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"sync"
	"sync/atomic"
)

// Config names the gRPC server and the certificate files.
type Config struct {
	Target string `json:"target,omitempty"`
	Cert   string `json:"cert,omitempty"`
	Key    string `json:"key,omitempty"`
	CA     string `json:"ca,omitempty"`
}

// CreateConfig returns the default configuration.
func CreateConfig() *Config { return &Config{} }

var (
	packageID = randomID() // set once per interpretation of the package
	hits      atomic.Int64
	news      atomic.Int64
	clientMu  sync.Mutex
	client    *http.Client
)

func randomID() string {
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

type mw struct {
	next     http.Handler
	cfg      *Config
	instance string
}

// New builds the middleware; a reload builds it again.
func New(_ context.Context, next http.Handler, cfg *Config, _ string) (http.Handler, error) {
	news.Add(1)
	return &mw{next: next, cfg: cfg, instance: randomID()}, nil
}

func (m *mw) httpClient() (*http.Client, error) {
	clientMu.Lock()
	defer clientMu.Unlock()
	if client != nil {
		return client, nil
	}
	pair, err := tls.LoadX509KeyPair(m.cfg.Cert, m.cfg.Key)
	if err != nil {
		return nil, err
	}
	pem, err := os.ReadFile(m.cfg.CA)
	if err != nil {
		return nil, err
	}
	roots := x509.NewCertPool()
	roots.AppendCertsFromPEM(pem)
	tr := &http.Transport{ForceAttemptHTTP2: true, TLSClientConfig: &tls.Config{
		Certificates: []tls.Certificate{pair}, RootCAs: roots, ServerName: "spike.component.test", MinVersion: tls.VersionTLS12}}
	client = &http.Client{Transport: tr}
	return client, nil
}

// check calls grpc.health.v1.Health/Check{service: name} and returns the status enum and the grpc-status.
func (m *mw) check(ctx context.Context, name string) (int, string, string, error) {
	c, err := m.httpClient()
	if err != nil {
		return 0, "", "", err
	}
	msg := append([]byte{0x0a, byte(len(name))}, name...) // field 1, length-delimited
	frame := make([]byte, 5+len(msg))
	binary.BigEndian.PutUint32(frame[1:5], uint32(len(msg)))
	copy(frame[5:], msg)
	req, err := http.NewRequestWithContext(ctx, "POST", m.cfg.Target+"/grpc.health.v1.Health/Check", bytes.NewReader(frame))
	if err != nil {
		return 0, "", "", err
	}
	req.Header.Set("Content-Type", "application/grpc")
	req.Header.Set("TE", "trailers")
	resp, err := c.Do(req)
	if err != nil {
		return 0, "", "", err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return 0, "", "", err
	}
	gs := resp.Trailer.Get("Grpc-Status")
	if gs == "" {
		gs = resp.Header.Get("Grpc-Status") // trailers-only answer
	}
	status := -1
	if len(body) >= 5 {
		n := binary.BigEndian.Uint32(body[1:5])
		p := body[5 : 5+n]
		if len(p) >= 2 && p[0] == 0x08 { // field 1, varint
			status = int(p[1])
		} else if len(p) == 0 {
			status = 0
		}
	}
	return status, gs, resp.Proto, nil
}

func (m *mw) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	h := hits.Add(1)
	w.Header().Set("X-Package", packageID)
	w.Header().Set("X-Instance", m.instance)
	w.Header().Set("X-Hits", strconv.FormatInt(h, 10))
	w.Header().Set("X-News", strconv.FormatInt(news.Load(), 10))
	if r.URL.Path == "/spike/grpc" {
		status, gs, proto, err := m.check(r.Context(), r.URL.Query().Get("service"))
		if err != nil {
			http.Error(w, "grpc call failed: "+err.Error(), http.StatusBadGateway)
			return
		}
		fmt.Fprintf(w, "proto=%s grpc-status=%s serving-status=%d\n", proto, gs, status)
		return
	}
	fmt.Fprintln(w, "state") // the spike answers itself; the next handler is not needed
}
