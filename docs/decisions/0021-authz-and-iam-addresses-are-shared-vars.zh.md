[English](0021-authz-and-iam-addresses-are-shared-vars.md) · [中文](0021-authz-and-iam-addresses-are-shared-vars.zh.md)

# 0021 authz 与 iam 的地址是共享变量，不是依赖

## 决策

没有任何组件把 `infra/authz` 或 IAM 组件声明为依赖。组件从 `AUTHZ_BUNDLE_URL` 读取权限 bundle 地址，从 `IAM_JWKS_URL` 读取身份提供方的签名公钥地址。两者都只在 `config/vars.yaml` 中设置一次，各组件的配置用 `$var:AUTHZ_BUNDLE_URL` / `$var:IAM_JWKS_URL` 引用，不同拓扑在部署文件的 `vars:` 中覆盖（见[配置约定](../conventions/configuration.zh.md#依赖地址)）。

## 理由

依赖锁定的是精确版本。如果每个组件都对 authz 和 iam 建依赖边，它们任何一个发版都会迫使所有组件跟着发版。IAM 还是一个槽位：依赖边会把实现的名字带进变量（`INFRA_IAM_CASDOOR_ENDPOINT`），从 Casdoor 换到另一个 OIDC 提供方就要改每一个组件。组件用发布的公钥在本地验签，并且能容忍 authz 尚未启动（[0005](0005-local-permission-bundle.zh.md)），所以不需要平台为它们安排启动顺序。

## 挡下什么

- 在组件的 `dependencies.components` 下加 `infra/authz@x.y.z` 或 `infra/iam-casdoor@x.y.z`
- 在组件代码里读取 `INFRA_AUTHZ_ENDPOINT` 或 `INFRA_IAM_CASDOOR_ENDPOINT`
- 共享值适用时，在某个组件的 `config/<scope>-<name>.yaml` 里写死 authz 或 iam 的 URL
- 每个请求都调用 IAM 组件校验 token
- 指望平台先启动 authz 或 iam，再启动其他组件

## 何时重新讨论

brickKit 提供一种既不锁定精确版本、也不把实现名带进注入变量的依赖类型时。
