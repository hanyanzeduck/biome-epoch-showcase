# Skill：架构迁移 / 收口

## 什么时候使用

当任务不是新增功能，而是：

- 删除重复系统；
- 合并两个 Source of Truth；
- Legacy -> New Model；
- Component 收口；
- 数据模型迁移；
- 大规模调用方迁移；

时使用。

## 修改前必须读取

- `AGENTS.md`
- 相关 Spec
- 相关 ADR
- 旧系统和新系统全部调用方

## 修改前检查

1. 找到 Old Source of Truth；
2. 找到 New Source of Truth；
3. 列出所有 Reader / Writer；
4. 找到 Save / Network / UI / Debug / Test 依赖；
5. 明确迁移完成判定。

## 执行步骤

1. 先让新路径完整可用；
2. 迁移 Reader；
3. 迁移 Writer；
4. 迁移 Data；
5. 更新 Save / Network / Debug / Test；
6. 确认旧路径无调用；
7. 最后删除 Legacy。

## 禁止事项

- 不长期保留两个可写 Source of Truth；
- 不在迁移中同时增加第三套兼容层；
- 不先删旧系统再发现调用方遗漏。

## 验证

- 搜索旧 API / 字段引用；
- Regression；
- Save；
- Network；
- Debug；
- Runtime Smoke Test。

## 何时停止并询问开发者

如果迁移会破坏正式旧存档、公开数据格式或网络协议，先报告迁移成本。
