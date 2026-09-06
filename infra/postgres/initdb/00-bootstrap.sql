-- 只做「带外容器在 be-ops 产出 2 之前就需要的那一点点」，不是建库脚本。
--
-- 为什么需要它：Casdoor（带外容器）在 make up（Task 3）时就要连
-- dbname=brickkit_db、search_path=casdoor 建自己的表，而 62 个组件的
-- schema / role / 归档 schema / 5 个外壳登录角色由 be-ops 产出 2 生成
-- （Task 8），排在 make up 之后。少了这个文件，第一次 make up 的症状是
-- Casdoor 容器反复重启，日志里是 "no schema has been selected to create in"
-- —— 而 PostgreSQL 自己 healthy，看起来像 Casdoor 的毛病。
--
-- ⚠️ 边界：本文件只建「一个 database + 两个非组件 schema」。
--    组件的 schema / role 一律归 be-ops 产出 2，不许往这里加。
--    判据：这里出现的东西必须是「带外容器要用的」，带外容器只有
--    Casdoor 与它的替换件 Keycloak（总纲 §2.2 末尾那两个非组件 schema）。
--
-- ⚠️ 它只在 pg_data 卷为空时跑一次（PostgreSQL 官方 initdb 机制）。
--    卷已存在时不会重跑，所以 be-ops 产出 2 的脚本必须全程 IF NOT EXISTS，
--    两者共存不冲突。

CREATE DATABASE brickkit_db;

\connect brickkit_db

-- Casdoor（slot:iam 的默认实现所依赖的带外容器）
CREATE SCHEMA IF NOT EXISTS casdoor;

-- Keycloak（slot:iam 的替换件，profile=keycloak 时才起，但 schema 先备好，
-- 免得换槽那天还要记得回来手动建一个）
CREATE SCHEMA IF NOT EXISTS keycloak;
