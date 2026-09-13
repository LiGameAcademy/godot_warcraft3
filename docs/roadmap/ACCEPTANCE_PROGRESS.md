# 验收证据记录

长期范围见 [ACCEPTANCE.md](ACCEPTANCE.md)。局部测试通过不代表所属里程碑整体通过。

## 2026-09-13：M1 物品生命周期局部回归

- 状态：有限支持；M1 完整对局仍未验收。
- 环境：当前 Windows 工作区，Godot 4.6.3；真实本地 SLK 数据；经典补丁基准尚未固定。
- 测试入口：`res://tests/unit/selftest_item_system.tscn`。
- 执行方式：Godot `--headless --path . --log-file tmp/item-lifecycle-test.log res://tests/unit/selftest_item_system.tscn`。
- 结果：退出码 0，`selftest_item_system: PASS (48 checks)`；本次输出无脚本错误。

### 已验证

原有 36 项检查涵盖实例身份、满包、生命/魔法药水、共享冷却、换槽/转交、护甲叠加、死亡登记与复活快照、掉落表和基础图标解析。本次新增 12 项检查：

- 两英雄在同次逻辑推进中争抢同一物品，仅一方拿到原实例，双方拾取任务结束。
- 远距离不能瞬间拾取；移动新命令替换拾取后，旧任务不拾物也不清除新命令。
- 满包、无路径、英雄死亡均不会把地面物品吞掉。
- 从真实数据找到死亡掉落物；地面容器不可用时保留原实例、原槽位与持有者；容器恢复后掉落成功；再次执行不复制掉落。

### 缺陷证据与修复

`ItemService.prepare_hero_death` 原先先从背包移除物品，再尝试生成地面实体，未处理生成失败。通过未配置地面容器复现物品丢失；修复前新增测试中 3 项失败，修复后全部 48 项通过。现在生成失败会把物品放回原槽位，并发出可诊断消息，供后续死亡登记保留。

### 验证边界与下一步

拾取检查直接推进控制器逻辑并设置远近位置，没有证明实际寻路、鼠标命令路由和 HUD 的完整交互。尚需完成真实地图中的移动拾取、清野掉落、丢弃、死亡复活人工剧本；商店、完整物品效果、跨进程存档及确定性冷却尚未验收。现有物品冷却使用进程时间，不能据此声称满足联机和存档目标。

下一项 M1 主要缺口仍为多玩家经济/命令隔离、电脑经营与进攻、胜负结算，以及完整对局验收。

## 2026-09-13：M1 生产与死亡结算的玩家隔离

- 状态：局部通过，多玩家命令和经济整体仍未验收。
- 环境：当前工作区，Godot 4.6.3，真实本地定义数据。
- 测试入口：`res://tests/unit/selftest_production_owners.tscn`；使用 `--headless --path . --log-file tmp/production_owners-regression.log` 运行。
- 复现：原有实现的退款、研究完成和阵亡人口依赖本地玩家，初始 7 项检查中有 6 项失败。
- 修复：训练取消信号携带订单 owner；研究完成和出生失败使用订单 owner；阵亡释放人口使用单位 owner；仅访问会话已有库存，不为中立单位隐式建库存。
- 验证：扩展后的 10 项检查全部通过（退出码 0）；涵盖电脑取消、本地库存不受影响、建筑换主后的原订单归属、研究、阵亡幂等、出生失败、本地取消和中立单位。故意缺省地图生成器的出生失败用例会输出一条预期警告。
- 相关回归：`selftest_item_system: PASS (48 checks)`，退出码 0。

测试使用真实 Director 的队列信号接线和两个独立库存，但直接入队，不代表电脑已经能够通过命令入口建造、生产和经营。下一步还需处理命令授权、下单扣费、建造经济、复活取消的非 UI 路径，以及双方开局与完整对局。

## 2026-09-13：M1 独立玩家生产命令入口

- CommandRouter 新增可选的固定玩家配置，电脑可使用独立实例；默认本地入口行为保留。训练、研究和顶盾查询使用该入口所属玩家的库存，不切换 session.local_player。
- 无已注册库存时拒绝训练/研究，不能绕过资源检查免费生产。
- 下单发出 production_queue_ready，由 Director 幂等接线；生产的完成/取消回调不再依赖界面选择建筑。后续新增电脑 Router 也需接此信号。
- `selftest_production_owners` 扩展到 29 项通过，退出码 0：包含人类/电脑互相越权拒绝、资金不足、七槽填满后的费用/人口回滚、真实命令取消退款、研究扣费/重复拒绝/科技授予、未注册玩家拒绝。出生失败测试保留一条预期警告。
- 当前工作区相关回归：`selftest_item_system: PASS (57 checks)`，退出码 0。

尚未完成：电脑 Router 的实际会话创建、建造扣费及额外工人费用归属、双方开局、经营和进攻。移动等历史系统入口仍存在调用方先筛选的约定，不能把本次生产权限验证扩展为所有命令均已完成权限审计。

## 2026-09-13：M1 建造资源所属玩家

- 新增 `selftest_construction_owners.tscn`，实际调用 BuildController.start_build/cancel 与 BuildSite 的加速费用结算，使用真实建筑数据和可建造的测试寻路网格。
- 修复前 8 项中 5 项失败：电脑开工扣了本地库存，换主退款、加速费用和电脑资金不足也未隔离。
- BuildOrder 在成功扣费时记录 owner；控制器按工人所属玩家扣费，退款按订单 owner；工地启动、半成品生成沿用该 owner；加速费用按工地 owner。建筑完成增加人口上限改为完成事件的玩家库存。
- 修复后 `selftest_construction_owners: PASS (8 checks)`，退出码 0；相关 `selftest_production_owners: PASS (29 checks)`，退出码 0（出生失败用例的预期警告仍在）。
- 测试验证行进中取消、换主退款、重复取消拒绝、加速费用与资金不足。测试未推进实际寻路施工到完工，因此半成品归属、完工人口仍需端到端验证，不能标为整体通过。

剩余主线：核对建造取消的其他入口及多人协助权限，创建双玩家会话与电脑命令接线，经营/进攻决策和完整胜负对局。

## 2026-09-13：取消生产权限与复活登记恢复

- 复现：本地 `_on_train_queue_cancel` 未检查建筑可控性；直接 `TrainQueue.cancel_at` 取消复活未恢复英雄登记，只有 UI 路径负责恢复。新增测试中 3 项失败。
- 修复：本地取消入口验证存活和所属玩家；队列取消回调绑定来源队列并一次性消费取消条目，统一恢复英雄登记，移除 UI 的重复恢复职责。
- 验证：`selftest_production_owners: PASS (34 checks)`，含敌方取消拒绝、非 UI 取消保留等级/经验/背包、重复取消不复制、己方界面取消正常且只恢复一次。退出码 0；出生失败用例保留预期警告。
- 相关回归：建造 8 项、物品 57 项通过，退出码均为 0。
- 边界：测试直接调用界面事件处理器，未模拟鼠标点击。建筑销毁是否主动取消全部队列、多人协助权限和完整双方对战仍需验证。

## 2026-09-13：建筑摧毁的人口上限结算

- 已复现：人口死亡结算只释放单位占用人口，没有扣回建筑提供的人口上限。修复前新增 4 项检查中 3 项失败。
- 修复：死亡结算同时扣回已完成对象的 food made；未完工建筑不扣未授予的上限；沿用原有所属玩家库存与一次性结算标记。
- `selftest_production_owners: PASS (38 checks)`，退出码 0。新增覆盖电脑农场、本地主城、重复通知及未完工建筑；现有部队的人口占用保持不变。出生失败回归仍产生一条预期警告。
- 边界：直接调用死亡结算函数，尚未通过实际攻击摧毁建筑验证完整流程。建筑死亡时的生产队列清理仍未完成；地图预置建筑的开局人口统计也需核对。

## 2026-09-13：建筑死亡终止生产队列

