# Skill：选择并执行回归测试

## 什么时候使用

任何核心代码修改完成后，都可以使用本 Skill 决定应该运行哪些测试。

## 目标

不是机械地“每次跑所有测试”，而是根据实际影响面选择：

- 必跑的直接测试；
- 相邻边界测试；
- 必要时完整回归。

## 步骤

### 1. 列出改动模块
例如：

- WorldGen；
- Save；
- Creature；
- Building；
- Combat；
- Network；
- UI。

### 2. 列出数据边界
检查改动是否涉及：

- Persistent Data；
- Seed；
- Reservation；
- Authority；
- UI Input；
- Persistent ID；
- Definition / Instance 分离。

### 3. 选择直接 Suite
运行改动系统对应测试。

### 4. 选择相邻 Suite
如果修改跨越系统边界，再运行相邻系统测试。

例如：

WorldGen + Save
-> WorldGen Suite + Save Suite

Creature Reservation + Building Work Target
-> Creature / Haul + Building 相关测试

Network Shared Building State
-> Network Authority + Building / Save

### 5. Full Regression
以下情况建议运行 `tests/run_all.gd`：

- 大型架构迁移；
- 公共基类 / 公共组件修改；
- Source of Truth 变化；
- 多个核心领域同时修改；
- 发布 / 里程碑前。

## 输出

Agent 完成任务时要明确列出：

- 实际运行的测试；
- 没有运行的测试；
- 为什么没有运行；
- 是否存在测试环境限制。
