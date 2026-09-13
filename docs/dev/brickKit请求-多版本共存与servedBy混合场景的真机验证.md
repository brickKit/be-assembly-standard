# brickKit 请求：多版本共存 + servedBy 混合部署场景，想请你们真机验证一遍

> **这份文档是一次性的**：只针对一组具体场景的真机验证请求，验证完之后可以直接删掉——跟 `给brickKit的反馈.md` 那份长期文档性质不一样，学的是你们自己那份"回复"文档的做法。

## 背景

我们（brickKit 这边）在完成 `servedBy` 设计之后，推演了几个"版本迁移期间，一部分组件被外壳收编、一部分独立部署，版本还参差不齐"的场景，想在真正开工前确认这些场景不会踩坑。代码层面的推导（依赖图、cascade、`internal/shell` 的合并逻辑）已经过了一遍，结论是这些场景本来就该被现有的"精确版本 + 版本化服务名"机制正确处理，不需要为 `servedBy` 单独加机制——但这类"看起来在代码里是对的"结论，你们过去已经用真实部署数据纠正过我们一次（环境变量合并那次），所以这次想请你们在真机上把这几个场景真的跑一遍，而不是只信我们的推导。

## 想请你们验证的三个场景

### 场景一：同一个组件的两个版本，一个被外壳收编，一个独立部署

```yaml
components:
  - id: infra/shell-go-core
    version: 1.0.0
    image: brickenterprise/be-shell-go:1.0.0
    healthCheck: { path: /healthz }
    deployment: { port: 9000 }

  - id: mdm/customer
    version: 1.0.7          # 旧版本，servedBy 上线之前就有的调用方还没升级
    deployment: { port: 8080 }

  - id: mdm/customer
    version: 2.0.0          # 新版本，收编进外壳
    servedBy: infra/shell-go-core@1.0.0
    deployment: { port: 8081 }

  - id: erp/legacy-caller
    version: 1.0.0           # 依赖旧版本，不需要跟着 servedBy 一起改
  - id: erp/new-caller
    version: 1.0.0           # 依赖新版本，走外壳
```

**想请你们确认**：`erp/legacy-caller` 拿到的 `MDM_CUSTOMER_ENDPOINT` 指向 `mdm-customer-1-0-7` 自己的独立地址，`erp/new-caller` 拿到的同名变量指向外壳（`infra-shell-go-core-1-0-0` 的地址、端口是 8081）——两边互不干扰，`erp/legacy-caller` 完全不需要因为 `mdm/customer` 升级并被收编而改任何一行配置。

### 场景二：同一个外壳，同时收编同一个组件的两个不同版本

```yaml
components:
  - id: infra/shell-go-core
    version: 1.0.0
    ...

  - id: mdm/customer
    version: 1.0.7
    servedBy: infra/shell-go-core@1.0.0
    deployment: { port: 8080 }

  - id: mdm/customer
    version: 2.0.0
    servedBy: infra/shell-go-core@1.0.0
    deployment: { port: 8081 }   # 必须跟 1.0.7 用不同端口，否则外壳里两份代码抢同一个端口
```

**想请你们确认**：这种"迁移期间外壳里同时跑两个版本"的用法在真实的 Go/Python 外壳启动器里能不能正常工作——两个版本各自监听自己声明的端口，各自的依赖端点正确合并进外壳环境，互不覆盖。如果你们的外壳启动器目前的模块注册表是按组件 ID（不带版本）做键的，这个场景可能会直接撞车，值得提前确认。

### 场景三（预期会被拒绝，想请你们确认报错清楚）：同一个精确版本，既想被外壳收编又想独立部署

```yaml
components:
  - id: mdm/customer
    version: 1.0.7
    servedBy: infra/shell-go-core@1.0.0
  - id: mdm/customer
    version: 1.0.7             # 同一个 ID+版本重复声明——现有校验应该直接拒绝
```

**我们的结论**：这个场景做不到，而且不应该做到——`brickkit.yaml` 里同一个 `(ID, 精确版本)` 只能出现一次，这是现有校验（不是 `servedBy` 新加的规则）。真的需要"同一份代码，一部分调用方走外壳、一部分走独立实例"，正确做法是发布两个版本号，而不是让一个版本号同时代表两种部署形态。**这条我们会写进指南文档里明确说清楚**，不需要你们额外测试，只是想说明我们已经想过这一种、并且认为它是设计上刻意的边界，不是遗漏。

## 想请你们做的事

用真实的 Go/Python 外壳启动器 + 真实的 K8s/Docker 部署，把场景一和场景二各跑一遍，确认：
1. 地址解析结果跟上面描述的一致；
2. 外壳启动器代码本身能不能正常处理"同一个组件 ID 出现两次、版本不同"这种情况（这一步跟 brickKit 平台生成的东西无关，是你们自己启动器内部模块注册表设计要不要考虑的问题）。

如果验证下来有任何跟预期不一致的地方，麻烦告诉我们，我们会在文档定稿前把这条边界重新梳理清楚。
