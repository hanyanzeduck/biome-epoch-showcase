# LAN Authority Specification

**Status:** Active  
**Domain:** Multiplayer / Network  
**Related ADR:** `docs/adr/004-host-authoritative-lan.md`  
**Related Skill:** `skills/change-shared-multiplayer-state.md`

---

## 1. Scope

负责：

- LAN Host Authority；
- Host / Client / Offline Role；
- Shared State；
- Owner / Personal State；
- Proposal；
- Validation；
- Canonical Commit；
- Authority Revision；
- Bootstrap；
- ACK；
- Fingerprint；
- Replica。

不负责：

- Internet Matchmaking；
- NAT Traversal；
- Dedicated Server；
- 产品级 Anti-Cheat。

---

## 2. Goals

- Shared World 只有一个 Canonical Authority。
- Client 无法通过本地直接写入成为 Shared Truth。
- 旧 Revision 不覆盖新状态。
- Client 可从 Host 获得可验证的 Replica。

---

## 3. Source of Truth

### Shared World State

Host 是 Canonical Source of Truth。

### Personal / Owner State

按当前 Ownership Contract 管理，不自动等同于 Shared World State。

### Client Replica

是 Replica，不是 Canonical Truth。

---

## 4. Core Invariants

### NET-INV-001

Client 对 Shared State 只能提出 Proposal。

### NET-INV-002

Host 负责 Validation。

### NET-INV-003

Canonical Shared State 只由 Host Commit。

### NET-INV-004

Authority Revision 用于拒绝 Stale State。

### NET-INV-005

Shared / Personal / Owner Scope 不混用。

---

## 5. Shared-State Flow

```text
Client Intent
-> Proposal
-> Host Validation
-> Canonical Commit
-> Revision
-> Replication
-> ACK / Replica
```

---

## 6. Bootstrap

新 Client 加入时：

- 从 Host 获得必要 Shared State；
- 建立当前 Revision；
- 建立 Replica；
- 按当前协议进行 ACK / Fingerprint 校验。

---

## 7. Fingerprint

Fingerprint 用于检查状态 / 配置一致性边界。

如果新 Shared State 纳入 Fingerprint：

- Host / Client 必须使用一致算法；
- 版本变化需考虑兼容。

---

## 8. Persistence

Shared State 的正式持久化：

> Host Write

Client Replica 不应独立变成共享世界存档真源。

---

## 9. Failure Handling

### Stale Revision
拒绝或重新同步。

### Invalid Proposal
Host Reject。

### Client Local Divergence
以 Host Canonical State 修正。

### Disconnect
只按照当前已实现能力处理，不夸大完整重连支持。

---

## 10. Extension Rules

新增 Shared State：

1. 定义 Scope；
2. 定义 Proposal；
3. 定义 Host Validation；
4. 定义 Canonical Commit；
5. 定义 Revision；
6. 定义 Bootstrap；
7. 定义 Fingerprint；
8. 定义 Persistence；
9. 补 Authority Tests。

---

## 11. Forbidden Patterns

- Client 直接写 Canonical Shared State；
- Shared State 依赖各 Client 本地时间作为最终事实；
- Owner State 与 Shared State 不加区分；
- 没有 Host Validation 的 Proposal。

---

## 12. Validation

- Valid Proposal；
- Invalid Proposal；
- Stale Revision；
- Bootstrap；
- ACK；
- Fingerprint；
- Owner / Personal Boundary；
- Host Persistence。

---

## 13. Non-Claims

当前不宣称：

- 完整断线重连；
- NAT Traversal；
- Dedicated Server；
- 产品级 Anti-Cheat；
- 完整双进程 E2E 覆盖；
- 所有 Shared Domain 都已迁移完成。
