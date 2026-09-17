# ADR-005：建筑能力使用 Data / Config / Component

**状态：Active**

## 决策

建筑功能优先通过 `BuildingData`、Capability Config 和 Component 组合。

已经统一的能力不再保留第二套 Legacy 配置来源。

## 原因

减少建筑数量增加后产生的重复逻辑和配置真源分裂。

## 影响

- 新建筑优先组合现有能力；
- Power、Creature Facility 等统一能力继续使用既有配置体系；
- Persistent ID 与 Component Save Boundary 保持稳定；
- 不为已有 Capability 再造平行系统。
