# D5 实体与行为工厂（第一波）

## 已落地

| 类型 | 路径 |
|------|------|
| `EntityId` | `game/entities/state/entity_id.gd` |
| `EntityRegistry` | `game/entities/state/entity_registry.gd` |
| `BehaviorRegistry` | `game/features/abilities/logic/behavior_registry.gd` |

## 约定

- `UnitOrder.target_id` 仍为 instance_id（兼容）；新代码优先 `EntityId`。
- 出生时用 creationNumber 注册 EntityRegistry（由 UnitsModule 逐步接入）。
- 新技能行为经 `BehaviorRegistry.register_factory`；对局开始后 `freeze()`。

## 验收

```powershell
& $env:GODOT --headless --path . res://tests/unit/selftest_entity_behavior.tscn
```

后续按功能：harvest → build → production → abilities（一功能一波接命令入口与行动退出协议）。
