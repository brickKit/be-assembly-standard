// be/go-infra 外壳：成员由 shell.members 声明，这里的 Registry 必须与之一一对应。
package main

import "github.com/brickKit/be-sdk-go/shell"

func main() {
	shell.Main("be-go-infra", shell.Registry{})
}
