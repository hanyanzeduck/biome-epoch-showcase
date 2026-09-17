# AGENTS.md

本文件定义 Biome Epoch 当前持续执行的 AI 辅助开发规则。

自项目进入规模化迭代和架构收口阶段后，开发流程逐步固定为：
**先理解现有系统 → 明确真源与边界 → 最小范围修改 → 复用既有架构 → 运行验证与回归测试。**

这些规则用于约束 Codex / Agent 在项目中的修改方式，避免随着项目规模扩大出现重复系统、数据真源分裂和跨模块回归。

## 1. 修改代码前

- 先阅读当前实现，不根据旧 Prompt 或旧版本直接修改。
- 优先采用满足需求的最小修改范围。
- 如果项目已经存在 Coordinator、Router、Component、Registry、Catalog、Adapter 等机制，优先复用。
- 不为同一职责重新创建平行系统。
- 跨模块修改前，先确认调用方、数据流和受影响边界。
- 已经稳定工作的能力默认保留，除非任务明确要求迁移或替换。

## 2. 玩法逻辑与表现层

- 2D 逻辑层是 Gameplay Source of Truth。
- 2.5D / 3D 表现层只消费逻辑状态，不反向成为玩法真源。
- 视觉偏移、噪声、平滑和渲染修复不能改写逻辑地形归属、玩法坐标、Task / Room 所有权等权威数据。

## 3. 世界生成

- 在 World Generation Version 兼容前提下，相同 Seed 应保持可确定性复现。
- 各随机阶段从 World Seed 派生自己的确定性随机流。
- 禁止在确定性世界生成或 Seed 驱动视觉逻辑中加入无 Seed 随机。
- Task Ownership 建立后，Room / Topology 阶段不得随意改写。
- Spawn 信息统一来自 `WorldGenResult`。
- 诊断指标与运行时有效性分开处理，Runtime Entry 以正式验证契约为准。

## 4. Creature 工作与搬运

- 复用 Action Coordinator、Reservation Lease、Retry Cooldown 和统一 Stop Reason。
- 行为持有 Reservation 时，所有放弃、失败、切换、目标失效路径都必须检查释放。
- 不为同一工作目标增加第二套 Ownership。
- 多 AI 竞争同一目标时，通过 Reservation 成功/失败和 Retry 处理。

## 5. 建筑能力

- 新建筑优先通过 `BuildingData`、Capability Config 和 Component 体系扩展。
- 已经统一过的能力不得重新建立第二配置真源。
- 修改持久化建筑逻辑时保留 Persistent ID 和现有 Save Boundary。

## 6. 存档

- 正式存档保存 Definition 引用 / Stable ID 与 Persistent State。
- Runtime State 在加载后重建。
- 不直接序列化实时 `SceneTree` 作为正式存档模型。
- 使用现有 Adapter / Codec 跨越存档边界。
- 保持 `.tmp`、`.bak`、原子替换和备份回退语义。
- 持久化结构变化时同步考虑 Schema Version 和 World Generation Version。
- Reservation、临时任务、运行时引用等不进入长期持久真源。

## 7. LAN 多人联机

- Shared World State 遵循 Host Authority。
- Client 不直接成为共享状态最终真源。
- 共享状态修改遵循：
  Client Proposal -> Host Validation -> Canonical Host Commit -> Replication。
- 保持 Authority Revision 与 Owner / Personal / Shared State 边界。
- 未完成验证的能力不得写成已实现功能。

## 8. UI 与输入

- Gameplay 输入继续通过 `PlayerInputController` 等既有入口。
- Modal 状态拥有输入优先级。
- Gameplay 通过 Router / Interface 与 UI 通信，不直接依赖具体页面节点。
- 不为同一类输入或 Modal 职责增加第二套入口。

## 9. Debug 与测试

- 全局 Debug 优先进入 `DebugSettings` / F10 Debug Hub。
- 修改核心系统后运行对应 Headless Regression Suite。
- 跨模块修改同步检查调用方、Save、Seed Determinism、Reservation、Network Authority 等相邻边界。
- 测试清单以当前代码树为准，不依赖单一文档列表。

## 10. Agent 输出要求

- 明确区分：当前已实现 / 本次要实现 / 后续计划。
- 不夸大尚未覆盖的 AI、Combat、DI、LAN E2E 等能力。
- 修改完成后说明：
  1. 改了什么；
  2. 为什么这样改；
  3. 影响哪些模块；
  4. 运行了哪些验证；
  5. 仍有哪些限制。
## 11. Skills 工作流

- 当任务与 `skills/` 中已有工作流匹配时，执行前先读取对应 Skill。
- Skill 负责规定该类任务的标准调查、修改和验证步骤；当前需求只补充本次任务的差异。
- 如果 Skill 与当前代码或 Spec 冲突，不允许机械执行旧 Skill，应停止并报告冲突。
- 一次性、小范围任务无需强行创建 Skill。
- 只有重复出现且流程已经稳定的任务，才沉淀为新的 Skill。
## 12. Specs 使用规则

- 修改核心系统前，如果 `specs/` 中已有对应规格，必须先阅读对应 Spec。
- Spec 定义系统当前契约、Source of Truth、核心不变量、生命周期和扩展边界。
- Skill 规定“任务怎么做”，Spec 规定“系统必须保持什么样”。
- 如果当前需求需要打破 Spec 中的 Core Invariant，不应直接把它当普通功能修改，应先作为架构变更处理。
- 如果代码与 Spec 冲突，先调查是代码漂移还是文档过期，再由开发者确认正式契约。
- 当 Source of Truth、Authority、Lifecycle、Persistence Contract 或核心数据流发生正式变化时，同步更新对应 Spec。