- TrainQueue 增加永久终止状态，从尾部清空队列，不启动等待订单，拒绝之后的入队；Director 死亡流程接入终止与统一取消结算。
- `selftest_production_owners: PASS (45 checks)`，退出码 0。新增 7 项验证清空停止、等待订单不启动、预占人口释放、复活登记保持、退款、重复通知幂等和拒绝新订单。出生失败回归保留预期警告。
- 明确的暂定规则：建筑死亡终止暂沿用项目已有主动取消退款（100%），不是已确认的经典摧毁退款行为。[暴雪 Building Basics](https://classic.battle.net/war3/basics/buildings.shtml) 的 Refunds 段给出主动取消训练、研究、复活的比例，但没有明确建筑摧毁的语义。应以选定补丁客户端实测正在生产/等待队列/研究/复活各情况后对齐；在此之前，此项属于有限支持。
- 验证边界：直接调用死亡流程中的生产清理函数；实际攻击摧毁建筑及场景销毁的完整生命周期仍待集成测试。终止守卫也覆盖进度通知期间触发终止后的继续执行。

## 2026-09-13：真实场景双玩家开局

- Director 增加 `spawn_opponent_base` 开关（默认关闭，待电脑经营接入）。开启后在剩余物理出生点生成另一玩家的人族主城和工人，建立独立库存；已有对手库存时拒绝重复生成。
- MeleeBootstrap 按坐标排除本地出生点和重复 sloc，避免不同 owner 的重复地图记录导致基地重叠。
- 集成入口：`res://tests/integration/selftest_two_player_start.tscn`。实际加载 `game_main` / Echo Isles，关闭开发英雄和牧师，开启对手基地；Godot headless，日志 `tmp/two-player-start.log`。
- 功能结果：`selftest_two_player_start: PASS (9 checks)`，进程退出码 0；双方各有五工人、不同位置主城、独立初始金币，电脑人口匹配工人及主城，重复开局拒绝。
- 稳定性未通过：退出时出现渲染依赖泄漏、ObjectDB 和资源仍在使用告警，需要继续排查场景释放。不得将功能检查通过解释为无错误或可稳定发布。
- 尚无电脑经营/进攻控制器；此次验证只是双方开局。资源部分缺失导致只生成部分工人的失败恢复、不同本地玩家编号与其他地图还需覆盖。

## 2026-09-13：真实对手工人采金与交货

- 发现 HarvestController 的库存回调仍绑定 `_local_stock`。现按工人节点查询当前 owner 对应的已注册库存，已有和新建采集控制器均使用同一入口。
- 双玩家集成测试增加对手工人：通过独立 CommandRouter 下采金命令，实际移动到金矿、采集并返回建筑交货，等待对手金币增加，检查本地金币不变。
- `selftest_two_player_start: PASS (13 checks)`，退出码 0；日志 `tmp/two-player-harvest.log`。未直接给金币或跳过采集过程。
- 渲染仍报空材质/无效 RID 与退出资源泄漏，稳定性门槛仍失败；本次只验证开局和一次采金往返功能。伐木、工人换主时的在途货物和采集点销毁仍需覆盖。
- 尚未建立自动分配工人、补工人、建造与进攻决策；本次由集成测试发出采金命令，不能声称已实现经营 AI。

## 2026-09-13：电脑自动采集分工

- 新增 `player_economy_ai.gd`，每秒为己方空闲工人决策：优先三名采金，其余伐木，已有货物优先送回；采集中、施工中或执行其他显式订单的工人不被周期性重置。
- Director 的 `enable_opponent_economy` 开关接入独立 Router 和已有资源/寻路/树木系统；配合 `spawn_opponent_base` 使用，两者仍默认关闭。新增 `PLAYER_AI` 命令来源。
- 真实双玩家集成测试先验证人工命令采金，再启用经营模块；测试不逐个派发采集命令，不直接增加库存，等待电脑自己交回金和木。
- `selftest_two_player_start: PASS (16 checks)`，退出码 0，日志 `tmp/opponent-economy.log`；电脑金木均实际增长，本地资源保持不变。
- 已有渲染 RID/空材质和退出泄漏错误仍在，稳定性未通过。当前仅完成采集分工，尚无补工人、建造、生产军队、进攻及胜负决策；资源目标可达性重试和资源枯竭恢复还需专项验证。

## 2026-09-13：电脑付费补工人与新工人采集

- 经营模块增加工人目标数量（默认 8），按存活工人加所有生产队列中的工人判断缺额，经公共训练命令补充，不直接生成单位。
- 集成测试将目标从 5 增到 6，连续执行决策验证只扣一次真实工人造价；等待正常训练完成并观察新工人自动进入采集。未加速训练或补测试资源。
- 发现并修复：金矿内部工人会暂时退出 WorldMembership，原筛选将他们误算为缺员导致多排工人。人数统计现覆盖仍存活的矿内工人；下达工作指令仍仅针对可交互的工人。
- `selftest_two_player_start: PASS (21 checks)`，退出码 0；日志 `tmp/opponent-workers.log`。增加了扣费一次、本地金币隔离、实际出兵、新工人采集、人口预占一致性验证。
- 退出仍存在 RID/渲染依赖等泄漏，稳定性未通过。实际阵亡后补工人、人口不足时建农场及资源不足恢复还需测试；电脑建造、军队生产和进攻尚未完成。

## 2026-09-13：电脑实际施工建农场

- 经营模块增加人口余量阈值，资源充足且没有行进中或施工中的农场时，选择可交互且未携带资源的工人，在主城周围有限候选点中检查落点与路径，经公共建造命令开工。
- 复用真实采集资源、建造扣费、工人移动、工地进度、建筑完成和人口结算；没有直接生成农场或修改测试人口。
- 集成测试调高人口余量阈值以触发建造，等待实际完工，检查对手增加一座农场的人口、本地人口不变、恰好一座农场。
- `selftest_two_player_start: PASS (24 checks)`，退出码 0；日志 `tmp/opponent-farm.log`。真实完整施工使此前“完工人口仍待端到端验证”的局部缺口得到一次 Echo Isles 场景验证。
- 渲染错误与退出资源泄漏仍存在，稳定性未通过。工人途中阵亡、断路重试、无可用落点、废弃工地接管和主城周边通道质量尚需覆盖；兵营、祭坛、军队和胜负尚未完成。

## 2026-09-13：模型缓存原型释放与一次干净场景回归

- 已复现：MapModelCache 的 RefCounted 对象释放后，保存在 Dictionary 中、未入 SceneTree 的模型原型 Node 仍存活。新增 `selftest_model_cache_lifetime` 修复前报原型泄漏。
- 修复：缓存收到 PREDELETE 时释放其持有的原型节点；不释放已经返回给场景的实例副本。
- 独立测试 `selftest_model_cache_lifetime: PASS (3 checks)`，验证缓存销毁、原型释放及已生成实例保留，退出码 0。
- 完整回归 `selftest_two_player_start: PASS (24 checks)`，退出码 0；包含开局、金木采集、补工人和农场施工。完整合并输出保存至 `tmp/cache-scene-output.log`，本次 ERROR/WARNING/leak 匹配数为 0；引擎日志为 `tmp/cache-scene-regression.log`。
- 结论限于一次干净完整回归。之前 RID 错误出现位置不固定，不能仅凭本次结果宣称全部渲染问题永久解决；重复开关地图、长时间运行和内存趋势仍未达到 M6 稳定性验收要求。

## 2026-09-13：电脑兵营、祭坛与初始军队

- 将农场选址施工提为通用建造入口，任一工人正在施工时不再抢走工人下另一栋建筑。军备决策依次补兵营、祭坛，全部完工后优先训练一名大法师，再补步兵（目标 6）。
- 军备数量统计包含存活单位和生产队列；英雄已在阵亡登记中时不重复购买新英雄。英雄复活的经营决策仍待实现。
- 对手经营模块的 `develop_army` 默认开启；外层对手开局/经营开关仍默认关闭。测试先关闭军备完成经济验收，再开启并等待真实施工、英雄和步兵生产。
- `selftest_two_player_start: PASS (27 checks)`，退出码 0；本次完整合并输出 `tmp/opponent-army-output.log` 无错误或警告，引擎日志 `tmp/opponent-army.log`。测试未补资源、未直接生成军备、未加速时间。
- 新增验证两栋已完工建筑各一座、一个实际英雄和至少一个实际步兵。六步兵目标、阵亡补兵、军队集结/进攻/回防、英雄升级施法和胜负结算尚未验收；本次不是完整对战通过。

## 2026-09-13：电脑军队调度决策

- 新增 `player_army_ai.gd`，集结/进攻/回防/撤退状态，默认四个战斗单位出击、只剩一个时撤退；工人不纳入军队。以每单位命令目标签名避免重复重置，增援单独派发。
- Director 增加 `enable_opponent_army`（默认关闭，配合对手经营开关），通过既有 Router 下 Move/AttackMove；军队只消费注入的敌情观察接口。
- 当前会话观察接口明确采用全图可见的开发规则，并排除中立对象作为战略目标。战争迷雾和联盟规则还未接入，不能声称公平对战 AI 已完成。
- `selftest_player_army: PASS (10 checks)`，退出码 0，无错误/警告；日志 `tmp/player-army.log`。验证兵力门槛、工人排除、电脑来源、命令不重复、增援、回防、恢复进攻、重损撤退及观察目标消失。
- 测试使用真实单位定义和状态查询，但 Router 为记录替身，仅证明调度意图；真实行军、交战、两轮进攻、断路重试和实战回防仍待集成验收。地图上实际抵达集结区后再统一出击的队形门槛也尚未实现。

## 2026-09-13：真实接敌测试与建筑攻击距离修复

- 新增 `selftest_player_army_game.tscn`：加载真实双玩家地图，以四名步兵作为战斗夹具，停止经营决策，由真实电脑军队调度、Router、寻路和攻击系统完成移动与建筑扣血。默认在敌方基地附近生成；传入 `-- --full-route` 从己方基地生成，保留完整远征验收。此测试不证明军队由经济生产所得。
- 初始远征失败：军队移动但主城生命始终为 1500，后期减员并撤回；日志 `tmp/army-game-output.log`。随后近基地诊断发现四名健康步兵已索敌主城，却持续 CHASE。该诊断运行工具句柄随后丢失，未取得完整退出结果，仅作为定位线索，日志 `tmp/army-approach.log`。
- 独立用例复现根因：步兵在主城阻挡区外已贴近建筑，却因中心距离大于射程而不能出手。修复前 `selftest_building_attack_range` 7 项中 2 项失败，日志 `tmp/building-range-before.log`。
- `CombatQuery` 对有占地的建筑按轴对齐占地最近边缘计算武器距离，统一出手、交战与自动索敌；移动单位及无占地目标保留既有中心距离。未改变武器射程或叠加 RngBuff。这是当前项目的占地几何规则，尚未证明精确复现原版碰撞算法或非矩形路径纹理。
- 修复后专项测试 `PASS (8 checks)`：边缘内外、角落欧氏距离、交战范围、Hold 射程索敌、移动单位与显式容差；日志 `tmp/building-range-after.log`。
- 基地附近真实集成 `PASS (5 checks)`，退出码 0，验证实际移动和主城扣血，日志 `tmp/army-approach-fixed-output.log`。该次出现材质/RID 错误及 2 个 Material RID 退出泄漏，功能通过不等于稳定性通过，也不能代替完整对战验收。
- 最终距离修复包含索敌改动后，军队决策回归 `selftest_player_army: PASS (10 checks)`，日志 `tmp/player-army-range-regression.log`。完整远征模式 `FAIL (5 checks)`：四名步兵在地图中段与 `nmrk`、`nogr` 交战，三名阵亡、一名返回己方基地，敌方主城未受伤；日志 `tmp/army-route-fixed-output.log`。这验证了真实行军、接敌和减员后返程，但明确未通过基地进攻目标。下一步应验证正常经营生产的英雄/步兵编队，并据实改进路线或兵力判断；不能用近基地夹具通过替代 M1 完整对局。

## 2026-09-13：正常开局人口规划死锁

- 新增 `selftest_opponent_campaign.tscn`，正常双玩家开局并同时启用经营和军队模块；不生成测试军队、不补资源、不加速、不直接下达作战命令。检查真实建筑、英雄和步兵生产、远征及敌方主城扣血。名称中的 campaign 指本次远征测试，并非 M7 剧情战役实现。
- 代码与独立测试确认：默认八工人占用 8/12 人口，剩余四人口无法训练五人口的首英雄；旧逻辑只在余量不足二时补农场，造成生产死锁。专项修复前 `FAIL (5 checks)`，失败项为首英雄人口不足时没有建农场，日志 `tmp/economy-supply-before.log`。
- `_ensure_supply` 现在同时考虑即将训练的首英雄人口需求；已有或在训英雄不重复预留，已阵亡英雄留待复活流程处理。关闭军备仍按常规人口余量规划。实际建造继续使用原有资源检查、路径检查和工人施工。
- 修复后 `selftest_economy_supply: PASS (7 checks)`，退出码 0，日志 `tmp/economy-supply-after.log`。覆盖人口不足、恰好足够、关闭军备、已有英雄、常规余量不足和英雄在训。
- 修复前正常地图对照运行持续处于 8/12 人口，保留 `tmp/opponent-campaign.log`；为运行修复版主动终止，退出码 1，未取得完整集成结论，不能记为超时失败或完整通过。
- 修复后正常开局集成 `selftest_opponent_campaign: PASS (6 checks)`，退出码 0，日志 `tmp/opponent-campaign-fixed-output.log`。观察到电脑自行建成兵营、祭坛和两座农场，人口上限先增至 18 再增至 24，实际生产大法师与步兵，军队进入 ATTACK 并离开基地，最终敌方主城生命下降；没有添加测试军队、资源或加速。
- 本次合并输出无 `ERROR:`，但有 4 条 `WARNING:`，均涉及 Attack 动画解析/播放失败。表现与稳定性门槛仍未通过。测试目前以主城生命下降作为伤害终点，尚未通过 DamagePipeline 事件单独核对最后一击来源；后续需增加来源断言，继续验证主城摧毁、英雄复活、两轮进攻及胜负结算。不能把本次首次进攻观察记为 M1 完整对局通过。

## 2026-09-13：建筑清场规则与进攻来源验收

- 核对官方 [Team Strategies](https://classic.battle.net/war3/basics/teams.shtml) 与 [Delay of Game](https://classic.battle.net/war3/basics/delayofgame.shtml)：团队全部建筑被摧毁才失败，主城损毁本身不是充分条件。未确定基准补丁前，不能据此声称全部细节兼容。
- 新增 `MeleeVictoryRules.evaluate`：消费显式玩家—团队配置和单位快照，仅在开局完成后启用；存活建筑按团队汇总，包括工地，排除未参赛对象与工人。单方测试地图不自动结束。双方同一快照均无建筑时判和是明确的项目规则，原版同帧行为仍待对照。
- `selftest_melee_victory: PASS (8 checks)`，退出码 0，日志 `tmp/melee-victory.log`。覆盖开局保护、双方存活、主城毁而农场存活、工地、工人/中立对象排除、盟友建筑、同时归零与单方地图。此模块尚未接入会话锁存、停止模拟或结算界面，不能声称游戏已能正常结算。
- 正常经营远征测试增加 DamagePipeline 事件核验，过滤目标实例、攻击者 owner=1 与英雄/步兵类型，并等待该军队的致命伤害；不再只用血量下降证明来源。等待上限扩大到开局完成后十分钟，用于实际建筑摧毁验收。
- 严格集成结果 `selftest_opponent_campaign: FAIL (8 checks)`，退出码 1，完整日志 `tmp/opponent-base-destruction-output.log`。八项中伤害、攻击者来源、主城摧毁三项失败，其余初始化、建筑/军队生产及远征检查通过。十分钟内主城生命始终为 1500，未收到符合条件的伤害事件；英雄后期阵亡，六名步兵长期保持宏观 ATTACK 状态，无法由此判断其微观寻路/交战原因。
- 本轮存在材质/RID 错误与攻击动画警告。上轮仅观察掉血的结果不能证明稳定进攻能力；当前来源核验与建筑摧毁明确未通过。下一步需记录每个军人的位置、AttackController 实际目标/状态与导航状态，定位进攻停滞，同时补齐英雄复活。胜负规则仍只是独立计算模块，尚未整合到对局。

## 2026-09-13：追击与导航朝向冲突

- 远征测试增加每名存活英雄/步兵的位置、生命、AttackController 状态和目标、导航移动状态与剩余路径日志；保留原有伤害来源和主城摧毁断言。
- 独立复现一个追击问题：敌人在东方，但绕障路径首段向西时，`_chase_or_strike` 每帧强制面向敌人，覆盖导航朝向并触发转向降速。修复前 `selftest_attack_chase_facing: FAIL (4 checks)`，朝向断言失败，日志 `tmp/chase-facing-before.log`。
- 修复为射程外追击由导航控制朝向，进入射程后才面向敌人；不更改射程、路径或速度参数。修复后 `PASS (6 checks)`，包含实际 UnitNavigator 与追击共同步进 60 次，验证能够向绕障首段推进，日志 `tmp/chase-facing-after.log`。
- 该专项验证尚不能证明十分钟远征停滞全部由朝向冲突引起；正在采集的地图诊断加载的是修复前控制器，须明确区分对照与修复后的整场回归。
- 对照日志 `tmp/opponent-tactical.log` 最终抓到六名步兵全部停在中立市场 `nmrk` 周围，连续两次采样均为 WINDUP/COOLDOWN、目标为该市场，路径为空。此前已实际击杀/切换食人魔目标并继续行军；因此本次停滞不是仅凭宏观状态推测的路径失败。取得稳定复现后主动终止该诊断，退出码 1，未等十分钟断言结束。
- 市场定义确有 `Avul`，但攻击合法性、自动索敌和伤害入口都未处理永久无敌。[官方中立建筑说明](https://classic.battle.net/war3/neutral/buildings.shtml) 明确中立建筑无敌。新增数据驱动的永久无敌查询，排除攻击/伤害目标，不用市场 ID 特判，也不改友军治疗/增益基础查询；临时无敌状态仍需另行实现。
- 修复前 `selftest_invulnerable_targets: FAIL (8 checks)`，其中六项失败，日志 `tmp/invulnerable-before.log`。修复后 `PASS (8 checks)`，日志 `tmp/invulnerable-after.log`：验证市场数据、自动/显式攻击、伤害技能、伤害入口、索敌选择和友军技能，并使用真实 AttackController+DamagePipeline 验证跳过更近市场、对敌方主城实际扣血。
- 相关回归：`selftest_gas_healing: PASS (20 checks)`；`selftest_ability_blizzard: PASS`。日志分别为 `tmp/invulnerability-healing-regression.log` 和 `tmp/invulnerability-blizzard-regression.log`。
- 两项修复后的正常经营整场回归 `selftest_opponent_campaign: FAIL (8 checks)`，退出码 1，日志 `tmp/opponent-invulnerability-fixed-output.log`。主城伤害、攻击者来源、主城摧毁三项仍失败；本轮战术日志中 `target=nmrk` 为零，军队与 `nogr`/`nomg` 交战后减员并撤回，未再观察到围攻市场的停滞。采样不能单独证明所有时刻均未索敌市场，永久无敌专项测试提供该过滤的直接验证。
- 本轮仍有材质错误和攻击动画警告。英雄出场日志生命为 100，随后在野怪战阵亡；英雄生命与属性结算应列为下一项核查，不应直接把低生存力全部归因于战术。电脑英雄复活、完整两轮进攻与对局胜负仍待完成。

## 2026-09-13：英雄生命遗漏力量加成

- 确认 `UnitLife` 原来只使用 UnitBalance 的基础 HP，导致大法师出生仅 100。官方 [英雄基础规则](https://classic.battle.net/war3/basics/heroes.shtml) 给出力量每点增加 25 生命；[大法师等级表](https://classic.battle.net/war3/human/units/archmage.shtml) 给出一级 450、十级 850 等对照值。
- 生命上限改为基础 HP 加等级力量加成，力量先取整，出生百分比应用到完整上限；非英雄保持原计算。`HeroProgression.set_level` 同步生命上限，按项目策略保持已受伤害量；死亡英雄保持零生命，重复设置同等级不回血。物品力量/生命加成尚未整合到该计算。
- 修复前 `selftest_hero_life: FAIL (14 checks)`，其中初始生命、出生百分比与等级上限对照失败，日志 `tmp/hero-life-before.log`；修复后 `PASS (14 checks)`，日志 `tmp/hero-life-after.log`，覆盖一级至十级、部分生命出生、非英雄、受伤升级、重复同步与死亡保护。
- 真实场景 `selftest_hero_life_game: PASS (6 checks)`，退出码 0，日志 `tmp/hero-life-game-output.log`：正常训练完工出生入口创建真实英雄模型后为 450/450，恢复六级状态后为 675/675，重复英雄运行时初始化保留伤害。测试为生命周期夹具，未验证支付费用、训练计时、真实死亡到祭坛复活的完整流程，也未重跑整场远征。
- 英雄技能与自然回复回归均通过：`selftest_hero_skill: PASS`、`selftest_unit_regen: PASS`。真实场景退出有 ObjectDB 泄漏警告，稳定性仍未通过。
- 本次核对还发现 `UnitMana.HERO_MANA_PER_INT` 当前为 12，而上述官方规则为 15；主属性伤害、敏捷护甲/攻速及完整属性来源也需继续审计。不能由本次生命修复推导英雄属性整体已正确。

## 2026-09-13：英雄智力与魔法上限修正

- 按上述官方英雄规则及大法师等级表，将魔法上限从智力乘 12 改为取整智力乘 15；避免将未取整的等级成长直接乘入上限。非英雄仍使用原有 mana_n/mana0。
- `HeroProgression.set_level` 现在同时同步生命和魔法上限，不再依赖界面或被动技能初始化额外触发。魔法上限增长时保留已消耗量；重复同步不补充魔法。
- 新增 `selftest_hero_mana`，修复前 `FAIL (12 checks)`，修复后 `PASS (12 checks)`；日志 `tmp/hero-mana-before.log`、`tmp/hero-mana-after.log`。覆盖一级至十级具体上限、升级后的余额、重复同步及不足支付。原英雄技能测试只断言满蓝能支付一次水元素，现补强为一级上限恰为 285；同步修正玩法文档中的旧乘数。
- 真实模型生命周期集成 `selftest_hero_life_game: PASS (9 checks)`，退出码 0，日志 `tmp/hero-vitals-game-output.log`：出生 450 生命/285 魔法，恢复六级 675/525，重复运行时初始化保留伤害和耗蓝。仍为出生/恢复生命周期夹具，不代表完整付费训练、死亡复活或远征对局验收。
- 生命专项 14 项、英雄技能、自然回复回归全部通过。真实场景退出仍有 ObjectDB 泄漏警告；本轮未重跑整场远征。主属性伤害、敏捷衍生属性、装备/临时属性加成与完整英雄成长仍待验证。

## 2026-09-13：英雄战斗属性与选中面板

- 使用真实数据与官方英雄规则核对：大法师武器基础为 2d4、固定加算为 0；原默认攻击遗漏主属性，实际只产生 2–8 原始伤害。一级 realdef=3.1 已包含初始敏捷，不能再加一遍；原逻辑也没有增加升级后的敏捷护甲或应用敏捷攻速。
- 默认武器结算现在补取整主属性伤害；显式 dmgplus 参数与技能伤害保持调用方数值。护甲保留一级派生值，只叠加等级带来的敏捷差值；攻击间隔与伤害前摇按每点敏捷 2% 的攻速换算。装备和临时属性来源尚未整合，动画播放速度与临时攻速叠加仍需专项核查。
- 选中面板改用当前等级的攻击、护甲和力量/敏捷/智力，避免高等级英雄仍显示一级数值。本轮核验的是面板数据，尚未进行屏幕视觉验收。
- `selftest_hero_combat_stats` 修复前 `FAIL (9 checks)`，其中七项失败；修复后扩展到 `PASS (14 checks)`，日志 `tmp/hero-combat-before.log`、`tmp/hero-combat-after.log`。覆盖一级伤害 21–27、十级下限 49、护甲 3.1/5.8、敏捷攻击间隔/前摇、固定伤害边界、非英雄与十级面板数据。
- 真实场景 `selftest_hero_life_game: PASS (12 checks)`，日志 `tmp/hero-combat-game-output.log`：包含六级真实英雄原始伤害 37 和受击护甲 4.6，经会话 DamagePipeline 验证；退出仍有 ObjectDB 泄漏警告。通用伤害表及弹道类型/参数回归通过，不能由弹道参数测试推导所有实际命中情况均通过。
- 更新英雄基础属性后的完整经营远征 `selftest_opponent_campaign: FAIL (8 checks)`，退出码 1，但八项中仅“摧毁主城”失败，其余七项通过。日志 `tmp/opponent-hero-stats-fixed-output.log` 记录正常生产的大法师以 450 生命出征，野怪战后仍存活并继续行军，随后 `campaign verified damage: attacker=Hamg owner=1` 明确证明其击中敌方主城；最后一条周期记录主城为 1193.46 生命。
- 本轮完成了此前缺失的伤害来源核验，未完成十分钟上限内摧毁主城。运行存在大量空材质错误；其是否影响模拟速度尚未测量，不能将超时直接归因于渲染。测试另一方未主动经营或下达战术指令，不能当作对抗活跃玩家/电脑的完整对局。下一步应继续完成基地摧毁与会话结算，并处理渲染错误对长时间验收的干扰。

## 2026-09-13：远征计时与会话结果锁定

- 上一轮结束来自脚本自身十分钟现实时间上限，不是外层运行器中断。本轮保留全部八项断言，将观察窗口延长为十五分钟，增加现实时间与累计 `_process(delta)` 时间、最终生命及有效伤害记录；该扩展不能视为通过原来的十分钟时限。
- `GameSession` 增加显式启用的参赛队伍快照、结果锁存、只触发一次的结束信号和结果副本读取。未启用或单方地图不产生终局；调用方修改队伍、信号载荷或返回字典不能污染已确定的结果。
- `selftest_match_session: PASS (8 checks)`，日志 `tmp/match-session.log`。相关回归：胜负规则 8 项、生产归属 45 项、建造归属 8 项全部通过，日志 `tmp/session-regression-*.log`；生产夹具仍有预期的缺少刷单位环境警告。
- 会话 API 尚未连接 GameDirector 的实际对局生命周期、结算界面或停止模拟逻辑。本轮运行中的远征在该 API 添加前已加载场景，不能用其结果证明会话结算集成通过。新增 [人族对战验收规程](../test-cases/MELEE_ACCEPTANCE.md) 明确自动远征与完整 M1 的不同门槛。
- 正常经营远征首次完整通过：`selftest_opponent_campaign: PASS (8 checks)`，退出码 0，整个进程耗时 638664 ms；日志 `tmp/opponent-timed-assault.log` 与 `tmp/opponent-timed-assault-output.log`。电脑自产军队穿过野怪营地、攻击主城，最终致命事件为 `attacker=hfoo owner=1 killed=true`，主城生命归零，累计有效伤害 1502.153846（包含致命一击溢出）。
- 致命事件发生于开局完成后现实时间 625.712 秒、累计处理时间 372.265 秒；600 秒时主城仍有 640.38 生命。本次确实超过原十分钟观察窗，不能回写为此前测试通过，也不证明十分钟内必定完成。两种时间差证明本次累计游戏处理时间落后现实时间，但不能单独定位性能瓶颈；不同运行的交战随机性也未控制，不能保证每次都在相同时间完成。
- 功能通过伴随渲染问题：128 次空 material 错误、16 次空 m 错误、RID 初始化/使用错误及退出时一项 DummyMesh RID 泄漏，另有攻击动画警告。该次通过仅限基础自动经营到摧毁主城的剧本；连续三局、主动对手、公平视野、真实英雄升级复活、会话结算界面及 M6 稳定性均未因此通过。

## 2026-09-13：双人对局接通结算界面

- `GameDirector` 在双人开局装配完成后启用会话判定，每帧检查参战双方建筑；最终结果锁存后停止本局全部已有节点的处理，包括选择器、AI、单位和开发面板。只冻结本局节点，不暂停外层编辑器/测试 SceneTree；结算层独立保持可操作。
- 增加胜利、失败、平局界面和退出按钮。当前双方各自成队，队伍来源为该双人开局已创建的玩家库存，未接入地图联盟/房间配置；仍无战绩统计、重开按钮。SceneTreeTimer 的既有尸体/表现清理回调不由节点 process_mode 自动取消，完整冻结语义仍需审计，不能宣称结算后所有回调都已停止。
- 新测试首次因局部变量类型推导失败未进入地图，确认错误后主动终止并修正；有效运行 `selftest_match_end_game: PASS (10 checks)`、退出码 0，日志 `tmp/match-end-game-fixed-output.log`。通过真实地图和 DamagePipeline/DeathService 验证最后建筑被摧毁后自动结算、本地失败显示、节点停止处理、结算层可处理，以及一秒观察中位置/资源和通知稳定。该夹具使用显式大伤害，不冒充自然经营远征；退出仍有 ObjectDB 泄漏警告。
- 界面渲染测试 `selftest_match_result_screen: PASS (10 checks)`、退出码 0，日志 `tmp/match-result-screen.log`。使用 OpenGL 隐藏窗口实际渲染，已检查 `tmp/match-result-victory.png`、`tmp/match-result-defeat.png`、`tmp/match-result-draw.png`，三种标题、说明和按钮均可见且未截断；按钮聚焦和退出请求通过。该画面为结算层独立渲染，不是完整地图背景截图。
- 本轮未重跑十余分钟自然经营远征；下一步需在同一次自然对局中核验结算，并补齐结算后延迟回调边界、重新开局与连续三局验收。完整 M1 和长期目标仍未完成。

## 2026-09-13：延迟回调随对局冻结与卸载

- 将尸体阶段/清理、金矿坍塌、树木动画、天神下凡姿态、临时附着特效、弹道命中特效、现代火球闪光和加载层等待从独立 SceneTreeTimer 迁移为宿主子 Timer。共享工具位于 `scripts/shared/infra/scene_delay.gd`；一次触发后回收，继承宿主处理状态，宿主销毁时取消等待，避免旧对局回调跨越卸载。
- `selftest_scene_delay: PASS (5 checks)`，验证正常触发一次并回收、冻结、恢复、卸载取消与新宿主独立计时。共享路径迁移后重复通过，日志 `tmp/delay-shared.log`。
- 真实地图结算测试扩展为 `PASS (12 checks)`，日志 `tmp/delay-selftest_match_end_game-output.log`：在结束前安排待执行回调，真实伤害触发结算后等待一秒不执行；卸载对局后计时器已销毁且回调未执行。仍有 ObjectDB 泄漏警告，不能据此宣称退出稳定性通过。
- 死亡动画回归通过，覆盖步兵防御姿态到 Death、DecayFlesh 和 DecayBone；弹道投送类型/飞行参数/资源回归通过，日志 `tmp/delay-selftest_death_anim.log` 与 `tmp/delay-selftest_c_combat_projectile.log`。这些回归不证明所有特效画面或完整尸体生命周期均已视觉验收。
- 这是已发现延迟机制的生命周期修复，不替代自然经营到结算的完整同场验证、重新开局及连续三局门槛。
- 加载层和现代火球也迁移完成后的最终真实地图回归仍为 `PASS (12 checks)`、退出码 0，日志 `tmp/delay-final-game-output.log`；退出对象泄漏警告仍在。

## 2026-09-13：加载遮罩卸载时的补间泄漏

- 详细真实地图日志 `tmp/match-leak-detail-output.log` 将本次退出泄漏定位为一个 Tween（引用计数 1）及 `finished` 信号名残留。独立用例在加载层淡出十秒、冻结并立即卸载时复现：`selftest_loading_lifetime: FAIL (3 checks)`，未结束 Tween 的弱引用仍有效，日志 `tmp/loading-lifetime-before.log`。
- 加载层原本 `await tw.finished`，取消动画不会正常完成该等待；改为 Tween 完成回调执行移除。修复后专项 3 项通过，真实地图 `selftest_match_end_game: PASS (12 checks)`、退出码 0；详细日志 `tmp/loading-fixed-selftest_match_end_game-output.log` 不再出现 ObjectDB 泄漏、Leaked instance 或其他 WARNING/ERROR。
- 再补最短显示时间尚未结束即卸载的边界：节点计时器已销毁，但 `await timeout` 留下信号名残留。将等待后的淡出改为 `_begin_fade` 回调，最终 `selftest_loading_lifetime: PASS (5 checks)`，详细日志 `tmp/loading-lifetime-callbacks.log` 无泄漏和未认领信号名报告。覆盖冻结淡出卸载、正常淡出、淡出前等待卸载；最后这项回调调整后通过专项，未再次重跑整张地图。
- 该证据修复的是快速结算/卸载加载层的已复现泄漏，不证明长时间远征中的材质/RID 问题、其他对象生命周期或两小时稳定性已通过。下一步继续重开与同场自然结算验收。

## 2026-09-13：结算后重新开始

- 结算界面新增“重新开始”。重开由旧局之外的临时节点执行：预先创建替换场景，复制 Director 导出的值配置（不复制运行时状态与节点引用），彻底销毁旧场景，再清理参赛玩家的静态英雄阵亡登记并装入新场景。正常主场景替换会更新 SceneTree.current_scene；嵌入测试则保持外层场景。
- `selftest_match_end_game.tscn -- --restart` 通过真实按钮事件执行重开，`PASS (21 checks)`、退出码 0，详细日志 `tmp/match-restart-output.log` 没有 WARNING/ERROR、泄漏对象或信号名残留。覆盖旧场景和计时器销毁、新场景就绪、会话实例不同、胜负清空、正常初始资源、英雄阵亡登记清空、出生配置保留及无旧结算层。
- 本次重开集成使用嵌入测试宿主和显式致命伤害夹具，未单独验证应用主场景指针分支，也不代表两局自然经营已打完。全局英雄登记仍是单活动对局设计，不支持同一进程并存多个独立对局。
- 三种结局界面测试扩展为 `PASS (14 checks)`，日志 `tmp/restart-screen.log`；重新渲染截图并检查胜利页，两个按钮完整可见。三种结局的退出与重开请求通过，重开请求后按钮禁用防止重复点击。
- 仍待自然经营到结算并连续重开的三局完整验证、战绩统计、正式玩家队伍配置及长期稳定性验收。

## 2026-09-13：活动主场景重开分支验证

- 集成测试增加 `--main-scene`：将真实 GameMain 放在根视口下并设为 SceneTree.current_scene，测试观察节点作为独立兄弟节点继续运行。经结算按钮重开后检查活动场景指针指向替换场景；最终卸载检查指针清空，外部观察未被停止。
- `selftest_match_end_game.tscn -- --restart --main-scene` 为 `PASS (24 checks)`、退出码 0，日志 `tmp/restart-main-scene-output.log`。包含此前资源、英雄登记、开局配置与会话隔离检查，补足上一轮未验证的主场景分支。仍采用显式致命伤害，不代表自然经营对局。
- 本次日志无 ObjectDB/Leaked instance/Orphan StringName 报告，但出现一项 DummyMaterial RID 退出泄漏、一次错误 RID 初始化、两次未初始化 RID 使用、三次空 material 和一次空 mem 错误。相关堆栈涉及单位粒子装配及旧场景释放，尚不足以定位根因；不能用功能 PASS 宣称重开稳定性通过。
- 下一步应定位重开中的渲染资源错误，并继续自然经营到结算的同场与连续三局验证；M1/M6 仍未完成。

## 2026-09-13：无窗口加载绕开 Dummy Renderer 并发缺陷

- 项目模型预载通过 ResourceLoader 后台创建 PackedScene 及渲染资源。Godot 官方 [问题 #121949](https://github.com/godotengine/godot/issues/121949) 报告无窗口 Dummy Renderer 的多线程资源创建会产生相同的错误 RID 初始化、空 mem/m 等报错；[修复 #121958](https://github.com/godotengine/godot/pull/121958) 针对 Dummy Renderer 的 RID 所有者线程安全。该上游证据与本地间歇报错高度吻合，但未通过引擎内部追踪单独证明本地所有历史错误的来源。
- `MapModelCache` 在 headless 模式将 .scn 预载排入主线程队列，每帧遵守既有解析预算；仍加载完整模型、材质和特效，不跳过相关行为或隐藏日志。有窗口模式保持原后台预载路径，GLB 字节读取仍可后台执行。此为当前引擎的应用侧规避，不是修改引擎或宣称所有后续版本均有该缺陷。
- 同一真实主场景结算/重开夹具连续启动三个独立进程，均 `selftest_match_end_game: PASS (24 checks)`、退出码 0，详细日志均无 ERROR/WARNING、Leaked instance 或 Orphan StringName。日志 `tmp/restart-main-serial-output.log`、`tmp/restart-main-serial-2-output.log`、`tmp/restart-main-serial-3-output.log`；后两次进程分别耗时 22180/22083 ms。
- 这是对原间歇渲染错误的三次修复后回归，不是三局自然经营对战，亦非两小时稳定性或 GPU 画面验收。主线程加载的单资源耗时及长期性能尚未量化；下一步继续自然经营到结算和连续重开验收。

## 2026-09-13：自然结算长测与英雄经验门槛核查

- 自然远征脚本扩展为 11 项，新增同场自动胜负、本地失败界面与对局/电脑控制器冻结检查。长测 `tmp/natural-match-end.log` 仍在运行，不能将历史八项通过推导为新增检查已通过；本次从原运行句柄持续观察，没有因观察超时重启。
- 等待期间核查 `HeroProgression`，原累计经验表三级为 700、十级为 14975，与 [官方英雄经验表](https://classic.battle.net/war3/basics/heroes.shtml) 不符。修正一级至十级门槛为 0/200/500/900/1400/2000/2700/3500/4400/5400，同时纠正索引注释。
- `selftest_hero_xp_thresholds: PASS (14 checks)`，日志 `tmp/hero-xp-thresholds-final.log`，覆盖十级门槛、下一等级、等级内经验条和设等级后的经验同步。首版测试过早调用数据表导致未注册警告，改为初始化完成后执行，最终日志无该警告。
- 此处只修正经验门槛；当前代码仍未接入击杀经验分配与自然升级，不能声称英雄清野成长已完成。正在运行的自然对局在修改前已加载脚本，也不能视为该修改的集成回归。

## 2026-09-13：经验入账驱动升级

- 新增 `HeroProgression.add_experience`，经验跨门槛时自动升级，可一次跨越多级；调用现有等级同步更新生命/魔法上限并保留伤害与消耗，技能点按新等级计算。拒绝非英雄、死亡英雄、非正奖励和无效引用，十级停止入账，经验封顶 5400。
- `selftest_hero_xp_gain: PASS (12 checks)`，日志 `tmp/hero-xp-gain.log`，包含 199→200 临界升级、生命/魔法余额、技能点、二级跨至五级、负经验、死亡、十级封顶、非英雄及空引用。
- 尚未连接死亡事件的经验奖励分配，距离/队伍共享、野怪经验折扣与五级限制、建筑击杀排除、单英雄科技奖励及升级表现仍需实现。本轮是成长入口的专项验证，不是自然击杀升级验收；现有自然对局进程继续使用其启动时加载的代码。

## 2026-09-13：自然长测进入野怪战，渲染问题仍有残留

- 原自然对局进程继续运行，现实时间约 420 秒时电脑有四名步兵和一名大法师，英雄正在攻击野怪 `nogr`，生命约 410；敌方主城仍为 1500。该状态是持续观察所得，不是另行启动的场景。
- `tmp/natural-match-end.log` 在交战期间再次出现空材质错误，位置为 Dummy Renderer 的 `material_get_instance_shader_parameters`，另有攻击动画缺失警告。此前三次短重开测试未触发这段战斗；主线程模型预载规避不能视为已消除所有无窗口渲染错误。本次尚未观察到之前的错误 RID 初始化，仍需区分不同报错路径。
- 保留同一长测继续采集最终结算，未停止、未重启；十一项验收仍未产生最终结果。

## 2026-09-13：首次自然经营至同场结算通过

- 持续观察的原进程最终 `selftest_opponent_campaign: PASS (11 checks)`、退出码 0，总进程耗时 660108 ms。日志 `tmp/natural-match-end.log` 与 `tmp/natural-match-end-output.log`，本次未因任何观察窗口到期停止或重启。
- 电脑正常经营、付费生产、清野行军后，大法师在现实时间 550.687 秒首次击中主城，并在 644.383 秒造成致命伤害；累计处理时间 371.195 秒，累计有效伤害 1508.153846（含溢出），主城生命为零。测试没有补资源、生成测试军队、加速或直接替电脑下作战命令。
- 主城摧毁后由 Director 自行观察并调用会话结算，新增三项均通过：电脑队伍获胜、本地失败界面存在且可处理、Director/电脑经营/军队控制器停止处理。测试没有直接调用结算。这首次把原经营远征与后续结算在同一自然运行中连接验证。
- 功能通过仍伴随 128 次空 material 错误（Dummy Renderer 的 instance shader 参数查询路径），两类攻击动画警告各 12 次；本次无此前错误 RID 初始化或 ObjectDB 泄漏报告，但不能推导所有渲染生命周期均正确。
- 仅完成一场、另一方保持空闲、战略 AI 使用开发期全图敌情；运行启动时尚未包含后来增加的经验入账代码，且击杀经验分配仍未接入。连续三局、英雄自然成长/复活、物品/科技全剧本、对抗活跃玩家和 M6 仍待验收。

## 2026-09-13：火球释放的重复材质覆盖

- 将战斗错误缩小为独立加载、准备表现、释放真实大法师火球模型，稳定出现一次 `material_get_instance_shader_parameters` 空材质错误；步枪命中特效未出现。日志 `tmp/missile-material-diag.log`；多等待两帧或先从场景树移除仍复现，因此不是简单等待渲染一帧即可解决。
- 实际材质清单显示烘焙火球 Geoset_0 同时持有整体和表面材质覆盖。与 [Godot #85817](https://github.com/godotengine/godot/issues/85817) 所述双重覆盖释放问题吻合。首次仅处理 FxBillboard 节点名称未覆盖该烘焙节点，实验无效并已撤回。
- `MapModelCache.prepare_fx_model` 现对特效中已有整体材质覆盖的网格清除被遮蔽的表面覆盖，保留实际生效材质；不依赖节点名，不改没有整体覆盖的网格。诊断日志 `tmp/missile-material-clean.log` 未再出现错误。
- 新增真实资源生命周期回归，火球与步枪特效各连续创建/准备/立即释放三次，`selftest_missile_material_lifetime: PASS (18 checks)`；日志 `tmp/selftest_missile_material_lifetime-single-material.log` 无空材质错误。覆盖实际材质仍存在、覆盖不重复、节点已释放；不代表完整战斗或画面视觉回归通过。
- 更广 `selftest_wc3_fx_presenter` 回归日志发现斧头特效缺失 `Abilities/Weapons/Axe/TrollPink.png`，运行器因 ERROR 判失败，不能声称该回归干净通过；详见 `tmp/selftest_wc3_fx_presenter-single-material.log`。该缺失资源与本次火球释放路径分开跟踪。自然长战斗中的全部 128 次错误尚需整场复验后才能确认消除。

## 2026-09-13：补齐斧头特效原始贴图依赖

- 确认 AxeMissile.gltf 引用 `./TrollPink.png`，本地转换目录和暂存源目录都缺失，非文件名大小写或相对路径错误。按项目 bootstrap 配置从本地 Warcraft3 安装资源包精确提取 `abilities/Weapons/Axe/TrollPink.blp`，原资源存在；仅提取一项、转换一项，无错误，没有替换图或修改模型引用。
- 使用现有工具的精确 `--include`；解包清单保存为 `tmp/axe-texture-extract.json`。转换使用 `--textures-only --skip-clean --skip-scn --skip-passthrough`，避免无关模型重烘焙或资产清理。产物仍遵循本地转换资源不纳入源码分发的约定。
- `selftest_wc3_fx_presenter: PASS`，火球/箭矢/斧头/地面光环分类全部通过；火球和步枪材质生命周期仍为 `PASS (18 checks)`。日志 `tmp/selftest_wc3_fx_presenter-texture-fixed.log`、`tmp/selftest_missile_material_lifetime-texture-fixed.log`，均无 ERROR/WARNING。
- 表现器测试增加 glTF 外链 images/buffers 文件存在检查，缺少依赖直接 `_fail`，防止引擎报告缺图但脚本仍输出 PASS。补强后 `tmp/fx-dependencies-final.log` 仍为 PASS 且无错误。完整战斗渲染复验、英雄击杀经验分配及完整 M1 仍待推进。

## 2026-09-13：死亡编排防重复与火球修复长测

- 火球材质修复后的自然对局长测已启动，日志 `tmp/natural-material-fixed.log`，持续使用同一进程观察；约 270 秒时正常建成兵营、祭坛、农场并生产两名步兵，尚未完成战斗或十一项验收。
- 等待期间复现 DeathService 对同一尸体重复执行清理并广播死亡事件：修复前 `selftest_death_once: FAIL (3 checks)`，日志 `tmp/death-once-before.log`。该行为会影响英雄阵亡登记，也会成为后续经验发奖重复风险。
- 在单位上于回调前记录死亡已处理，跨服务实例和回调重入均拒绝重复；不能用 HP=0 作为拒绝依据，因为伤害入口先扣至零。回调若已释放节点则安全返回。当前复活创建新节点；未来同节点复生需显式开启新生命期并重置标记。
- 扩展后的 `selftest_death_once: PASS (5 checks)`，覆盖首次零生命结算、重复/跨服务调用、离场、重入、回调释放节点；真实 `selftest_match_end_game: PASS (12 checks)`。日志 `tmp/death-guard-selftest_death_once.log`、`tmp/death-guard-selftest_match_end_game.log`，均无错误或警告。
- 正在运行的自然长测加载的是死亡修复前代码，不能作为本项新改动的集成验证；击杀经验分配仍待实现，长期目标保持未完成。

## 2026-09-13：火球材质修复通过完整自然对局

- 原长测最终 `selftest_opponent_campaign: PASS (11 checks)`、退出码 0，总进程耗时 656412 ms，日志 `tmp/natural-material-fixed.log` 与 `tmp/natural-material-fixed-output.log`。正常经营、付费训练、野怪战、基地进攻、同场结算及控制器冻结全部通过，没有重启或缩短原断言。
- 首次主城伤害来自自产步兵，现实时间 433.697 秒；致命伤害来自大法师，现实时间 635.229 秒、累计处理时间 381.449579 秒，主城为零生命，累计有效伤害 1507.230769（含溢出）。
- 整份输出无 ERROR、空材质错误或泄漏报告；与上一轮同类长测的 128 次空材质错误相比，本轮未再复现，支持重复材质覆盖修复在完整火球战斗中的效果。两类攻击动画缺失警告各 15 次仍在，视觉与稳定性不能宣称全部通过。
- 这是修复后的一次独立自然对局，不是连续重开三局；另一方仍空闲，英雄击杀经验分配、完整成长/复活/科技/物品流程未涵盖。启动后的死亡防重复改动也不由本轮验证，已有独立专项与短集成记录。

## 2026-09-13：攻击动画警告增加定位信息

- 检查本地步兵、大法师、农民、食人魔 glTF 动画列表，均存在 Attack 或编号攻击动作；尚不能据此判定具体运行时模型正常，也未确认警告来源。
- AnimPlayback 的失败警告补充宿主节点路径、场景路径和实际 AnimationPlayer 动画列表，保留原失败返回与警告，不以静默方式掩盖缺失动作。
- 使用此诊断启动独立自然对局，日志 `tmp/natural-animation-diagnostic.log`。已确认初始化完成，约 60 秒时正常采集及训练农民，无 ERROR；进程仍在运行，尚未出现目标攻击警告，未获得最终十一项结果。此记录不计作完成对局或动画修复验收。

## 2026-09-13：确认并修正命中特效截获单位动画

- 同一诊断对局已复现：`nogr_88/CombatImpactFx/Abilities_Weapons_FireBallMissile_FireBallMissile_mdx` 收到 Attack 请求，而实际动画列表仅 Birth/Death/Stand。原始 glTF 单位本身没有 Wc3ModelScene 门面，全单位递归查找却找到了后来挂入的火球门面，并缓存为自身模型。
- Unit 将门面和未绑定播放器的查找限定在 `Model` 分支，不再遍历单位的命中/技能特效兄弟分支。保留失败警告及诊断信息。
- 回归先复现同类警告及身体攻击未播放，`tmp/unit-fx-animation-before.log` 为 FAIL；修复后 `selftest_unit_fx_animation: PASS (6 checks)`，涵盖普通模型挂特效、特效播放不被改动、未绑定播放器及烘焙模型攻击。证据 `tmp/unit-fx-animation-final.log` 无 ERROR/WARNING；原步兵死亡/尸体三项回归仍 PASS，见 `tmp/animation-revive-death-anim.log`。
- 诊断长对局仍使用修复前代码，已进攻主城；最终结果与修复后独立长对局均待验证，不能据此宣布整场动画警告清零。

## 2026-09-13：祭坛复活费用、时间与魔法对齐经典规则

- 根据 [官方英雄规则](https://classic.battle.net/war3/basics/heroes.shtml)，复活按英雄原始训练价格及时间计算，祭坛金币上限550、时间上限110秒、零木材；复活满生命、100魔法。移除固定 `250 + 等级×50` 金与 `120 + (等级−1)×30` 秒公式，命令卡和下单入口都传入英雄类型并使用同一报价。
- 本地大法师数据为425金/55秒：一级170金/35.75秒，六级382金/110秒，十级550金/110秒。整数金币向下取整，等级限制1–10；首英雄免费不影响复活基价。地图自定义游戏常量覆盖尚未接入，本项不是所有历史补丁规则兼容证明。
- 真实英雄回归先按100魔法断言得到 FAIL，证据 `tmp/revive-mana-before.log`；修复后 `selftest_hero_life_game: PASS (17 checks)`，包括真实复活状态恢复、重复初始化不回满魔法、真实祭坛六级英雄下单扣382金及队列110秒。证据 `tmp/animation-revive-revive-game.log` 无 ERROR/WARNING。
- 十级报价/时间、边界及祭坛命令卡显示 `selftest_hero_revive_rules: PASS (25 checks)`，证据 `tmp/animation-revive-revive-rules.log`。真实祭坛由夹具创建并补充费用，未把下单断言冒充自然经营或完整等待复活；完整 M1 与击杀经验分配仍未完成。

## 2026-09-13：诊断对局结束与复活命令卡收敛

- 原诊断对局已正常结束，`tmp/natural-animation-diagnostic.log` 为 `PASS (11 checks)`，退出码0。603.042秒由自产步兵摧毁主城，累计伤害1506.38461538462（含溢出）。警告明确涉及 `nogr_88` 与 `nomg_6` 的火球命中特效，支持上一条根因分析；该进程加载修复前代码，不计动画修复后的整场通过。
- 已启动独立修复后自然对局，日志 `tmp/natural-animation-fixed.log`；进程存活，初始化与正常经营已确认，尚无最终结果。此次运行包含动画分支查找与祭坛复活数值修复，但不验证启动后本条命令卡修改。
- 命令卡原先对所有建筑生成复活按钮；测试确认农场会实际保留该无效按钮，主城/兵营同槽后续按钮会覆盖它。将当前支持的人族祭坛判断集中到 `HeroDeathRegistry.can_revive_at`，命令卡与实际下单共同使用。其他种族祭坛尚未接入，不以此项冒充四族完成。
- 回归 `tmp/revive-card-before.log` 先 FAIL；修复后 `tmp/revive-card-fixed.log` 为 `PASS (28 checks)` 且无 ERROR/WARNING，包含祭坛报价与主城/兵营/农场不出现无效复活动作。

## 2026-09-13：经验接入前发现基准及补丁提取缺口

- 检查死亡事件与英雄经验入口，目前仍未连接击杀经验分配；先提取并检查游戏常量，发现本地数据与官方网页在野怪经验衰减及复活上限方面不一致。前述复活测试仅证明实现符合网页规则，不证明本地1.20.4客户端一致。
- 进一步发现补丁清单只有两项，但按已知路径能读取 Units/MiscGame.txt 与 Units/UnitBalance.slk；当前提取器仅枚举清单，会漏掉这种补丁覆盖。已记录文件大小、SHA256、版本元数据、规则差异及修复验证要求，见 [规则基准待核项](CLASSIC_RULES_BASELINE.md)。尚未改变提取器或重转全部资源。
- 动画修复长对局 `tmp/natural-animation-fixed.log` 的原进程仍存活，约240秒时正常产出步兵，无最终结果；本轮未重复启动它。

## 2026-09-13：修正补丁清单遗漏导致的旧表残留

- 提取器累计已知路径（各包清单、历史manifest与明确include），后续包对未列出的路径使用 StormLib 存在性查询。按原包顺序覆盖，候选路径大小写去重；include/exclude继续生效。不存在的探测不算读取错误，损坏文件仍失败。
- 新增五组提取流程回归：未列出补丁覆盖及重复运行、完全未列出路径的精确include、排除条件、大小写变体、已存在但损坏的补丁。`node tools/mpq-extract/src/extract.test.mjs` 5/5通过；最后一组故意触发读取错误以验证报告，不是未处理的测试失败。首次 `node --test` 因本地进程隔离权限失败，改为直接运行同一测试文件后通过，没有删减断言。
- 实际包独立验证：仅提取 Units/MiscGame.txt 与 Units/UnitBalance.slk 至 `tmp/patch-probe-extracted`，零错误，`tmp/patch-probe-manifest.json` 的两项来源均为 War3Patch.mpq，大小与哈希符合先前直接读取证据。现有运行时资产尚未换表；数据差异评估与对应玩法回归待继续。
- 原动画修复长测仍存活，约480秒时军队继续进攻，尚未结束；已读日志未出现 ERROR/WARNING。不能将中途无警告写成整场验收完成。

## 2026-09-13：动画修复整场通过与补丁换表影响确认

- 原长测已结束：`tmp/natural-animation-fixed.log`、`tmp/natural-animation-fixed-output.log` 为 `PASS (11 checks)`，退出码0，整份输出没有 ERROR/WARNING。首次主城伤害由大法师造成于500.623秒，577.105秒由大法师致命攻击结束，累计伤害1504.15384615385（含溢出）。仍是一次独立自然对局，未覆盖连续三局或完整英雄成长/科技/物品流程。
- 新增可重复运行的 SLK/JSON 主键逐字段比较工具及三组回归，全部通过。实际报告 `tmp/patch-unitbalance-comparison.json`：812→836行，新增24、删除0，380个已有单位存在旧字段值变化；所有已有行还增加了字段，不把新增列算成812个单位数值全变。
- 确认补丁涉及火枪手、骑士、飞行器生命及建筑/中立单位价格，且要塞/城堡表价需要检查总价值与升级增量语义。详见 [规则基准待核项](CLASSIC_RULES_BASELINE.md)。目前保留原运行时表，关联表完整性和迁移验证待继续。

## 2026-09-13：成组迁移补丁单位关联数据

- 修复后的提取器准备61份单位SLK/Func/Strings/Misc文件，来源 `tmp/patch-units-manifest.json`；15份SLK导出无错误。首次导出参数误用另一工具的相对路径约定，写入被权限限制拒绝；改为工作区内路径后成功，没有提升权限写入外部目录。
- 836个单位的单位数据、技能分配、界面、武器关联行齐全，全部技能引用存在，证据 `tmp/patch-unit-references.json`。四个无主键技能占位行与现有定义库跳过空主键行为一致，单独记录；有效技能799项，新增36、已有192项值变化。
- 将15份JSON及46份文本共同迁入运行目录，更新标准staging源61份；两套原文件备份在 `tmp/before-patch-units-runtime`、`tmp/before-patch-units-staging`。本地来源清单 `assets/.staging/patch-units-manifest.json` 保留逐文件补丁来源及哈希，未提交游戏资源到源码。
- `selftest_patch_unit_data: PASS (24 checks)`；真实英雄17、复活规则28、战斗属性14、真实结算12项全部通过。日志 `tmp/patch-data-loaded.log`、`tmp/patch-data-hero.log`、`tmp/patch-data-revive.log`、`tmp/patch-data-combat.log`、`tmp/patch-data-match.log`，无 ERROR/WARNING。首次读取专项脚本直接引用autoload导致编译失败，改为读取已初始化节点后通过。
- 上一场自然长测发生在换表前，不当作新数据的整场验证；新补丁单位模型与技能行为、完整英雄经验、科技升级及规则版本统一仍待推进。

## 2026-09-13：复活计算使用同源游戏常量

- 新增MiscGame常量读取入口，限定Misc节并处理BOM、注释；无效或缺失数值会报告错误。复活计算读取导入数据中的基数、等级系数、倍率及绝对上限，替代先前来自网页的硬编码550金/110秒上限。
- 当前补丁为700金/150秒上限，但仍受原始训练时间两倍限制：十级大法师552金/110秒。该变化是对本地来源统一的修正，不声称适用于所有经典补丁；地图自定义常量与其他经验规则仍待接入。
- 常量专项 `PASS (7 checks)`、复活规则 `PASS (28 checks)`，日志 `tmp/imported-selftest_melee_constants.log`、`tmp/imported-selftest_hero_revive_rules.log`；真实英雄与祭坛回归 `PASS (17 checks)`，日志 `tmp/imported-constants-hero-game.log`，全部无 ERROR/WARNING。

## 2026-09-13：接通击杀经验与自然升级验收

- Director死亡事件接入经验分配。普通单位/英雄奖励表及递推、1200范围、全局回退、满级英雄分摊、野怪衰减、召唤物倍率与建筑击杀开关读取当前MiscGame常量。近处英雄优先，同owner英雄均分；友军击杀与无攻击建筑不发奖，死亡英雄不参与。独立死亡奖励标记与DeathService防重入共同防止重复发奖。
- `selftest_hero_death_xp: PASS (11 checks)`，覆盖部队清野20经验推动190→210升级、重复死亡/分配、附近独享、无近处英雄全局均分、五级野怪限制、友军/建筑禁奖和召唤物系数；`tmp/death-xp-final.log` 无ERROR/WARNING。
- 真实英雄集成扩展至 `PASS (19 checks)`，通过实际伤害→死亡→经验入账证明敌方步兵奖励40经验，重复死亡不增加；`tmp/death-xp-game-final.log` 无ERROR/WARNING。专项首次坐标辅助调用参数错误已修正，没有放宽断言。
- 当前敌我与现有CombatQuery一致按owner区分；联盟共享、单英雄科技奖励、升级声光提示及地图自定义经验规则尚未接入，不能称为完整经典英雄成长系统。
- 自然对局新增实际经验和至少二级两项要求（原11项保留，共13项），已启动 `tmp/natural-patch-xp.log` 长测；该进程使用新补丁表与经验接入。尚无最终结果，不把专项升级夹具冒充自然经营验收。

## 2026-09-13：升级即时刷新选中英雄面板

- 确认命令卡冷却轮询只在已有技能冷却时刷新，静止且无冷却英雄升级后可用技能点仍停留旧值。真实地图集成新增“190经验选中英雄实际击杀→二级→不重新选中显示2技能点”，修复前 `tmp/xp-ui-before.log` 的最后断言失败。
- 死亡经验回调读取实际奖励结果，对当前主选英雄刷新详情；跨级时主动刷新命令卡。避免只在重新选择或其他操作后才看见可用技能点。
- 修复后 `tmp/xp-ui-fixed.log` 显示 `PASS (23 checks)`，但卸载场景时另有一次 `material_get_instance_shader_parameters` 空材质引擎错误，严格运行器因此退出1。功能断言通过不能宣称整项回归干净通过；新增场景中的选择/额外模型及卸载路径仍待定位。
- 原自然经验长测进程仍存活，约90秒正常建成兵营；加载的是本条界面修复前代码，最终13项结果仍待观察。

## 2026-09-13：自然升级对局通过与卸载顺序定位

- `tmp/natural-patch-xp.log`、`tmp/natural-patch-xp-output.log` 最终 `PASS (13 checks)`、退出码0，无 ERROR/WARNING。电脑通过正常经营与实际战斗获得328经验、升到二级；647.38秒由大法师摧毁主城，累计伤害1507.15384615385（含溢出）。包含迁移后的补丁关联表和击杀经验分配，不包含启动后选中英雄界面刷新改动。
- 该自然对局没有夹具补经验或直接设置英雄等级；仍未覆盖完整复活/物品/编队交互或连续三局，不代表EI MVP完成。
- 升级界面专项通过23项功能断言后仍复现一次空材质错误。诊断扫描未发现整体与表面双重覆盖，阶段日志确认错误发生于整个游戏卸载时，不能照搬先前火球覆盖修复。
- 诊断模式先停止游戏处理、释放HUD、等待两帧，再释放其余游戏，`tmp/xp-ui-material-hud-free.log` 为23项PASS且无错误；原顺序 `tmp/xp-ui-material-phases.log` 仍有错误。该实验支持HUD/战场共享资源卸载顺序是下一步排查方向，尚未改正式生命周期或认定根因已完全证明。
- 文档提交25914b0的后台整理已完成，提交进程退出0；原有其他暂存项保持。功能里程碑仍有上述引擎错误，尚未作完成提交。

## 2026-09-13：头像生命周期修复并提交

- 原直接卸载路径中，已排队的头像任务在父场景queue_free后仍能创建/初始化模型。组件现检查自身及祖先删除状态，离树作废任务；无需改变测试的正常卸载顺序。
- 最小真实头像测试进一步复现TeamGlowBillboard的PrimitiveMesh空基础材质配表面覆盖，在正常加载后卸载也报空材质。将覆盖材质转入实例独有网格的基础材质并移除覆盖，缓存网格保持不变。
- `tmp/portrait-milestone-portrait.log` 六项PASS，`tmp/portrait-milestone-hero.log` 真实英雄升级集成23项PASS，两份日志均无ERROR/WARNING。修复前最小头像四项功能PASS但引擎报错见 `tmp/portrait-shutdown-scene.log`；验证未通过隐藏错误或跳过正常头像加载实现。
- 小里程碑提交 `3df2f40`：头像组件、六项专项与生命周期说明四个文件。仅提交该修复，其他已暂存子模块项保持；完整EI MVP仍未完成，画面视觉验收和其他系统工作继续。
