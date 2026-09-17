# Skill：修改 UI / Input / Modal

## 什么时候使用

涉及：

- Gameplay Input；
- Modal；
- UI Router；
- 快捷键；
- UI 打开 / 关闭；
- 输入穿透；
- 同一按键同时触发 UI 和 Gameplay；

时使用。

## 修改前必须读取

- `AGENTS.md`
- `PlayerInputController`
- `GameplayUIRouter`
- 当前 Modal UI

## 修改前检查

1. 输入是 Gameplay 还是 UI；
2. 当前事件在哪一层消费；
3. Modal 是否锁输入；
4. Close 后是否存在按键保持导致的穿透；
5. 是否存在第二个直接监听同一输入的脚本。

## 执行步骤

1. Gameplay Input 进入统一入口；
2. UI 通过 Router；
3. Modal 打开时锁 Gameplay；
4. Modal 关闭时处理必要的离散输入抑制；
5. 不让业务系统直接查找具体 UI Node。

## 验证

- 打开 UI；
- 关闭 UI；
- 长按按键；
- 快速重复打开 / 关闭；
- Modal 叠加；
- Gameplay 不误触发。
