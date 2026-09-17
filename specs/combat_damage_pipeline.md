# Combat Damage Pipeline Specification

**Status:** Active  
**Domain:** Combat / Skill / Weapon  
**Related Skill:** `skills/add-combat-content.md`

---

## 1. Scope

负责描述当前已有的公共战斗计算边界：

- CombatMath；
- DamageInfo；
- Skill Damage Ledger / Damage Budget；
- Weapon Definition / Instance 分离原则；
- Skill / Weapon / Projectile / Melee 与公共伤害逻辑的关系。

---

## 2. Goals

- 避免每个技能或武器复制自己的基础伤害公式。
- 保持伤害参数、Runtime State 与攻击结果之间边界清晰。
- 支持单发、多段、持续伤害等不同表现形式在统一伤害预算思想下扩展。

---

## 3. Source of Truth

### Static Definition

- Skill / Weapon 静态参数；
- 基础威力；
- 类型；
- 资源定义。

### Runtime Instance

- Ammo；
- Magazine；
- Reload；
- 当前扩散；
- Weapon Runtime State。

### Damage Calculation

当前已存在公共 `CombatMath` / `DamageInfo` 路径。

---

## 4. Core Invariants

### COMBAT-INV-001

公共伤害数学不应在多个武器脚本中复制维护。

### COMBAT-INV-002

Static Definition 与 Runtime Instance State 分离。

### COMBAT-INV-003

Skill Damage Budget / Ledger 是技能伤害分配的重要边界之一。

### COMBAT-INV-004

特殊攻击可以有特殊实现，但如果只是同一公式的参数变化，应优先数据驱动。

---

## 5. Damage Flow

高层逻辑：

```text
Attack / Skill Definition
-> Runtime Context
-> DamageInfo / Damage Budget
-> CombatMath
-> Hurt / Apply Damage
-> Result / Effect
```

具体不同攻击类型的完整覆盖范围，以当前代码为准。

---

## 6. Skill Damage Budget

对：

- 单段；
- 多段；
- DOT；

允许通过不同出伤方式表达。

但整体威力应通过统一 Budget / Ledger 控制，而不是每个 Skill 独立失控增长。

---

## 7. Weapon Definition / Instance

Definition 保存：

- 武器静态参数；
- 弹药类型；
- 基础属性；
- 配件规则等。

Instance 保存：

- 当前弹匣；
- Runtime Ammo；
- Reload；
- 当前状态；
- 动态配件 / Instance 状态。

---

## 8. Extension Rules

新增 Skill / Weapon：

1. 优先新增数据；
2. 复用 CombatMath；
3. 复用 DamageInfo；
4. Runtime State 放 Instance；
5. 特殊机制独立，但必须解释为什么公共路径不能表达。

---

## 9. Forbidden Patterns

- 每个 Weapon 自己复制一套伤害公式；
- Runtime Ammo 写回静态 Weapon Definition；
- 单个 Skill 为了特殊效果绕开全部战斗公共逻辑；
- UI 自己计算最终 Damage Truth。

---

## 10. Validation

- 单发；
- 多段；
- DOT；
- Ammo / Reload；
- Weapon Instance；
- Skill Budget；
- Combat Regression。

---

## 11. Known Gaps

当前不宣称：

- 所有 Weapon / Projectile / Melee 已经 100% 统一到同一 Damage Pipeline；
- 所有历史内容已经全部迁移；
- CombatMath 已经覆盖未来所有特殊战斗机制。
