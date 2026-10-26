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
seaweedfs-up: ; @bash $(S)/optional.sh seaweedfs up  ## 开启 SeaweedFS（替换 RustFS）
seaweedfs-down:; @bash $(S)/optional.sh seaweedfs down ## 关闭 SeaweedFS
keycloak-up:  ; @bash $(S)/optional.sh keycloak up   ## 开启 Keycloak（替换 Casdoor）
keycloak-down:; @bash $(S)/optional.sh keycloak down ## 关闭 Keycloak
kafka-up:     ; @bash $(S)/optional.sh kafka up      ## 开启 Kafka（替换 NATS）
kafka-down:   ; @bash $(S)/optional.sh kafka down    ## 关闭 Kafka
nginx-up:     ; @bash $(S)/optional.sh nginx up      ## 开启 Nginx（替换 Traefik）
nginx-down:   ; @bash $(S)/optional.sh nginx down    ## 关闭 Nginx
obs-up:       ; @bash $(S)/optional.sh obs up        ## 开启可观测性 5 件套（整套）
obs-down:     ; @bash $(S)/optional.sh obs down      ## 关闭可观测性 5 件套（整套）

.PHONY: up down status logs nuke \
        seaweedfs-up seaweedfs-down keycloak-up keycloak-down kafka-up kafka-down \
        nginx-up nginx-down obs-up obs-down

##@ 全局册子
registry-check:  ## 校验端口册与 schema 册自洽
	@bash $(S)/registry-check.sh

docs-boundary:  ## 正式文档不得链接 dev/ 或 archive/
	@python3 infra/scripts/docs-boundary.py

docs-diagrams:  ## No diagrams in developer documents; every diagram in customer documents is followed by its relations in text
	@python3 -I infra/scripts/docs-diagrams.py .

docs-mirror:  ## Mirror check across language trees; enabled only once a second language exists (D67: Chinese only for now)
	@python3 infra/scripts/docs-mirror.py

docs-links:  ## Local links and anchors in AGENTS.md, README.md and docs/; current documents never link archive/ or dev/
	@python3 tools/be-acceptance/doc-checks/links.py .

docs-ids:  ## Expectation IDs: one owner per prefix, unique, contiguous (check 33)
	@python3 tools/be-acceptance/doc-checks/33-expectation-ids.py .

docs-closure:  ## Required dependencies acyclic and customer combinations closed (check 34)
	@python3 tools/be-acceptance/doc-checks/34-dependency-closure.py .

docs-index:  ## Regenerate the component index (docs/zh/00-overview/09-component-index.md) from the catalog, cards and component.yaml files
	@python3 infra/scripts/component-index.py

docs-index-check:  ## The component index is up to date
	@python3 infra/scripts/component-index.py --check

prune:  ## 列出可以删的旧镜像与构建缓存（本项目能重新构建的；不动卷与别人的镜像）
	@python3 -I $(S)/prune-images.py
.PHONY: prune

prune-apply:  ## 删除 make prune 列出的（有格、运行器或构建在跑时自动跳过）
	@python3 -I $(S)/prune-images.py --apply
.PHONY: prune-apply

prune-timer:  ## 安装并启用每天的清理定时器（systemd 用户单元 be-prune，见 infra/systemd/）
	@mkdir -p $(HOME)/.config/systemd/user
	@ln -sf $(CURDIR)/infra/systemd/be-prune.service $(CURDIR)/infra/systemd/be-prune.timer $(HOME)/.config/systemd/user/
	@systemctl --user daemon-reload && systemctl --user enable --now be-prune.timer
	@systemctl --user list-timers be-prune.timer --no-pager
.PHONY: prune-timer

infra-images:  ## 基础资源的镜像都写确切版本与摘要，infra/resources.tsv 与 compose 一致
	@python3 -I infra/scripts/infra-images.py

security-schemas:  ## The security records' JSON Schemas in be-protocol are exactly what the field tables (security 09a, protocol 08) generate
	@python3 -I tools/be-acceptance/doc-checks/security-schemas.py --check tools/be-protocol/schemas/security

design-models:  ## Run every reference model in be-acceptance (about 15 minutes)
	@$(MAKE) -C tools/be-acceptance models
.PHONY: registry-check docs-boundary docs-diagrams docs-mirror docs-links docs-ids docs-closure docs-index docs-index-check infra-images security-schemas design-models

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

test-db-init:  ## 建/刷新本地测试专用库 brickkit_test_db（跟真机演示数据用的 brickkit_db 物理分开，幂等可重跑）。make test-db-init [ID=<id>]：带 ID 只跑这一个组件的 migrate-idempotent
	@bash infra/scripts/test-db-init.sh $(ID)
