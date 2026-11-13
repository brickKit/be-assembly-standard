# 复盘 R2 的验证：代理答 404 时 git 回退能取到模块（2026-11-13）

格 `c10a-3` 的构建里公共代理没有答 404，回退没有被用上，所以另做一个最小实验：在 `golang:1.27.2-alpine` 容器里让代理地址必然答 404（`GOPROXY=https://proxy.golang.org/does-not-exist,direct`），取一个 brickKit 模块（`GONOSUMDB=github.com/brickKit/*`，与探针变体的构建相同；外壳另有 `go.sum` 校验）。

装了 git（`apk add --no-cache git`）：

```
# get https://proxy.golang.org/does-not-exist/github.com/brick%21kit/be-protocol/v3/@v/v3.0.0-alpha.130.info: 404 Not Found (0.454s)
cd /go/pkg/mod/cache/vcs/5064a…; git ls-remote -q --end-of-options https://github.com/brickKit/be-protocol
	"Version": "v3.0.0-alpha.130",
	"Dir": "/go/pkg/mod/github.com/brick!kit/be-protocol/v3@v3.0.0-alpha.130",
```

新容器、不装 git（对照）：

```
	"Version": "v3.0.0-alpha.130",
	"Error": "github.com/brickKit/be-protocol/v3@v3.0.0-alpha.130: unable to resolve git version: failed to execute git version: exec: \"git\": executable file not found in $PATH"
```

命令：`docker run --rm golang:1.27.2-alpine sh -c 'apk add --no-cache git; cd /tmp && go mod init x; GOPROXY=https://proxy.golang.org/does-not-exist,direct GONOSUMDB=github.com/brickKit/* go mod download -json github.com/brickKit/be-protocol/v3@v3.0.0-alpha.130'`（对照去掉 `apk add`）。
