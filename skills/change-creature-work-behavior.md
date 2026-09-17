# Skill：修改 Creature Work / Haul 行为

## 什么时候使用

涉及：

- Work 行为；
- Haul 行为；
- Reservation；
- Action Coordinator；
- Retry；
- Stop Reason；
- 多 AI 争抢同一目标；

时使用。

## 修改前必须读取

- `AGENTS.md`
- `specs/creature_work_reservation.md`
- 当前 Behavior
- Reservation Lease
- Action Coordinator
- Retry Cooldown
- Stop Reason

## 修改前检查

1. 找到 Target Acquire；
2. 找到 Reservation Acquire；
3. 枚举全部 Exit Path；
4. 检查 Target Invalid；
5. 检查 Behavior Switch；
6. 检查失败后的 Retry。

## 执行步骤

1. 复用现有 Coordinator；
2. Reservation 成功后才进入占用状态；
3. 新 Reservation 前清理旧 Reservation；
4. 所有退出路径处理 Release；
5. 使用统一 Stop Reason；
6. 临时失败进入 Retry，而不是无限重复抢占。

## 必须保持的约束

- 同一 Exclusive Target 不能被多个 Creature 同时拥有；
- Lease 不应泄漏；
- Work / Haul 不重新各造一套 Ownership。

## 验证

- 两个 Creature 抢同一 Target；
- Target 中途销毁；
- Creature 中途死亡；
- Behavior 被战斗打断；
- 取消任务；
- Retry 后再次成功；
- 完成后 Reservation 清零。

## 何时停止并询问开发者

如果任务要求建立新的全局 AI Coordinator 或改变 Wild / Party / Base 的总体 AI 架构，先作为架构变更处理。
