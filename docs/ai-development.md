# Biome Epoch 的 AI 辅助开发流程

## 开发模式

Biome Epoch 长期采用 AI 辅助开发。

随着项目从功能原型进入规模化迭代阶段，我逐步把开发方式固定为：

**需求定义 → 实现约束 → AI 辅助实现 → 代码/架构检查 → 实际运行 → Bug 反馈 → 回归验证**

其中：

- 我负责玩法目标、功能边界、架构约束和验收标准；
- ChatGPT 主要用于需求拆解、方案讨论、将复杂需求整理成更完整的 Codex 指令；
- Codex 负责在读取当前项目后辅助实现、修改和代码审查；
- 最终是否接受实现，以实际运行结果、测试和架构一致性为准。

## 我持续要求 AI 遵守的原则

在项目进入架构收口和复杂系统开发阶段后，AI 任务持续遵循以下约束：

- 修改前先读取当前项目实现；
- 尽量做最小改动；
- 优先复用已有系统；
- 不创建平行架构；
- 明确 Source of Truth；
- 跨模块修改前检查完整影响面；
- 保留已经成熟的功能；
- Bug 优先复现和定位，再修改；
- 修改后通过实际运行和回归测试验收。

## 这些规则如何体现在项目中

项目目前已经形成多处稳定的工程边界，例如：

- 2D Gameplay Logic 作为玩法真源，2.5D / 3D 为表现层；
- WorldGen 使用 Seed 派生随机流保证确定性；
- Creature Work / Haul 使用 Reservation、Coordinator、Retry、Stop Reason 管理并发目标；
- Save 区分 Static Definition、Persistent State 和 Runtime State；
- LAN Shared State 使用 Host Authority、Revision、Proposal / Commit；
- Building 能力逐步收口到 Data / Config / Component；
- UI 输入和页面调用通过统一 Router / Modal / Input Boundary；
- Debug 与自动回归测试集中化。

## 当前 AI 工作方式

现在每个较大的 AI 开发任务，理想流程是：

1. 明确需求和验收标准；
2. 读取 `AGENTS.md`；
3. 阅读相关系统 Spec；
4. 检查当前真实实现；
5. 确定修改边界和受影响模块；
6. Codex 实现；
7. Review Diff；
8. 运行测试和实际游戏验证；
9. 如果系统契约发生变化，同步更新文档。

AI 主要提升：

- 代码实现效率；
- 大规模代码检索；
- Code Review；
- Bug 定位；
- 测试设计；
- 重复性内容生成。

玩法设计、核心架构、技术取舍和最终验收由开发者负责。
