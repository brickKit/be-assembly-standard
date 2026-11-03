// The spike's gRPC server: the standard health service over mTLS that requires a client certificate signed by the
// spike's CA (the way a member's system surface admits callers, P8.5). "be.spike" is SERVING.
package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"log"
	"net"
	"os"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/health"
	healthpb "google.golang.org/grpc/health/grpc_health_v1"
	"google.golang.org/grpc/peer"
)

func main() {
	pair, err := tls.LoadX509KeyPair(os.Args[1], os.Args[2])
	if err != nil {
		log.Fatal(err)
	}
	pem, _ := os.ReadFile(os.Args[3])
	pool := x509.NewCertPool()
	pool.AppendCertsFromPEM(pem)
	creds := credentials.NewTLS(&tls.Config{Certificates: []tls.Certificate{pair}, ClientCAs: pool,
		ClientAuth: tls.RequireAndVerifyClientCert, MinVersion: tls.VersionTLS12})
	hs := health.NewServer()
	hs.SetServingStatus("be.spike", healthpb.HealthCheckResponse_SERVING)
	srv := grpc.NewServer(grpc.Creds(creds), grpc.ChainUnaryInterceptor(logCaller))
	healthpb.RegisterHealthServer(srv, hs)
	lis, err := net.Listen("tcp", os.Args[4])
	if err != nil {
		log.Fatal(err)
	}
	log.Fatal(srv.Serve(lis))
}

// logCaller prints the verified client certificate's subject of each call: the proof that mTLS was used.
func logCaller(ctx context.Context, req any, info *grpc.UnaryServerInfo, h grpc.UnaryHandler) (any, error) {
	if p, ok := peer.FromContext(ctx); ok {
		if ti, ok := p.AuthInfo.(credentials.TLSInfo); ok && len(ti.State.VerifiedChains) > 0 {
			log.Printf("call %s from verified client %s", info.FullMethod, ti.State.VerifiedChains[0][0].Subject.CommonName)
		}
	}
	return h(ctx, req)
}
