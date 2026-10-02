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

docs-boundary:  ## 正式文档不得链接 dev/ 或 archive/
	@python3 infra/scripts/docs-boundary.py

docs-mirror:  ## 项目文档 docs/en/ 与 docs/zh/ 逐文件对应：路径相同、二级标题数相同、第一行互链
	@python3 infra/scripts/docs-mirror.py
.PHONY: registry-check docs-boundary docs-mirror

##@ 校验
lint:  ## brickKit 自身的三层 + 文档检查（严格模式）
	@bash $(S)/lib/require-brickkit.sh
	@brickkit lint --strict

docs-check:  ## 只检查一个组件或外壳：make docs-check ID=mdm/customer | ID=be/go-core（整个项目用 make lint）
	@test -n "$(ID)" || (echo "用法：make docs-check ID=<scope>/<name>（外壳：ID=be/<name>）"; exit 2)
	@bash $(S)/lib/require-brickkit.sh
	@brickkit lint --strict $(ID)
.PHONY: lint docs-check

##@ 数据库
db-init:  ## 执行 be-ops 产出的建库脚本（幂等，可重跑；.env 缺密码时报错并提示 make dev-env）
	@bash $(S)/db-init.sh

dev-env:  ## 补齐 .env 里各数据库登录角色的随机密码（只追加缺失项，不覆盖，只打印变量名）
	@bash $(S)/dev-env.sh
.PHONY: db-init dev-env

test-db-init:  ## 建/刷新本地测试专用库 brickkit_test_db（跟真机演示数据用的 brickkit_db 物理分开，幂等可重跑）
	@bash infra/scripts/test-db-init.sh
.PHONY: test-db-init

##@ 组件接入、真机验证与发布（integrate / verify / permissions 自己拿项目锁，见 infra/scripts/project-lock.sh）
integrate:  ## 接入一个组件或外壳：dev-env/db-init → add 或 upgrade → 填 config → 同步 deploy.teardown.yaml → lint → up --dry-run。make integrate ID=<id> [VERSION=2.0.0] [INTEGRATE_OUT=<日志目录>]（db-init 的详细输出进日志，终端只打结果行）
	@test -n "$(ID)" || { echo "用法：make integrate ID=<scope>/<name> [VERSION=<版本>]（外壳 ID=be/<name>，版本默认 1.0.0）"; exit 2; }
	@bash $(S)/integrate.sh "$(ID)" $(VERSION)

verify:  ## 真机验证一个组件或外壳：build → 只起闭包 → 迁移/健康/鉴权 → test-cross → [focus] → 收尾。make verify ID=<id> [ROUTE='GET /路径'] [FOCUS=1] [KEEP=1] [FORCE_BUILD=1] [SEED=1]（只有 =1 才生效；SEED=1 在健康检查之后灌组件的 make seed）
	@test -n "$(ID)" || { echo "用法：make verify ID=<scope>/<name> [ROUTE='<METHOD> <路径>'] [FOCUS=1] [KEEP=1] [FORCE_BUILD=1] [SEED=1] [OUT=<目录>]"; exit 2; }
	@ROUTE="$(ROUTE)" FOCUS="$(FOCUS)" KEEP="$(KEEP)" FORCE_BUILD="$(FORCE_BUILD)" SEED="$(SEED)" OUT="$(OUT)" bash $(S)/verify-component.sh "$(ID)"

ship:  ## 【只有控制者】发布：发布前门禁（openapi-additive-scan、config-key-scan --strict，只看本组件）→ 推 main → 契约包 tag → brickkit release → v tag → 外壳视角拉取检查。make ship DIR=components/<id>|shell/be/<name> NOTES=<说明文件> [DRY_RUN=1]
	@test -n "$(DIR)" -a -n "$(NOTES)" || { echo "用法：make ship DIR=<components/<scope>/<name> | shell/be/<name>> NOTES=<发布说明文件> [DRY_RUN=1]"; exit 2; }
	@bash $(S)/ship.sh $(if $(DRY_RUN),--dry-run,) "$(DIR)" "$(NOTES)"

teardown-sync:  ## 让 deploy.teardown.yaml 与 deploy.yaml 一致（target、components；不带 vars:）。make teardown-sync [CHECK=1] 只核对
	@bash $(S)/project-lock.sh -- python3 $(S)/teardown-sync.py $(if $(CHECK),--check,)

permissions:  ## 从各组件 assembly.yaml 重新产出 registry/permissions.tsv 与 data-scopes.tsv，再 registry-check；permissions.tsv 相对 HEAD 只增不删
	@bash $(S)/project-lock.sh -- $(MAKE) --no-print-directory _permissions-locked

_permissions-locked:
	@set -euo pipefail; \
	  (cd tools/be-ops && go build -o build/be-ops ./cmd/be-ops); \
	  tools/be-ops/build/be-ops permissions --root .; \
	  tools/be-ops/build/be-ops data-scopes --root .; \
	  $(MAKE) --no-print-directory registry-check; \
	  removed="$$(git diff HEAD -- registry/permissions.tsv | grep '^-[^-]' || true)"; \
	  if [ -n "$$removed" ]; then echo "✗ registry/permissions.tsv 只增不删，下面这些已有行被改或删了（键是持久标识，退役用 deprecated 列）："; echo "$$removed"; exit 1; fi; \
	  echo "✓ registry/permissions.tsv 相对 HEAD 只有新增（git diff HEAD -- registry/ 看改动）"
.PHONY: integrate verify ship teardown-sync permissions _permissions-locked

