// A minimal SessionService (be.session.v1) for the cost measurement: every exchange answers the same token, valid
// for an hour, over TLS with the identity member's certificate; Ended answers nothing new.
package main

import (
	"context"
	"crypto/tls"
	"log"
	"net"
	"os"
	"time"

	"github.com/brickKit/be-sdk-go/v3/sessionpb"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
)

type iam struct {
	sessionpb.UnimplementedSessionServiceServer
	token string
}

func (s iam) Exchange(context.Context, *sessionpb.ExchangeRequest) (*sessionpb.ExchangeResponse, error) {
	now := time.Now()
	return &sessionpb.ExchangeResponse{AccessToken: s.token, Principal: "p", ExpiresAtMs: now.Add(time.Hour).UnixMilli(),
		SessionUntilMs: now.Add(2 * time.Hour).UnixMilli()}, nil
}

func (s iam) Ended(_ context.Context, in *sessionpb.EndedRequest) (*sessionpb.EndedResponse, error) {
	return &sessionpb.EndedResponse{Reset_: in.GetAfter() == nil, Next: &sessionpb.Cursor{Impl: "fake", Epoch: "1.1"}}, nil
}

func main() { // token file, cert, key, listen address
	tok, _ := os.ReadFile(os.Args[1])
	pair, err := tls.LoadX509KeyPair(os.Args[2], os.Args[3])
	if err != nil {
		log.Fatal(err)
	}
	srv := grpc.NewServer(grpc.Creds(credentials.NewTLS(&tls.Config{Certificates: []tls.Certificate{pair}})))
	sessionpb.RegisterSessionServiceServer(srv, iam{token: string(tok)})
	ln, err := net.Listen("tcp", os.Args[4])
	if err != nil {
		log.Fatal(err)
	}
	log.Fatal(srv.Serve(ln))
}
