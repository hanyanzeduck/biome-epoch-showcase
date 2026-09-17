# ADR-002：WorldGen 使用阶段独立 Seed

**状态：Active**

## 决策

每个需要随机性的 WorldGen Stage 从 World Seed 派生自己的随机流。

## 原因

避免某一阶段增加一次随机调用后，导致后续所有阶段的结果整体变化。

## 影响

- 同 Seed 可稳定复现；
- 单阶段修改尽量不影响无关阶段；
- 确定性视觉随机同样基于 Seed / 坐标；
- WorldGen 路径中禁止无 Seed Random。
