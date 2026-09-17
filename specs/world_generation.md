# World Generation Specification

**Status:** Active  
**Domain:** World / Procedural Generation  
**Related ADR:** `docs/adr/002-derived-worldgen-stage-seeds.md`  
**Related Skill:** `skills/modify-world-generation.md`

---

## 1. Scope

本 Spec 管理：

- World Seed；
- Graph；
- Task Layout；
- Raster；
- Room Layout；
- Topology；
- Validation；
- Spawn；
- 与 Seed 直接关联的生成阶段；
- 世界生成结果进入 Runtime 的边界。

不负责：

- 纯表现层动画；
- 与世界生成无关的 UI；
- 不参与生成结果的独立视觉特效。

---

## 2. Goals

- 根据 Seed 生成完整、可运行的世界。
- 在兼容的 World Generation Version 下保持确定性复现。
- 控制不同生成阶段之间的依赖。
- 保持逻辑地形与视觉表现解耦。
- 防止半完成或仅用于 Debug 的结果进入正式 Runtime。

---

## 3. Source of Truth

### Authoritative

- World Seed；
- Pipeline 当前阶段产生的逻辑结果；
- Task Ownership；
- 最终 `WorldGenResult`；
- Validator 对“是否可进入 Runtime”的正式判断。

### Derived / Presentation

- Debug Overlay；
- 视觉边缘噪声；
- 2.5D / 3D 表现；
- 仅用于评分或诊断的辅助指标。

这些数据不得反向改写逻辑生成结果。

---

## 4. Core Invariants

### GEN-INV-001：确定性

在 World Generation Version 兼容的情况下：

> 相同 Seed + 相同输入配置 -> 可复现结果。

### GEN-INV-002：阶段独立随机流

需要随机性的 Stage 从 World Seed 派生自己的 RNG。

一个 Stage 内新增随机调用，不应拖动后续无关 Stage 的随机序列。

### GEN-INV-003：Task Ownership

Task 土地所有权建立后：

- Room Layout 不随意改写；
- Topology Repair 不随意改写；
- Visual 不允许改写。

### GEN-INV-004：Spawn Truth

最终 Spawn 信息来自 `WorldGenResult`。

### GEN-INV-005：Runtime Gate

只有满足正式 Validation Contract 的结果才能进入 Gameplay Runtime。

Diagnostic Metric 不自动等于 Runtime Validity。

---

## 5. Data / Stage Flow

当前高层流程可概括为：

```text
World Seed
-> Graph
-> Task Layout / Workspace
-> Raster
-> Room Layout
-> Room Raster / Topology
-> Validation
-> Boundary / Roads / Spawn 等后续阶段
-> WorldGenResult
-> Runtime
```

具体阶段顺序以当前 `WorldGenPipeline` 为准。

本 Spec 固定的是不变量，不代表每个 Stage 永久不能重排。

---

## 6. Seed Rules

所有需要随机性的 WorldGen 子系统：

- 必须使用 Seed 派生随机；
- 禁止直接使用无法复现的无 Seed Random；
- 如果新增新的 Stage，应为其建立稳定的 Stage Seed 派生规则。

如果修改 Seed 派生方式会导致旧 Seed 世界整体变化：

> 视为 World Generation Compatibility 变更。

---

## 7. Ownership Rules

Raster 后形成的土地归属属于逻辑真源。

后续系统可以：

- 读取；
- 验证；
- 在合法范围内生成 Room / Road / Resource；

但不应为了局部修复：

- 偷偷重写 Task Ownership；
- 让视觉边缘决定逻辑 Tile 类型。

---

## 8. Validation / Failure Handling

WorldGen 失败时：

- 返回失败结果或 Validation Result；
- 输出足够 Debug 信息；
- 不把“尽量生成出来的半成品世界”当正式成功结果。

Diagnostic Topology / Connectivity 可以用于：

- Debug；
- 评分；
- 辅助修复。

但 Runtime Entry 必须使用正式 Validity Contract。

---

## 9. Spawn Contract

- Spawn 属于生成结果的一部分；
- Runtime 不应自己重新猜出生位置；
- Main Scene 不应成为 Spawn 的第二真源；
- Spawn 必须通过合法性检查。

---

## 10. Presentation Boundary

视觉系统可以对逻辑结果做：

- Edge Smoothing；
- Noise；
- 2.5D Offset；
- Sprite / Mesh 映射。

但不得改变：

- Logical Tile；
- Task Ownership；
- Room Ownership；
- Gameplay Position Truth。

---

## 11. Extension Rules

新增：

- Biome；
- Task；
- Room；
- Road；
- Resource；
- Ecology；

时：

1. 明确它属于哪个 Stage；
2. 明确其输入输出；
3. 不跨 Stage 偷写数据；
4. 使用确定性 Seed；
5. 更新 Validator；
6. 更新 Debug；
7. 更新 Regression Test。

---

## 12. Validation

最低验证：

- 同 Seed 重复生成；
- 不同 Seed 差异；
- Spawn；
- Runtime Valid；
- Task Ownership；
- WorldGen Headless Tests。

涉及大改时还应：

- 比较多个固定 Seed；
- 检查 Runtime Map；
- 检查 Save / WorldGen Version。

---

## 13. Known Gaps

当前文档不把以下内容定义成已经彻底稳定：

- 所有 Stage 永久固定顺序；
- 所有资源 / 道路 / 生态阶段已经完全统一；
- 所有拓扑指标都是硬失败条件。
