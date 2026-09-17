# Skill：新增建筑或建筑能力

## 什么时候使用

新增：

- 建筑种类；
- 建筑 Capability；
- 生产；
- 库存；
- 物流；
- 电力；
- Creature Facility；
- 建筑交互；

时使用。

## 修改前必须读取

- `AGENTS.md`
- `docs/adr/005-building-capability-consolidation.md`
- 当前 `BuildingData`
- 相关 Capability Config / Component
- Building Catalog
- Building Save Adapter
- 放置 / Construction 相关代码

## 修改前检查

1. 当前是否已有同类 Capability；
2. 能否通过配置完成，而不新增业务分支；
3. 是否需要新 Component；
4. 是否影响：
   - Placement；
   - Interaction；
   - Inventory；
   - Production；
   - Logistics；
   - Power；
   - Save；
   - Multiplayer。

## 执行步骤

1. 优先新增 / 修改 Data；
2. 复用现有 Capability；
3. 只有现有能力无法表达需求时才新增 Component；
4. 接入交互 / 生产 / 物流等必要边界；
5. 确保持久身份；
6. 补对应测试。

## 必须保持的约束

- 不恢复已经删除的 Legacy 配置真源；
- 不为单个建筑复制整套已有逻辑；
- 持久建筑必须保持 Persistent ID。

## 验证

- 放置；
- Construction；
- Interaction；
- Save / Load；
- Capability 功能；
- 如果参与网络，同步 Authority；
- 对应 Regression Suite。

## 何时停止并询问开发者

如果需求需要新增一套与现有 Building Component 平行的系统，先说明为什么现有能力不能扩展。
