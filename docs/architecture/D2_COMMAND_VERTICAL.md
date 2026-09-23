# D2 纵切：移动 / 攻击请求链

日期：2026-09-23。

```text
玩家输入 / AI
  → CommandRequest（entities/commands）
  → CommandRouter.submit_request
  → issue_stop / issue_move_to_wc3 / issue_attack_*（既有实现）
  → OrderQueue + UnitNavigator / AttackController
  → 表现（光标、确认 FX）仍由 interaction presentation
```

## 本批范围

- 新增 `CommandRequest` / `CommandResult`
- `CommandRouter.submit_request` 覆盖 STOP / MOVE / ATTACK / ATTACK_MOVE
- 既有 `issue_*` API 保留；输入模块可逐步改为构造 Request

## 刻意未做

- 将 `UnitOrder.target_id` 改为 EntityId（D5）
- 采集/建造/生产请求类型
- 建造瞄准从 Director 下沉（D5-build）

## 验收

```powershell
& $env:GODOT --headless --path . res://tests/unit/selftest_command_request.tscn
# 冒烟：移动、A 攻击、停止、目标死亡后攻击取消、重开
```
