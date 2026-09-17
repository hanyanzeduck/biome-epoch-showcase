# Creature Work / Reservation Specification

**Status:** Active  
**Domain:** Creature AI / Work  
**Related Skill:** `skills/change-creature-work-behavior.md`

---

## 1. Scope

负责：

- Work / Haul 类行为目标占用；
- Reservation；
- Reservation Lease；
- Action Coordinator；
- Retry Cooldown；
- Stop Reason；
- 多 Creature 对同一目标的竞争。

不负责定义全部 Wild / Party / Base AI。

---

## 2. Goals

- 同一独占 Target 同一时间只被一个 Creature 合法占用。
- 行为退出时 Reservation 可可靠释放。
- 行为竞争失败时进入可控 Retry。
- Work / Haul 不重复建立不同的目标所有权模型。

---

## 3. Source of Truth

对于 Exclusive Work Target：

> Reservation System 是目标占用权真源。

`current_target` 等 Runtime 引用本身不等价于 Ownership。

---

## 4. Core Invariants

### AI-INV-001

Reservation 成功后才允许行为进入“已占有目标”状态。

### AI-INV-002

Reservation 生命周期由 Lease 明确管理。

### AI-INV-003

目标失效、失败、取消、行为切换等退出路径必须释放不再有效的 Lease。

### AI-INV-004

多个 Creature 不能同时把同一个独占目标视为自己合法拥有。

### AI-INV-005

临时竞争失败通过 Retry 机制处理，不通过无限每帧抢占处理。

---

## 5. Runtime Lifecycle

典型流程：

```text
Find Candidate
-> Can Reserve?
-> Try Reserve
-> Acquire Lease
-> Start Action
-> Complete / Fail / Cancel / Interrupted
-> Release Lease
-> Stop Reason / Retry
```

---

## 6. Stop Reason

Stop Reason 用于描述“为什么当前行为停止”。

典型类型包括：

- Target Invalid；
- Reservation Failed；
- Navigation Failed；
- Combat Interrupt；
- Behavior Switch；
- Completed。

如果新增新的退出语义：

- 优先映射到已有枚举；
- 必要时统一扩展；
- 不在不同 Behavior 内随意造字符串状态。

---

## 7. Retry

Retry Cooldown 用于避免：

- 每帧重复争抢同一失败目标；
- 多 AI 高频竞争；
- 失败行为立刻无限重试。

---

## 8. Failure Handling

### Target 在持有期间销毁
释放 Lease，停止行为。

### Creature 自身失效 / 死亡
释放所有本行为持有的 Reservation。

### 行为被更高优先级行为打断
通过 Stop / Cleanup 路径释放。

### Reservation 失败
不进入 Ownership，进入 Retry 或寻找其他目标。

---

## 9. Extension Rules

新增 Work / Haul 行为：

1. 使用现有 Coordinator；
2. 使用 Lease；
3. 明确 Acquire；
4. 明确 Cleanup；
5. 明确 Stop Reason；
6. 明确 Retry；
7. 补竞争测试。

---

## 10. Forbidden Patterns

- 只靠 `target != null` 判断 Ownership；
- Behavior 自己维护第二张全局占用表；
- 失败后每帧立即抢同一 Target；
- 在多个 Exit Path 中漏掉 Release。

---

## 11. Validation

至少覆盖：

- 两个 Creature 同时抢一个 Target；
- Target 中途被删除；
- Behavior 被 Combat 打断；
- Creature 死亡；
- Cancel；
- Retry 后成功；
- 行为结束后 Reservation Count 恢复。

---

## 12. Non-Claims

当前不声明：

- Wild / Party / Base 已经完全统一为一个 Coordinator；
- 所有 AI 行为都已经 Reservation 化。
