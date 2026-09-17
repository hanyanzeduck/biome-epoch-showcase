# Save System Specification

**Status:** Active  
**Domain:** Persistence  
**Related ADR:** `docs/adr/003-adapter-based-save.md`  
**Related Skill:** `skills/change-save-schema.md`

---

## 1. Scope

负责：

- Save Schema；
- Persistent ID；
- Save Adapter / Codec；
- Persistent State；
- Runtime State Reconstruction；
- Save / Load；
- `.tmp` / `.bak`；
- Schema Version；
- World Generation Version Compatibility。

---

## 2. Goals

- 保存长期游戏事实。
- 将 Runtime Scene 与正式存档格式解耦。
- 支持稳定身份与引用恢复。
- 防止写盘中断造成主存档直接损坏。
- 对不兼容版本进行明确处理。

---

## 3. State Classification

所有需要保存的数据必须先分类。

### Static Definition

例如：

- Item Definition；
- Building Definition；
- Species Definition；
- Skill Definition。

保存稳定 ID / Reference，而不是复制整个 Runtime Object。

### Persistent State

例如：

- Creature Instance 长期属性；
- 建筑长期状态；
- Player 长期状态；
- 持久库存；
- Persistent ID。

### Runtime-only State

例如：

- Scene Node Reference；
- AI Reservation；
- 临时导航任务；
- Runtime Assignment；
- 当前行为执行上下文。

Runtime-only State 在 Load 后重建。

---

## 4. Source of Truth

存档中的 Persistent State 是长期事实。

运行中的 Node / SceneTree 只是当前 Runtime Representation。

因此：

> SceneTree != Save Schema

---

## 5. Core Invariants

### SAVE-INV-001

正式存档不直接持久化实时 SceneTree。

### SAVE-INV-002

Persistent Object 使用稳定身份。

### SAVE-INV-003

Runtime State 不成为长期持久真源。

### SAVE-INV-004

写盘过程保留：

```text
main
.tmp
.bak
```

以及当前原子替换 / 备份回退策略。

### SAVE-INV-005

不兼容 Schema / WorldGen Version 不应静默当正常数据加载。

---

## 6. Adapter Boundary

每个领域通过对应 Adapter / Codec：

```text
Runtime Domain Object
-> Save Adapter
-> Serializable Persistent Data
```

Load：

```text
Serialized Data
-> Adapter / Codec
-> Persistent Domain State
-> Runtime Reconstruction
```

业务系统不应绕过 Adapter 直接把 Node 存盘。

---

## 7. Load Lifecycle

逻辑上：

```text
读取 Save Envelope
-> Version Check
-> 恢复 World / Definition Context
-> 恢复 Persistent Entities
-> 恢复 Persistent IDs / References
-> Rebuild Runtime State
```

具体执行顺序以当前代码为准。

---

## 8. Write Safety

保存流程应尽量保证：

- 新数据先写到临时文件；
- 写入完成后再替换正式文件；
- 必要时保留上一版本 Backup；
- 主文件失败时允许使用 `.bak` 回退。

不能为了代码简单直接删除这些安全语义。

---

## 9. Compatibility

### Save Schema Version

当持久化结构发生不兼容变化时，需要：

- Migration；
- 或明确 Reject。

### World Generation Version

如果旧世界数据无法与新生成逻辑安全共存：

- 明确拒绝；
- 或进行正式迁移。

禁止“看起来能读就继续读”。

---

## 10. Extension Rules

新增 Persistent Field：

1. 分类；
2. 找到对应 Adapter；
3. 定义缺省行为；
4. 判断是否影响 Schema；
5. 判断旧 Save 行为；
6. 补测试。

新增 Runtime Field：

- 默认不进 Save；
- Load 后通过系统重建。

---

## 11. Forbidden Patterns

- 直接保存 NodePath / Node Reference 作为长期核心事实；
- 把 Reservation 存档；
- 把当前行为状态整个序列化；
- 靠默认值掩盖关键 Schema 不兼容；
- 修改 Persistent ID 规则但不做迁移。

---

## 12. Validation

- Save -> Load；
- Save -> Quit -> Load；
- `.bak` Fallback；
- Schema Reject / Migration；
- WorldGen Version；
- Persistent Reference Restore；
- Runtime State Rebuild。

---

## 13. Known Gaps

当前 Spec 不声称：

- 已支持任意历史版本 Save；
- 所有错误都具备用户友好恢复 UI；
- 所有 Domain Adapter 都已完成长期版本迁移矩阵。
