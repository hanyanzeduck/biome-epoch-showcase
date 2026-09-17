# Skill：新增 Creature / 菲菈内容

## 什么时候使用

新增或修改：

- Species Definition；
- Creature Instance 默认数据；
- 属性；
- 工作适应；
- 捕获相关静态内容；
- 生态生成；
- 图鉴 / UI 数据；

时使用。

## 修改前必须读取

- `AGENTS.md`
- Creature Species / Instance / Runtime 相关数据模型
- Catalog / Resource 定义
- Save 相关 Creature Adapter
- World / Ecology Spawn 路径

## 修改前检查

1. 内容属于 Species Definition 还是 Instance State；
2. 是否新增稳定 ID；
3. 是否影响 Save；
4. 是否影响 World Spawn / Ecology；
5. 是否影响 UI / 图鉴；
6. 是否错误地把 Runtime State 写进 Definition。

## 执行步骤

1. 添加静态 Definition；
2. 更新 Catalog；
3. 配置默认数据；
4. 接入 Spawn / Ecology；
5. 接入 UI；
6. 检查 Save；
7. 不为单个 Species 新增特殊硬编码，除非需求本身就是特殊机制。

## 必须保持的约束

- Species / Instance / Runtime 分层不混淆；
- Static Data 不保存 Runtime 引用；
- 尽量数据驱动。

## 验证

- Catalog 可加载；
- Spawn；
- Instance 创建；
- Save / Load；
- UI 展示；
- 对应内容测试。
