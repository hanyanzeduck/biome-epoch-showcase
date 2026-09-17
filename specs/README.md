# Biome Epoch Specs

本目录保存 Biome Epoch 核心系统的 **Current-State Specification（当前实现规格）**。

Spec 的作用不是描述“代码在哪”，也不是记录“为什么当初这么设计”。

Spec 主要回答：

> 这个系统现在必须满足什么契约？
> 谁是 Source of Truth？
> 数据如何流动？
> 哪些不变量不能被破坏？
> 出错时应该怎样处理？
> 新功能应该沿着什么边界扩展？

---

## 1. Spec 与其他文档的区别

### `AGENTS.md`
回答：

> 所有任务都必须遵守哪些项目级规则？

属于全局约束。

---

### `docs/adr/`
回答：

> 为什么项目选择这种架构？

ADR 记录架构决策及其后果。

---

### `skills/`
回答：

> 当我要执行某一类常见修改时，具体步骤是什么？

Skill 是任务工作流。

---

### `specs/`
回答：

> 某个系统“现在应该是什么样”。

Spec 是系统契约。

---

## 2. 一个完整 Spec 应包含什么

每个 Spec 尽量包括：

1. **Scope**
   - 这个 Spec 管什么；
   - 不管什么。

2. **Goals**
   - 当前系统要解决什么问题。

3. **Source of Truth**
   - 哪些数据是权威状态；
   - 哪些只是缓存、表现、Replica、Runtime State。

4. **Core Invariants**
   - 任何修改都不能破坏的规则。

5. **Data Model**
   - 主要对象、状态分类和身份关系。

6. **Data Flow / Lifecycle**
   - 数据从哪里来，经过什么阶段，到哪里去。

7. **Failure Handling**
   - 失败、非法状态、版本不兼容、目标失效时怎么处理。

8. **Extension Rules**
   - 新功能应该沿着哪些现有接口扩展。

9. **Non-Goals / Non-Claims**
   - 当前系统明确没有承诺什么。

10. **Validation**
    - 如何证明修改没有破坏系统契约。

11. **Known Gaps**
    - 当前仍存在但没有解决的问题。

---

## 3. 什么时候必须更新 Spec

出现以下情况时，应检查并更新对应 Spec：

- Source of Truth 改变；
- 数据生命周期改变；
- 新增或删除核心状态；
- Save / Network / WorldGen 兼容规则改变；
- Authority 改变；
- 新增重要状态机或阶段；
- 原有不变量被正式替换；
- 原本不支持的能力成为正式支持能力。

---

## 4. 什么情况下不用更新 Spec

以下改动通常不需要更新：

- 纯视觉调整；
- 不改变契约的小 Bug 修复；
- 内部重命名；
- 等价重构；
- 性能优化但系统行为、状态和边界不变。

---

## 5. Spec 冲突处理

如果发现：

- Spec 与当前代码冲突；
- 两份 Spec 互相冲突；
- ADR 与当前实现不一致；

Agent 不应自行选择一个版本强行执行。

正确流程：

1. 找到当前真实实现；
2. 找相关历史文档 / ADR；
3. 判断是代码漂移还是文档过期；
4. 报告冲突；
5. 由开发者确认哪一个才是新的正式契约；
6. 再同步修改代码和文档。

---

## 6. 当前核心 Specs

### 世界与运行时
- `world_generation.md`

### Creature
- `creature_instance_lifecycle.md`
- `creature_work_reservation.md`

### 建筑
- `building_capabilities_and_persistence.md`

### 战斗
- `combat_damage_pipeline.md`

### 存档
- `save_system.md`

### 多人联机
- `lan_authority.md`

### UI / Input
- `ui_input_modal_routing.md`

后续只有当某个系统已经形成稳定契约时，才继续增加新的 Spec。
