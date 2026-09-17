# Skill：新增技能、武器或战斗内容

## 什么时候使用

新增 / 修改：

- Skill；
- Weapon；
- Projectile；
- Melee；
- Damage；
- Damage Budget；
- Weapon Runtime State；

时使用。

## 修改前必须读取

- `AGENTS.md`
- 当前 CombatMath / DamageInfo
- Skill Damage Ledger
- Weapon Definition / Instance
- 对应 Projectile / Melee 路径

## 修改前检查

1. 需求属于静态 Definition 还是 Runtime Instance；
2. 当前伤害是否可以走现有公共路径；
3. 是否需要新的 Damage Type / Attribute；
4. 是否影响 Save；
5. 是否影响 Network；
6. 是否影响 UI / Ammo / Reload。

## 执行步骤

1. 优先通过数据配置新增内容；
2. 使用现有 Combat / Skill / Weapon 公共接口；
3. Runtime 状态放在 Instance；
4. 静态参数放在 Definition；
5. 如果确实需要特殊伤害逻辑，明确隔离并说明为什么不能复用当前公共路径。

## 禁止事项

- 不为每个武器复制一份伤害公式；
- 不把弹匣 / 弹药 / Reload Runtime 状态写进静态 Definition；
- 不为了一个特例破坏全局 CombatMath。

## 验证

- 单发；
- 连续攻击；
- 多段 / DOT（如适用）；
- Ammo / Reload；
- Save / Load；
- Network（如适用）；
- Combat Regression。

## 何时停止并询问开发者

如果需求会改变统一伤害数学、属性体系或整个 Weapon Runtime Model，先做架构讨论。
