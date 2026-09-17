# ADR-003：Adapter-based Save

**状态：Active**

## 决策

正式存档保存 Stable ID、Definition Reference 与 Persistent State。

Runtime Scene Reference 和短生命周期状态在加载后重建。

## 原因

避免 SceneTree 结构直接绑定 Save Schema，使 Runtime 重构与存档格式解耦。

## 影响

- `SceneTree` 不作为正式 Save Model；
- Persistent ID 成为稳定身份；
- Adapter / Codec 管理领域数据；
- Schema Version 和 Migration 必须显式处理；
- Runtime State 不直接持久化。
