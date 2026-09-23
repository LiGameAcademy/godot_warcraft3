# 战斗模块

本目录聚合战斗职责，脚本 class_name、UID 和行为保持不变。

| 目录 | 职责 |
|---|---|
| `combat_module.gd` | 对局内服务装配、推进与信号连接 |
| `actions/` | AttackController 攻击状态机；ProjectileService 弹道飞行与命中时序 |
| `rules/` | CombatDamageTable 攻防与护甲计算；CombatRng 可注入随机数 |
| `logic/` | DamagePipeline 伤害入口；DeathService 死亡编排；CombatQuery 场景单位查询 |
| `presentation/` | 弹道外观、伤害飘字、受击闪烁 |

`logic/` 是已确认属于战斗、但仍依赖 Godot 节点和单位运行态的服务，不代表纯领域规则。伤害由 DamagePipeline 结算，显示层不负责命中扣血。

尚待拆分的边界：AttackController 通过 Unit 直接切换攻击动画；DeathService 修改尸体可见性；CombatQuery 读取场景节点与内容定义。后续应通过表现事件和单位状态访问接口拆分，不能仅靠移动目录宣称解耦完成。

单位通用生命状态、英雄成长、技能伤害与内容加载仍保留在各自既有模块，本次不改变状态所有者。
