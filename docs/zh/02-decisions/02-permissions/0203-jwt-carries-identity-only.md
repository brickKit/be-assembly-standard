[English](../../../en/02-decisions/02-permissions/0203-jwt-carries-identity-only.md) · [中文](0203-jwt-carries-identity-only.md)

# 0203 token 只承载身份

## 决策

JWT 只说明用户是谁——`sub`、`roles[]`、`dept_path`、`org_id`——别的都不放。权限键一个都不进 token；每个角色能做什么，来自 bundle（[0202](0202-local-permission-bundle.md)）。

## 理由

身份随用户数增长，策略随角色数增长，各自放在能保持小的地方。超级管理员的全部权限键会撑爆 8 KB 的请求头上限：登录成功，之后每个请求都返回 `431`。放进 token 的权限也要等 token 过期才会变化。

## 挡下什么

- "把用户的权限 / scope 放进 JWT claims"
- 为了让权限键塞进 token 而发明的通配符或压缩方案
- 把特性开关或数据范围规则放进 token
- 在前端根据 token claims 判断能否访问，并把它当成安全措施

## 何时重新讨论

权限键永远不重新讨论。新增身份类 claim 可以，前提是本项目支持的每一种 IAM 实现都能签发它。
