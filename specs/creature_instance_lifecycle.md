# Creature Instance Lifecycle Specification

**Status:** Active  
**Domain:** Creature Data / Persistence / Runtime

---

## 1. Scope

负责：

- Species Definition；
- Persistent Creature Instance；
- Runtime Entity；
- Runtime Assignment；
- Save / Load 后的重建；
- Species / Instance / Runtime 分层。

---

## 2. Goals

- 静态物种定义与具体个体长期状态分离。
- 持久个体与当前世界中的 Runtime Node 分离。
- Runtime Entity 可以被销毁 / 重建，而不丢失个体身份。
- Save 不依赖当前 Scene Node 生命周期。

---

## 3. Three-Layer Model

### Species

描述“这种 Creature 是什么”。

例如：

- Name；
- Element；
- Species Base Stats；
- Work Capability；
- 静态技能池 / 内容定义。

### Instance

描述“这一只 Creature 是谁”。

例如：

- Persistent ID；
- Level；
- Individual Values；
- Learned Skills；
- Equipment；
- 长期成长状态。

### Runtime Entity

描述“这一只 Creature 当前在世界里怎么运行”。

例如：

- Node；
- Position；
- AI Behavior；
- Reservation；
- 当前任务；
- Runtime Assignment。

---

## 4. Source of Truth

### Species Truth
Species Definition Resource / Catalog。

### Persistent Individual Truth
Creature Instance Data。

### Current Runtime Representation
Runtime Entity / Node。

Runtime Entity 被销毁不等于 Instance 被删除。

---

## 5. Core Invariants

### CREATURE-INV-001

Species 数据不保存个体长期状态。

### CREATURE-INV-002

Instance 不依赖当前 Scene Node 才能存在。

### CREATURE-INV-003

Runtime-only Assignment / Reservation 不直接成为 Persistent State。

### CREATURE-INV-004

同一个 Persistent Creature Instance 应具有稳定身份。

---

## 6. Lifecycle

典型生命周期：

```text
Species Definition
-> Create Persistent Instance
-> Spawn Runtime Entity
-> Runtime Assignment / Behavior
-> Despawn Runtime Entity
-> Persistent Instance remains
-> Spawn again
```

Save / Load：

```text
Save Persistent Instance
-> Destroy Runtime
-> Load Persistent Instance
-> Rebuild Runtime
```

---

## 7. Context Transition

Creature 可以在不同上下文之间变化，例如：

- Wild；
- Party；
- Base；
- Transit / Storage（若当前实现涉及）。

上下文变化不应重新创建一个“新的长期个体身份”。

---

## 8. Runtime Cleanup

Despawn / Load / Context Switch 时：

- 清理 Runtime Assignment；
- 清理 Reservation；
- 清理 Node Reference；
- 保留 Persistent Instance。

---

## 9. Extension Rules

新增 Creature 长期属性：

- 放 Instance。

新增 Species 静态属性：

- 放 Species Definition。

新增只在当前运行期间有效的数据：

- 放 Runtime State。

---

## 10. Forbidden Patterns

- 把 Node Reference 保存到长期存档；
- 把 Species Resource 当某只个体的唯一状态；
- Context Switch 时生成新的 Persistent ID；
- 把 AI 临时任务写入长期 Instance。

---

## 11. Validation

- Spawn；
- Despawn；
- Save / Load；
- Context Switch；
- Persistent ID；
- Runtime Reset；
- Instance 长期状态保持。

---

## 12. Known Gaps

当前不在本 Spec 中宣称：

- Wild / Party / Base 所有行为状态已完全统一；
- 所有 Context Transition 已具备完整自动回归。
