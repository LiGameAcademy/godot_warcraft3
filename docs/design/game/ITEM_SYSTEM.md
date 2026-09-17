# 道具系统第一版

2026-09-13。对应 [实施计划 I0–I3](../../roadmap/ITEMS_AND_MELEE_AI_PLAN.md)。

## 模块与权威

| 模块 | 职责 |
|---|---|
| `ItemCatalog` | ItemDef/AbilityDataDef 的静态映射、首版支持行为、名称与资源路径 |
| `ItemInstance` | 实例身份、次数、冷却截止、持有者；不修改共享 Def |
| `Inventory` | 六格操作、使用事务、按实例汇总护甲、共享冷却组与快照 |
| `ItemPickupController` | PICKUP_ITEM 订单接近/重校验/领取；新命令替换即让步 |
| `ItemDropTable` | 固定掉落与互斥概率组、全局表引用、随机类别与等级 |
| `ItemService` | 会话地面实体生成、丢弃、死亡掉落编排与失败回滚 |
| `GroundItemVisual` | 现有模型缓存、材质修正、Stand 动画、名称及屏幕命中；`resolved_model_path` 优先 `.gltf`/同目录 `.scn` |
| `InventoryPanel` | 2×3 方格 tile、Art 图标、次数角标、冷却扇形、使用/丢弃/换槽请求 |

命令流：屏幕右键 → SmartTarget.ITEM → ItemHandler → CommandRouter.issue_pickup → ItemPickupController。拾取范围 128 WC3 单位；已经在范围内时不启动寻路脱困。

六格不自动合并同类物品。主动效果确认有效后才提交次数/冷却，满血或满蓝时不消耗。装备按实例累加，BuffQuery 汇总到战斗伤害和选中信息。

背包区域显式参与世界输入屏蔽，避免悬停状态尚未更新时点击槽位清空选中；移动/技能瞄准期间也优先交给背包 GUI。

死亡时先处理 ItemDef.drop 标记，再由 HeroDeathRegistry 保存留存背包，然后清空尸体背包。复活使用生产队列完成条目的 revive_entry 恢复快照；取消复活仍保留登记。地面容器失效时死亡掉落回滚到原格，避免吞物品。

随机编码核对 [War3Net RandomItemProvider](https://github.com/Drake53/War3Net/blob/master/src/War3Net.Build.Core/Providers/RandomItemProvider.cs) 及 [ItemClass](https://github.com/Drake53/War3Net/blob/master/src/War3Net.Build.Core/Widget/ItemClass.cs)：`Y + 类别字符 + I + 等级字符`；`Y` 类别代表任意，`/` 等级代表 -1（任意）。候选来自真实 ItemDef 的 pickRandom/class/Level，不把未实现道具替换成药水。

## 验证入口

- 数据/事务测试：运行 `res://tests/unit/selftest_item_system.tscn`。
- 完整对战接线测试：运行 `res://tests/integration/selftest_items_game.tscn`。自动通过实际鼠标输入验证拾取、背包使用和丢弃，通过键盘验证取消，通过 HUD 动作和祭坛队列验证复活；包含较长的地图加载过程。图形模式会生成 `.cache/item-system-tests/inventory_preview.png`。
- 既有回归：`selftest_unit_ai.gd`、`selftest_threat_table.gd`、`selftest_buff_system.gd`。
- [给玩家的手动清单](../../test-cases/items/TEST_CASES.md)。

测试结果应同时检查日志中的脚本错误与退出码，不应只凭 PASS 字样。完整地图进程退出时的资源释放诊断须单独记录，不能算成运行过程中无错误的证明。

2026-09-13 验证：Godot 4.6.3，道具逻辑 57 项通过，图形完整场景 16 项通过（含实际鼠标背包使用/丢弃）。既有单位 AI、仇恨、Buff 三组回归通过。最后一次图形运行未出现玩法脚本错误，但场景退出仍报告 RID/渲染资源释放告警，尚未解决。测试日志和界面截图保存在 `.cache/item-system-tests/`。

## 本次顺带修复

- AbilityCatalog 改为运行时获取 DefStore，与 UnitMana 的方式一致，避免独立脚本自测提前编译时 Autoload 标识符未注册。
- RuntimeAssets/AppLog 不再构造 `String.chr(0)`；构造本身会触发 Unicode NUL 错误，原有读盘层已经拒绝 NUL 字节。
- HealthBarManager 先检查 Variant 类型与实例有效性，再做类型判断，避免英雄尸体释放后访问失效对象。
- SpellHitFx 的节流标记改用资源路径摘要构成合法 metadata 标识符，修复低血量测试触发牧师治疗时的报错。

商店、回城卷轴、全效果、PowerUp 自动触发及磁盘存档在本版之外。

## 进度自检（与 [实施计划 I0–I4](../../roadmap/ITEMS_AND_MELEE_AI_PLAN.md) 对照）

| 段 | 内容 | 当前 | 关键证据 |
|---|---|---|---|
| I0 | ItemCatalog / ItemInstance / Inventory（六格）| **闭环** | `item_catalog.gd:18-42`、`item_instance.gd:14-22`、`inventory.gd:16-160` |
| I1 | GroundItem / ItemService / ItemPickupController / InventoryPanel / 智能右键拾取 / 抢道具 | **闭环** | `item_pickup_controller.gd:31-56`、`inventory_panel.gd:1-103`、`smart_handler_registry.gd:243-256`、Director L1465-1473 |
| I2 | 使用效果 / 装备护甲 / 死亡保留 / 复活恢复 / 共享冷却组 | **闭环** | `inventory.gd:99-134`、`hero_death_registry.gd:21-39`、`production_module.gd:144-160` |
| I3 | 死亡掉落 / 互斥组 / 全局表 / 随机码 / seed / 幂等 | **闭环** | `item_drop_table.gd:21-62`、`item_service.gd:65-73` |
| I4 | 商店 / 回城卷轴 / PowerUp 自动触发 | **缺失**（与文档预期一致，第二批）| 全仓零 `**/shop*.gd`、零 `purchase/buy/cost_gold` 调用 |

## AI 侧道具决策（与 [MELEE_AI.md](MELEE_AI.md) §4 共口径）

A3 已闭环：`PlayerArmyAI` 在集结/撤退时拾取白名单地面道具，并按 HP 低于 50% / MP 低于 30% 调用 `Inventory.try_use`（与玩家同规则）。装备感知微调仍可选增强；商店等见 I4。
