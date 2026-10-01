FROM golang:1.25-alpine AS build
WORKDIR /src
RUN apk add --no-cache git
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/shell .

# 基底必须带 /bin/sh 与 wget：平台健康检查是 CMD-SHELL
FROM alpine:3.20
RUN apk add --no-cache wget ca-certificates tzdata
WORKDIR /app
COPY --from=build /out/shell /app/shell
# shell.Main 从工作目录读自己的 component.yaml 取 deployment.port（/healthz 端口）
COPY component.yaml /app/component.yaml
ENTRYPOINT ["/app/shell"]
