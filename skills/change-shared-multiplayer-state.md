# Skill：修改 LAN Shared State

## 什么时候使用

涉及：

- Shared World State；
- Host / Client Authority；
- Proposal；
- Revision；
- Bootstrap；
- ACK；
- Fingerprint；
- Owner / Personal State；

时使用。

## 修改前必须读取

- `AGENTS.md`
- `specs/lan_authority.md`
- `docs/adr/004-host-authoritative-lan.md`
- `LanMultiplayerService`
- 对应 Authority Adapter

## 修改前检查

1. 判断状态属于：
   - Shared；
   - Owner-scoped；
   - Personal。
2. 找到当前 Proposal；
3. 找到 Host Validation；
4. 找到 Canonical Commit；
5. 检查 Revision；
6. 检查 Bootstrap / ACK / Fingerprint；
7. 检查 Save 是否由 Host 写入。

## 执行步骤

1. Client 只提交 Proposal；
2. Host Validation；
3. Host Commit Canonical State；
4. 更新 / 校验 Revision；
5. Replication；
6. 必要时同步 Bootstrap / Fingerprint。

## 必须保持的约束

- Client 不直接成为 Shared Truth；
- Shared State Canonical Commit 在 Host；
- Revision 语义保持一致。

## 禁止事项

- 不为了“先跑起来”让 Client 直接写共享世界；
- 不把 Owner State 和 Shared State 混在一起；
- 没有 E2E 测试时不宣称完整网络稳定性。

## 验证

- Valid Proposal；
- Invalid Proposal；
- Stale Revision；
- Client Bootstrap；
- ACK；
- Fingerprint；
- Authority Regression。

## 何时停止并询问开发者

如果需要改变 Authority 模型、增加 Dedicated Server、完整 Reconnect 或新的 Conflict Resolution，先做架构讨论。
