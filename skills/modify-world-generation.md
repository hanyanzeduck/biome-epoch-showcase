# Skill：修改世界生成

## 什么时候使用

涉及以下任一内容时使用：

- Graph / Task / Room；
- Raster；
- Topology；
- Validation；
- Spawn；
- Road；
- Resource / Ecology 生成；
- 与 World Seed 有关的视觉生成。

## 修改前必须读取

- `AGENTS.md`
- `specs/world_generation.md`
- `docs/adr/002-derived-worldgen-stage-seeds.md`
- 当前 `WorldGenPipeline`
- 当前 Result / Validator / Runtime Consumer

## 修改前检查

1. 明确需求属于哪个 WorldGen Stage；
2. 找到这一阶段输入和输出；
3. 找到下游消费者；
4. 检查是否影响：
   - Seed Determinism；
   - Task Ownership；
   - Spawn；
   - Runtime Validity；
   - Debug；
   - Save Compatibility。

## 执行步骤

1. 在当前 Stage 内优先完成修改；
2. 如果需要随机数，从 World Seed 派生该阶段自己的 RNG；
3. 不修改不属于当前 Stage 的权威数据；
4. 同步更新 Result / Validator / Debug Consumer；
5. 如改变生成契约，再更新 Spec。

## 必须保持的约束

- 同版本 + 同 Seed 保持确定性；
- 不加入无 Seed Random；
- Task Ownership 不被后续 Stage 偷偷改写；
- Spawn 继续来自 `WorldGenResult`；
- Visual 不修改 Gameplay Truth。

## 禁止事项

- 不通过增加随机重试“碰运气”掩盖生成错误；
- 不把 Debug 指标直接当成 Runtime Truth；
- 不为了视觉效果修改逻辑 Tile Ownership。

## 验证

至少：

1. 固定 Seed 前后重复生成；
2. WorldGen Headless Regression；
3. Spawn 合法性；
4. Validator；
5. Debug View；
6. 如果涉及 Save，检查 World Generation Version。

## 完成时输出

说明：

- 改动 Stage；
- Seed 行为是否变化；
- 是否影响旧 WorldGen Version；
- 执行的固定 Seed / 测试；
- 当前已知限制。

## 何时停止并询问开发者

如果修改要求：

- 改变 Task Ownership；
- 改变整个 Pipeline 顺序；
- 导致旧 Seed 世界全面变化；
- 需要修改 World Generation Version；

先停止并报告影响。
