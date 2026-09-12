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

test-db-init:  ## 建/刷新本地测试专用库 brickkit_test_db（跟真机演示数据用的 brickkit_db 物理分开，幂等可重跑）
	@bash infra/scripts/test-db-init.sh
.PHONY: test-db-init

##@ 门禁
gates:  ## 跑全部验收门禁：铁律六 import 扫描 + SystemClient 误用 + 裸路由/裸 resolver + 事件契约破坏性变更 + 数据权限边界测试缺失 + 依赖版本号漂移（拆回门禁见阶段四）
	@cd tools/be-acceptance && go build -o build/be-acceptance ./cmd/be-acceptance
	@tools/be-acceptance/build/be-acceptance gate import-scan --root .
	@tools/be-acceptance/build/be-acceptance gate system-client-scan --root .
	@tools/be-acceptance/build/be-acceptance gate bare-route-scan --root .
	@tools/be-acceptance/build/be-acceptance gate events-breaking-scan --root .
	@tools/be-acceptance/build/be-acceptance gate data-scope-test-scan --root .
	@tools/be-acceptance/build/be-acceptance gate dependency-version-scan --root .
.PHONY: gates

version-check:  ## 扫全部 submodule：HEAD 是否领先最新 tag（阶段三 Task 3，阶段二复盘 §4 第 1 条）
	@bash infra/scripts/version-check.sh
.PHONY: version-check

bump-version:  ## 自动传播一次版本升级（算出全部下游要跟着同步的组件+改好所有文件），不写盘先看计划：make bump-version PLAN=<计划文件>；确认后加 APPLY=1 真的落地。计划文件格式与完整流程见 00-master-guide.md SOP-W-11
	@test -n "$(PLAN)" || { echo "用法：make bump-version PLAN=<计划文件> [APPLY=1]"; exit 1; }
	@cd tools/be-acceptance && go build -o build/be-acceptance ./cmd/be-acceptance
	@tools/be-acceptance/build/be-acceptance bump-version --root . --plan "$(PLAN)" $(if $(APPLY),--apply,)
.PHONY: bump-version

docs-check:  ## 检查某个组件的四份文档：make docs-check REPO=mdm-customer
	@test -n "$(REPO)" || { echo "用法：make docs-check REPO=<仓库名>"; exit 1; }
	@bash $(S)/docs-check.sh "$(REPO)"
.PHONY: docs-check

test-cross:  ## 组件局部测试：只跑 REPO 一个组件，强依赖 gRPC 指向真实在跑的依赖容器（要求强依赖树在跑）。make test-cross REPO=crm-opportunity；带过滤直接 bash infra/scripts/test-cross.sh <repo> -run <名>
	@test -n "$(REPO)" || { echo "用法：make test-cross REPO=<仓库名>"; exit 1; }
	@bash $(S)/test-cross.sh "$(REPO)"
.PHONY: test-cross

##@ 本地开发数据（只给本地用，不用于生产/CI；每个组件自己拥有种子数据——总纲 SOP-W-7）
# ⚠️ 这里曾经是 infra/seed-data/ 的编排脚本（seed.sh/clean.sh）。等到每个
# 组件都有了自己的 make seed（且互不需要装配层帮它们传 id/sub——各自反查
# 依赖组件的 command_idempotency 表），编排层就只剩"按顺序调用谁"这一件
# 事，薄到直接写在这里就够了，不需要再维护一个单独的目录/脚本文件。
# ⚠️ 顺序不能乱：erp-inventory 必须先于 crm-opportunity——crm-opportunity
# 的 WON 商机会真实触发 erp-sales 自动建单确认（含 Reserve 库存），库存
# 不够会走 TCC 补偿建异常待办（不是失败，但不是"打开就是一条干净
# CONFIRMED 订单"这个演示效果）。erp-finance/infra-print 零依赖，谁先谁
# 后都行。
seed-data:  ## 灌本地开发/测试用的示例数据（身份+客户/产品+库存+订单+商机+财务凭证+打印模板），可重复跑
	@$(MAKE) -C components/mdm/customer seed
	@$(MAKE) -C components/mdm/product seed
	@$(MAKE) -C components/erp/inventory seed
	@$(MAKE) -C components/erp/sales seed
	@$(MAKE) -C components/crm/opportunity seed
	@$(MAKE) -C components/erp/finance seed
	@$(MAKE) -C components/infra/print seed
	@echo ""
	@echo "✓ 种子数据灌完了。登录方式：Casdoor 用户名 dev.superuser / 密码 DevSeed123!"
.PHONY: seed-data

seed-data-clean:  ## 清空 seed-data 能清的部分（见下方哪些组件没有 seed-clean）
	@$(MAKE) -C components/crm/opportunity seed-clean
	@$(MAKE) -C components/erp/sales seed-clean
	@$(MAKE) -C components/mdm/customer seed-clean
	@$(MAKE) -C components/mdm/product seed-clean
	@$(MAKE) -C components/infra/authz seed-clean
	@$(MAKE) -C components/infra/iam-casdoor seed-clean
	@echo ""
	@echo "⚠️ erp-inventory/erp-finance 没有 seed-clean，只有 db-reset（entry_no_seq/post_no 等计数器只增不回退，LockPeriod 是终态——逐行 DELETE 做不到干净复原，见总纲 SOP-W-7「delete 不是 reset」判据）：make -C components/erp/inventory db-reset / make -C components/erp/finance db-reset（会清空该组件全部数据，不止 seed 灌的那部分）"
	@echo "⚠️ infra-print 也没有 seed-clean——模板走版本管理，重跑 seed 只追加新版本，不需要撤销机制"
	@echo "✓ 其余组件的种子数据已清空"
.PHONY: seed-data-clean

##@ 验收
# ⚠️ 会真的临时停掉 postgres、跑一次 brickkit down/up——先确认没有别人在用。
tier0:  ## 档 0 六项验收，每加一个组件都要重跑（§9.6.1 档 4）
	@$(MAKE) -C tools/be-acceptance tier0
.PHONY: tier0

tier1:  ## 档 1 平台断言（brickKit 自身行为的回归测试，非业务），需要 brickkit up 先起好
	@$(MAKE) -C tools/be-acceptance tier1
.PHONY: tier1
