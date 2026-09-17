# ADR-004：LAN 使用 Host Authority

**状态：Active**

## 决策

LAN Shared World 使用 Host 作为 Canonical Authority。

Client 提交 Proposal，由 Host Validation 后 Commit。

## 原因

将共享状态的最终决定集中在单一权威端，减少 Client 之间直接竞争造成的状态分叉。

## 影响

- Client 不直接提交 Canonical Shared State；
- Shared State 修改经过 Proposal / Validation / Commit；
- Authority Revision 用于处理旧状态；
- Bootstrap、ACK、Fingerprint 与 Owner / Personal State 需要保持一致。
