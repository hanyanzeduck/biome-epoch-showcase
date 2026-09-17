# Building Capabilities & Persistence Specification

**Status:** Active  
**Domain:** Building  
**Related ADR:** `docs/adr/005-building-capability-consolidation.md`  
**Related Skill:** `skills/add-building.md`

---

## 1. Scope

负责：

- Building Definition；
- Capability Config；
- Building Component；
- Building Persistent ID；
- Building Save Boundary；
- 建筑能力组合原则。

涉及但不完全定义：

- Placement；
- Interaction；
- Inventory；
- Production；
- Logistics；
- Power；
- Creature Facility。

---

## 2. Goals

- 通过数据与组件组合扩展建筑。
- 减少每种建筑各写一套逻辑。
- 防止同一能力出现多个配置真源。
- 保持建筑持久身份稳定。

---

## 3. Source of Truth

### Static Capability Truth

`BuildingData` + 对应 Capability Config。

### Runtime Behavior

对应 Component。

### Persistent Identity

Persistent ID。

---

## 4. Core Invariants

### BUILD-INV-001

已经统一到 Capability Config 的能力，不重新建立第二套同义配置字段。

### BUILD-INV-002

新建筑优先组合已有能力。

### BUILD-INV-003

只有现有 Component 无法表达需求时，才增加新 Component。

### BUILD-INV-004

需要持久化的建筑必须保持稳定 Persistent ID。

### BUILD-INV-005

Runtime Node 不是建筑长期身份本身。

---

## 5. Capability Model

典型结构：

```text
BuildingData
-> Capability Config
-> Runtime Building Component
-> Runtime State
-> Save Adapter / Persistent State
```

---

## 6. Extension Rules

新增建筑：

1. 创建 / 配置 BuildingData；
2. 检查现有 Capability；
3. 复用 Config / Component；
4. 接入 Placement / Interaction；
5. 如果有持久状态，接入 Save；
6. 如果 Shared，接入 Network Authority；
7. 补 Regression。

新增 Capability：

1. 先确认不是已有能力的变体；
2. 定义 Config；
3. 定义 Component；
4. 明确 Persistent / Runtime State；
5. 明确 UI / Interaction；
6. 明确 Save / Network。

---

## 7. Persistence

建筑长期身份：

> Persistent ID

建筑组件如有长期状态：

> 通过现有 Save Boundary 保存。

不依赖 Scene Instance 本身作为长期身份。

---

## 8. Forbidden Patterns

- 为一个建筑复制整套 Power / Inventory / Production；
- 恢复已废弃的第二配置真源；
- 通过 NodePath 作为长期建筑身份；
- 单个建筑大量硬编码 ID 分支。

---

## 9. Validation

至少：

- Placement；
- Construction；
- Interaction；
- Capability Behavior；
- Save / Load；
- Persistent ID；
- Network（如 Shared）；
- Regression。

---

## 10. Known Gaps

本 Spec 不声称：

- 所有 Building 子系统已经拥有统一万能接口；
- Production / Logistics / Power 已经完全共享同一套抽象。
