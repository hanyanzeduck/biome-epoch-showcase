# UI / Input / Modal Routing Specification

**Status:** Active  
**Domain:** UI / Input  
**Related Skill:** `skills/change-ui-input-modal.md`

---

## 1. Scope

负责：

- Gameplay Input Boundary；
- `PlayerInputController`；
- Gameplay UI Router；
- Modal Input Priority；
- UI 打开 / 关闭；
- 输入穿透防护。

---

## 2. Goals

- 避免同一个按键同时被 UI 与 Gameplay 消费。
- Gameplay 不直接依赖具体 UI Node。
- Modal 打开时可以阻止 Gameplay 输入，但不强制暂停整个世界。
- UI 生命周期变化不破坏 Gameplay 调用边界。

---

## 3. Source of Truth

### Gameplay Input

统一 Gameplay Input Controller / Boundary。

### UI Navigation / Opening

Gameplay UI Router。

### Modal State

当前 Modal 管理逻辑。

---

## 4. Core Invariants

### UI-INV-001

Gameplay Input 不应由多个业务脚本各自直接监听同一动作。

### UI-INV-002

Modal 打开时拥有更高输入优先级。

### UI-INV-003

Gameplay 通过 Router / Interface 请求 UI，不直接查找具体页面 Node。

### UI-INV-004

Modal 关闭后要处理必要的按键残留，避免同一按键立即穿透到 Gameplay。

---

## 5. Input Flow

高层：

```text
Raw Input
-> UI / Modal Priority
-> Gameplay Input Controller
-> Gameplay Action
```

具体使用 `_unhandled_input` 等方式，以当前实现为准。

---

## 6. Modal Contract

Modal：

- 可以锁 Gameplay Input；
- 不一定暂停 World Simulation；
- 关闭时处理当前按键状态；
- 不应该让 Gameplay 在同一 Frame 收到同一个离散操作。

---

## 7. Router Contract

Gameplay 系统请求：

- 打开页面；
- 关闭页面；
- 切换 UI；

时通过稳定 Router / Interface。

业务代码不要：

- `get_node()` 直接寻找某个具体页面路径；
- 依赖某个页面的 SceneTree 位置。

---

## 8. Extension Rules

新增 UI：

1. 判断是 Modal / Non-Modal；
2. 判断是否锁 Gameplay Input；
3. 接入 Router；
4. 明确 Close 行为；
5. 测试 Hold / Repeat；
6. 不增加第二套输入入口。

---

## 9. Failure Handling

### UI 被销毁
Router 不应留下非法硬引用。

### Modal 关闭瞬间
避免按键穿透。

### 多 Modal
按当前优先级规则处理，不允许 Gameplay 越过顶层 Modal。

---

## 10. Validation

- Open；
- Close；
- Rapid Toggle；
- Hold Key；
- Mouse Input；
- Modal Stack；
- Gameplay Input Block；
- UI Destroy / Recreate。

---

## 11. Non-Claims

当前不宣称：

- 全项目存在统一 DI Container；
- 所有 UI 都已经迁移到同一种生命周期模型。