.PHONY: test-db-init

##@ 组件接入、真机验证与发布（integrate / verify / permissions 自己拿项目锁，见 infra/scripts/project-lock.sh）
integrate:  ## 接入一个组件或外壳：dev-env/db-init → add 或 upgrade → 填 config → 同步 deploy.teardown.yaml → lint → up --dry-run。make integrate ID=<id> [VERSION=2.0.0] [INTEGRATE_OUT=<日志目录>]（db-init 的详细输出进日志，终端只打结果行）
	@test -n "$(ID)" || { echo "用法：make integrate ID=<scope>/<name> [VERSION=<版本>]（外壳 ID=be/<name>，版本默认 1.0.0）"; exit 2; }
	@bash $(S)/integrate.sh "$(ID)" $(VERSION)

verify:  ## 真机验证一个组件或外壳：build → 只起闭包 → 迁移/健康/鉴权 → test-cross → [focus] → 收尾。make verify ID=<id> [ROUTE='GET /路径'] [FOCUS=1] [KEEP=1] [FORCE_BUILD=1] [SEED=1] [ROUTE_BODY='<JSON>']（只有 =1 才生效；SEED=1 在健康检查之后灌组件的 make seed；ROUTE_BODY 是受保护路由的请求体，经环境传入）
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
# The Go gates of the 0.x be-acceptance (import, SystemClient, bare-route, event and OpenAPI
# breaking changes, data-scope tests, dependency versions, config keys) moved to its legacy/v0
# branch with the old code (D59); conformance suites and gates return with the rebuilt tools.
gates: docs-boundary docs-diagrams docs-mirror docs-links docs-ids docs-closure docs-index-check infra-images security-schemas  ## Document gates (boundary, mirror, links, IDs, closure), infra image pins, security schemas + brickkit up --dry-run
	@echo "▸ brickkit up --dry-run"
	@bash $(S)/lib/require-brickkit.sh
	@brickkit up --dry-run
.PHONY: gates

version-check:  ## 扫全部 submodule（组件、外壳、工具仓库）：HEAD 是否领先最新 tag（兼容 2.0.0 与 v2.0.0 双 tag）
	@bash infra/scripts/version-check.sh
.PHONY: version-check

# bump-version (version propagation across dependants and shells) lived in the 0.x be-acceptance;
# it returns with the rebuilt tools. Until then follow docs/zh/01-conventions/10-development-workflow.md.

test-cross:  ## 组件局部测试：只跑 ID 一个组件，强依赖 gRPC 指向真实在跑的依赖容器（要求强依赖树在跑）。make test-cross ID=crm/opportunity [ARGS="-run TestX -v"]
	@test -n "$(ID)" || { echo "用法：make test-cross ID=<scope>/<name> [ARGS=\"go test 额外参数\"]"; exit 2; }
	@bash $(S)/test-cross.sh "$(ID)" $(ARGS)
.PHONY: test-cross

##@ 本地开发数据（只给本地用，不用于生产/CI；每个组件自己拥有种子数据，见 docs/zh/03-seed-data.md）
# Rebuilt components only, in dependency order; each component's `make seed` seeds its declared dependencies first and
# every seed is idempotent, so the repeats cost a few requests. Needs the components and the identity member up, and
# SEED_PASSWORD (the test users' password); the addresses default to the cell's host ports (see each cmd/seed).
seed-data:  ## 灌重建后组件的种子数据（测试账号、授权、主数据与交易链的组件），可重复跑；需要 SEED_PASSWORD 等（docs/zh/03-seed-data.md）
	@$(MAKE) -C components/infra/authz seed
	@$(MAKE) -C components/mdm/org seed
	@$(MAKE) -C components/mdm/currency seed
	@$(MAKE) -C components/mdm/partner seed
	@$(MAKE) -C components/mdm/product seed
	@$(MAKE) -C components/erp/inventory seed
	@$(MAKE) -C components/erp/credit seed
	@$(MAKE) -C components/erp/sales seed
	@$(MAKE) -C components/erp/billing seed
.PHONY: seed-data

seed-data-clean:  ## 主数据组件没有清除命令：说明怎样重置（docs/zh/03-seed-data.md）
	@echo "主数据组件没有清除命令（全状态事件已发出，删行会让消费者的投影对不上）。要清空某个组件："
	@echo "在开发库里删掉它的 schema（mdm_org、mdm_currency、mdm_partner、mdm_product），再 brickkit up 让迁移重建。"
.PHONY: seed-data-clean

# tier0/tier1/tier2 acceptance lived in the 0.x be-acceptance (legacy/v0); acceptance returns
# with the rebuilt components and conformance suites (protocols 18, 21).
