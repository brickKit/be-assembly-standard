# BrickEnterprise 基础资源一键管理。判据真相源：infra/resources.tsv
SHELL := /usr/bin/env bash
S     := infra/scripts

.DEFAULT_GOAL := help
.PHONY: help net check check-all

help:  ## 列出所有目标
	@awk 'BEGIN{FS=":.*##"; printf "\n用法: make <目标>\n\n"} \
	     /^[a-zA-Z0-9_-]+:.*##/ {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2} \
	     /^##@/ {printf "\n\033[1m%s\033[0m\n", substr($$0,5)}' $(MAKEFILE_LIST)
	@echo ""

##@ 基础资源
net:  ## 幂等创建 external network be-net
	@source $(S)/lib.sh && ensure_net

check: net  ## 一键查询：默认基础资源是否全部就绪
	@bash $(S)/check.sh default

check-all: net  ## 同上，把已启用的可选资源一起查
	@bash $(S)/check.sh all

##@ 基础资源（续）
up: net  ## 一键开启所有默认资源（已就绪的跳过；不符的报错中止）
	@bash $(S)/up.sh

down:  ## 停止本项目所有容器（不删 volume）
	@docker compose --env-file .env -p be-infra -f infra/docker-compose.infra.yml --profile "*" down
	@docker compose --env-file .env -p be-obs   -f infra/docker-compose.observability.yml down 2>/dev/null || true
	@echo "已停止（volume 保留）"

status:  ## 查看运行状态
	@docker compose --env-file .env -p be-infra -f infra/docker-compose.infra.yml --profile "*" ps
	@docker compose --env-file .env -p be-obs   -f infra/docker-compose.observability.yml ps 2>/dev/null || true

logs:  ## 跟日志：make logs SVC=postgres
	@test -n "$(SVC)" || { echo "用法：make logs SVC=<service>"; exit 1; }
	@docker logs -f --tail 200 "be-$(SVC)"

nuke:  ## 停止并删除所有 volume（危险，需二次确认）
	@read -r -p "输入 yes-delete-my-data 确认删除全部数据卷：" c; \
	 [[ "$$c" == "yes-delete-my-data" ]] || { echo "已取消"; exit 1; }; \
	 docker compose --env-file .env -p be-infra -f infra/docker-compose.infra.yml --profile "*" down -v; \
	 docker compose --env-file .env -p be-obs   -f infra/docker-compose.observability.yml down -v 2>/dev/null || true

##@ 可选资源（单个开关）
minio-up:     ; @bash $(S)/optional.sh minio up      ## 开启 MinIO（替换 RustFS）
minio-down:   ; @bash $(S)/optional.sh minio down    ## 关闭 MinIO
keycloak-up:  ; @bash $(S)/optional.sh keycloak up   ## 开启 Keycloak（替换 Casdoor）
keycloak-down:; @bash $(S)/optional.sh keycloak down ## 关闭 Keycloak
kafka-up:     ; @bash $(S)/optional.sh kafka up      ## 开启 Kafka（替换 NATS）
kafka-down:   ; @bash $(S)/optional.sh kafka down    ## 关闭 Kafka
rabbitmq-up:  ; @bash $(S)/optional.sh rabbitmq up   ## 开启 RabbitMQ（替换 NATS）
rabbitmq-down:; @bash $(S)/optional.sh rabbitmq down ## 关闭 RabbitMQ
nginx-up:     ; @bash $(S)/optional.sh nginx up      ## 开启 Nginx（替换 Traefik）
nginx-down:   ; @bash $(S)/optional.sh nginx down    ## 关闭 Nginx
obs-up:       ; @bash $(S)/optional.sh obs up        ## 开启可观测性 5 件套（整套）
obs-down:     ; @bash $(S)/optional.sh obs down      ## 关闭可观测性 5 件套（整套）

.PHONY: up down status logs nuke \
        minio-up minio-down keycloak-up keycloak-down kafka-up kafka-down \
        rabbitmq-up rabbitmq-down nginx-up nginx-down obs-up obs-down

##@ 全局册子
registry-check:  ## 校验端口册与 schema 册自洽
	@bash $(S)/registry-check.sh
.PHONY: registry-check

##@ 军火库
arsenal-check:  ## 检查 submodule 结构与 brickkit.yaml 是否自洽
	@bash $(S)/arsenal.sh check

arsenal-restore:  ## 把 enabled 与目录结构还原到与 brickkit.yaml 一致
	@bash $(S)/arsenal.sh restore
.PHONY: arsenal-check arsenal-restore

##@ 数据库
db-init:  ## 执行 be-ops 产出的建库脚本（幂等，可重跑）
	@cd tools/be-ops && go build -o build/be-ops ./cmd/be-ops
	@tools/be-ops/build/be-ops db-script --root . --out build/db-init.sql
	@set -a; . ./.env; set +a; \
	docker exec -i be-postgres psql -v ON_ERROR_STOP=1 -U postgres \
	  -v pw_shell_go_core="$$SHELL_GO_CORE_PASSWORD" \
	  -v pw_shell_go_backoffice="$$SHELL_GO_BACKOFFICE_PASSWORD" \
	  -v pw_shell_go_infra="$$SHELL_GO_INFRA_PASSWORD" \
	  -v pw_shell_py_brain="$$SHELL_PY_BRAIN_PASSWORD" \
	  -v pw_shell_py_render="$$SHELL_PY_RENDER_PASSWORD" \
	  -f - < build/db-init.sql
	@echo "✓ 建库脚本已执行（幂等，可重跑）"
.PHONY: db-init

##@ 门禁
gates:  ## 跑全部验收门禁：铁律六 import 扫描 + SystemClient 误用 + 裸 gin 路由（拆回门禁见阶段四）
	@cd tools/be-acceptance && go build -o build/be-acceptance ./cmd/be-acceptance
	@tools/be-acceptance/build/be-acceptance gate import-scan --root .
	@tools/be-acceptance/build/be-acceptance gate system-client-scan --root .
	@tools/be-acceptance/build/be-acceptance gate bare-gin-scan --root .
.PHONY: gates

docs-check:  ## 检查某个组件的四份文档：make docs-check REPO=mdm-customer
	@test -n "$(REPO)" || { echo "用法：make docs-check REPO=<仓库名>"; exit 1; }
	@bash $(S)/docs-check.sh "$(REPO)"
.PHONY: docs-check

##@ 验收
# ⚠️ 会真的临时停掉 postgres、跑一次 brickkit down/up——先确认没有别人在用。
tier0:  ## 档 0 六项验收，每加一个组件都要重跑（§9.6.1 档 4）
	@$(MAKE) -C tools/be-acceptance tier0
.PHONY: tier0