##@ 拆回验证
# 同一份 brickkit.yaml，`--ignore-shells` 让所有成员忽略 servedBy、各自独立成容器；
# -f deploy.teardown.yaml 只读这一份部署文件、忽略本地模式；authz/iam 地址本来就是成员自己的服务名，不用覆盖。
# 不再临时改 brickkit.yaml，也就没有"事后恢复"这一步。
teardown-up:  ## 拆回验证：所有成员按独立组件部署（--ignore-shells + deploy.teardown.yaml）
	@bash $(S)/lib/require-brickkit.sh
	@brickkit up -f deploy.teardown.yaml --ignore-shells

teardown-down:  ## 停掉拆回验证的容器
	@bash $(S)/lib/require-brickkit.sh
	@brickkit down -f deploy.teardown.yaml
.PHONY: teardown-up teardown-down

##@ 门禁
gates: docs-boundary docs-mirror  ## 跑全部验收门禁：正式文档边界 + 中英文档树镜像 + 组件互不 import + SystemClient 误用 + 裸路由/裸 resolver + 事件契约破坏性变更 + 数据权限边界测试缺失 + 依赖版本号漂移（外壳 go.mod 钉与镜像 tag）+ 配置里的版本化服务名与 brickkit.yaml 一致 + configSchema 键名（大写下划线、不撞保留名；1.x 组件只警告）+ OpenAPI 契约相对上一个发布 tag 只增 + brickkit up --dry-run（brickKit 自带的依赖/钉/成员漂移检查）
	@cd tools/be-acceptance && go build -o build/be-acceptance ./cmd/be-acceptance
	@tools/be-acceptance/build/be-acceptance gate import-scan --root .
	@tools/be-acceptance/build/be-acceptance gate system-client-scan --root .
	@tools/be-acceptance/build/be-acceptance gate bare-route-scan --root .
	@tools/be-acceptance/build/be-acceptance gate events-breaking-scan --root .
	@tools/be-acceptance/build/be-acceptance gate data-scope-test-scan --root .
	@tools/be-acceptance/build/be-acceptance gate dependency-version-scan --root .
	@tools/be-acceptance/build/be-acceptance gate service-hostname-scan --root .
	@tools/be-acceptance/build/be-acceptance gate config-key-scan --root .
	@tools/be-acceptance/build/be-acceptance gate openapi-additive-scan --root .
	@echo "▸ brickkit up --dry-run（brickKit 自带的漂移检查：依赖/版本钉/外壳成员；不启动任何容器）"
	@bash $(S)/lib/require-brickkit.sh
	@brickkit up --dry-run
.PHONY: gates

version-check:  ## 扫全部 submodule（组件、外壳、工具仓库）：HEAD 是否领先最新 tag（兼容 2.0.0 与 v2.0.0 双 tag）
	@bash infra/scripts/version-check.sh
.PHONY: version-check

bump-version:  ## 自动传播一次版本升级（算出全部下游要跟着同步的组件+改好所有文件），不写盘先看计划：make bump-version PLAN=<计划文件>；确认后加 APPLY=1 真的落地。计划文件格式与完整流程见 .claude/skills/version-bump-ship/SKILL.md 与 docs/en/01-conventions/01-development-workflow.md
	@test -n "$(PLAN)" || { echo "用法：make bump-version PLAN=<计划文件> [APPLY=1]"; exit 1; }
	@cd tools/be-acceptance && go build -o build/be-acceptance ./cmd/be-acceptance
	@tools/be-acceptance/build/be-acceptance bump-version --root . --plan "$(PLAN)" $(if $(APPLY),--apply,)
.PHONY: bump-version

test-cross:  ## 组件局部测试：只跑 ID 一个组件，强依赖 gRPC 指向真实在跑的依赖容器（要求强依赖树在跑）。make test-cross ID=crm/opportunity [ARGS="-run TestX -v"]
	@test -n "$(ID)" || { echo "用法：make test-cross ID=<scope>/<name> [ARGS=\"go test 额外参数\"]"; exit 2; }
	@bash $(S)/test-cross.sh "$(ID)" $(ARGS)
.PHONY: test-cross

##@ 本地开发数据（只给本地用，不用于生产/CI；每个组件自己拥有种子数据，见 docs/en/03-seed-data.md）
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
	@echo "⚠️ erp-inventory/erp-finance 没有 seed-clean，只有 db-reset（entry_no_seq/post_no 等计数器只增不回退，LockPeriod 是终态——逐行 DELETE 做不到干净复原）：make -C components/erp/inventory db-reset / make -C components/erp/finance db-reset（会清空该组件全部数据，不止 seed 灌的那部分）"
	@echo "⚠️ infra-print 也没有 seed-clean——模板走版本管理，重跑 seed 只追加新版本，不需要撤销机制"
	@echo "✓ 其余组件的种子数据已清空"
.PHONY: seed-data-clean

##@ 验收
# ⚠️ 会真的临时停掉 postgres、跑一次 brickkit down/up——先确认没有别人在用。
tier0:  ## 档 0 六项验收，每加一个组件都要重跑
	@$(MAKE) -C tools/be-acceptance tier0
.PHONY: tier0

tier1:  ## 【占位】档 1 平台断言：v1 下整体重写，06f 之前不做任何事
	@echo "tier1 在 brickKit v1 下整体重写，推迟到 06f（platform/ 旧断言已随 be-acceptance 删除）；当前为占位，直接通过"
.PHONY: tier1

tier2:  ## 档 2 合并态专属断言，需要真实可达的 TEST_PG_DSN/TEST_NATS_URL
	@$(MAKE) -C tools/be-acceptance tier2
.PHONY: tier2
