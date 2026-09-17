# Biome Epoch Skills

本目录保存项目中可重复执行的 AI / Codex 工作流。

`Skill` 的作用不是解释系统设计，而是告诉 Agent：

> 当遇到某一类常见任务时，应当先读取哪些内容、按什么步骤执行、必须保持哪些约束、如何验证结果，以及在什么情况下应该停止并向开发者确认。

---

## 1. Skills 在整套文档中的位置

项目文档分工如下：

### `AGENTS.md`
回答：

> 所有任务都必须遵守什么？

它是全局规则。

例如：

- 修改前先读当前实现；
- 不新建平行系统；
- 2D Gameplay 是玩法真源；
- Client 不能直接成为 Shared World Truth。

---

### `specs/`
回答：

> 某一个系统当前必须满足什么契约？

例如：

- Save System 如何区分 Persistent / Runtime；
- WorldGen 如何保持 Seed Determinism；
- LAN Authority 的状态流是什么。

Spec 描述的是“系统应该是什么”。

---

### `docs/adr/`
回答：

> 为什么项目选择了这种架构？

例如：

- 为什么 Gameplay Truth 放在 2D；
- 为什么 Save 不直接序列化 SceneTree；
- 为什么 LAN 使用 Host Authority。

ADR 记录的是架构决策。

---

### `skills/`
回答：

> 我要做某一类修改，实际应该怎么操作？

例如：

- 我要新增一个建筑能力；
- 我要修改世界生成；
- 我要增加一个存档字段；
- 我要修改 Creature Work 行为；
- 我要修一个跨模块 Bug。

Skill 描述的是“任务怎么做”。

---

## 2. 什么任务值得做成 Skill

满足以下条件中的大部分时，才应该新增 Skill：

1. 这类任务会重复出现；
2. 已经有相对稳定的修改步骤；
3. 涉及多个文件或系统；
4. 很容易因为漏步骤造成回归；
5. 有明确的验证办法；
6. Agent 容易因为不了解上下文而重复造系统。

典型例子：

- 新增建筑；
- 修改存档 Schema；
- 新增 Skill / Weapon；
- 修改 WorldGen；
- 修改 Shared Multiplayer State；
- 修复跨模块坐标问题。

---

## 3. 什么不应该做成 Skill

下面这些通常不需要 Skill：

### 一次性问题

例如：

> 把某个按钮往下移动 6px。

直接做即可。

### 单纯知识说明

例如：

> Host Authority 是什么？

这是文档或 Spec，不是 Skill。

### 架构决策

例如：

> 为什么世界采用 2D Truth + 3D Presentation？

应该写 ADR。

### 还没有稳定流程的事情

如果一类任务只做过一次，而且连我们自己都还不知道标准步骤，就不要急着写成 Skill。

先完成几次任务，再总结稳定流程。

---

## 4. Skill 的标准结构

每个 Skill 尽量包含以下部分：

```text
# Skill 名称

## 什么时候使用
说明触发条件。

## 修改前必须读取
告诉 Agent 先看哪些文件 / Spec / ADR。

## 修改前检查
列出必须调查的当前实现。

## 执行步骤
按顺序给出操作流程。

## 必须保持的约束
明确不能破坏的架构规则。

## 禁止事项
列出这类任务最常见的错误做法。

## 验证
明确代码修改后如何测试。

## 完成时输出
要求 Agent 汇报：
- 改了什么
- 为什么这样改
- 运行了什么测试
- 还有什么限制

## 何时停止并询问开发者
如果遇到架构冲突、数据迁移、破坏兼容等情况，不要自行猜测。
```

---

## 5. Agent 使用 Skill 的方式

以后给 Codex 的任务可以逐渐简化。

过去可能需要写：

> 修改这个系统，但是不要重写旧系统，要检查存档，要跑测试，要注意……

以后可以写：

> 按 `skills/add-building.md` 新增建筑 XXX。
> 需求如下：……

或者：

> 按 `skills/fix-cross-module-bug.md` 调查这个坐标偏移问题。
> 先只定位，不修改。

也就是说：

**长期稳定规则写进 Skill，当前需求只描述差异。**

这样可以减少每次 Prompt 重复写大量工程约束。

---

## 6. Skill 的维护规则

### 当架构没变，只是步骤优化
直接更新 Skill。

### 当系统契约变了
先更新 Spec，再同步 Skill。

### 当架构决策变了
新增或修改 ADR，再同步 Spec 和 Skill。

### 当 Skill 与当前代码冲突
以当前真实代码和明确架构文档为准，先停止执行并报告冲突，不允许为了满足旧 Skill 强行改回旧架构。

---

## 7. 当前 Skills

### 核心系统修改
- `modify-world-generation.md`
- `change-save-schema.md`
- `change-creature-work-behavior.md`
- `change-shared-multiplayer-state.md`

### 内容与能力扩展
- `add-building.md`
- `add-creature-content.md`
- `add-combat-content.md`

### 跨模块工程任务
- `fix-cross-module-bug.md`
- `change-ui-input-modal.md`
- `architecture-migration.md`
- `select-regression-tests.md`

### 模板
- `_template.md`

以后只有在真实开发中出现新的重复工作流时，才继续新增 Skill。
