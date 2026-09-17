# Skill：修改存档结构

## 什么时候使用

涉及：

- 新增 / 删除持久化字段；
- Persistent ID；
- Save Adapter / Codec；
- Schema Version；
- World Generation Version；
- Save / Load 顺序；
- 旧存档兼容；

时使用。

## 修改前必须读取

- `AGENTS.md`
- `specs/save_system.md`
- `docs/adr/003-adapter-based-save.md`
- `SaveGameService`
- 对应领域 Save Adapter

## 修改前检查

1. 判断数据属于：
   - Static Definition；
   - Persistent State；
   - Runtime State。
2. 找到当前 Adapter / Codec；
3. 检查引用恢复；
4. 检查旧存档可能包含什么；
5. 检查是否需要 Schema Version 变化。

## 执行步骤

1. 只持久化真正需要长期保存的数据；
2. 使用稳定 ID / Definition Reference；
3. 在对应 Adapter 中写入 / 读取；
4. Runtime State 在加载后重建；
5. 必要时增加 Migration 或明确 Reject；
6. 保持 `.tmp` / `.bak` / Atomic Replace。

## 必须保持的约束

- 不直接序列化 SceneTree；
- 不把 Reservation / 临时任务写成长期事实；
- 不静默吞掉不兼容版本；
- Persistent ID 不随场景重建改变。

## 禁止事项

- 不因为方便直接保存 Node Reference；
- 不通过默认值偷偷掩盖关键字段缺失；
- 不删除旧 Schema 处理但不说明兼容影响。

## 验证

- Save -> Load；
- Save Regression；
- 主文件损坏后的 Backup Fallback；
- Schema 不兼容；
- 旧版本样本（如果存在）。

## 何时停止并询问开发者

如果需要：

- 破坏旧正式存档；
- 修改 Persistent ID 规则；
- 改变 World Generation Version 兼容策略；

先报告再执行。
