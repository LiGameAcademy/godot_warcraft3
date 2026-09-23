# D2–D5 审查修复记录

对应 [审查报告](REVIEW_2026_09_23_D2_D5.md)。本轮修复运行边界，不把接口骨架视为已完成的 Mod SDK 或双产品发布。

## 已实现

- R1：EntityRegistry 使用 WeakRef，释放后查询先解引用再校验；注销、同 ID 替换同时清理正反索引。树内实体离树立即移除，树外实体在查询/计数时清理。
- R2：普通 rebind 不清空实体表。UnitsModule 绑定单位宿主，初始化扫描已有实体，并监听新增节点和离树，覆盖地图、训练、召唤等通过该宿主生成的单位。零/重复 creationNumber 分配对局内备用身份，不修改地图数据；训练路径不会重复注册。
- R3：同步工具显式生成一个过渡 `rts_runtime` 包，保留完整源码目录并转换内部 res:// 路径；包括受版本控制的子模块源码。配置必要的 Autoload。两个 boot 实际实例化 GameSession、创建 PlayerStock、执行未开局胜负查询。Test-Apps.ps1 同时检查退出码、脚本错误与完成标记。
- R4：叠加包摘要由包 ID、排序后的相对路径和文件 SHA-256 构成；修改原文件使摘要变化，相同文件搬到其他根路径保持摘要。挂载前完成目录读取/哈希校验，失败不改当前 overlay/快照。
- R5：快照字段 freeze 后不接受赋值，数组返回副本；首次开始对局封闭 AssetProvider，ContentRegistry 和直接 overlay 修改均不能绕过。当前支持启动前选包，运行过对局后切换 Mod 要重启应用。
- R6：请求玩家必须匹配 Router 绑定玩家；暂未实现的 queue_append 明确返回 APPEND_UNSUPPORTED；拒绝发生在转发和改订单之前。非有限坐标也被拒绝。

## 有意保留的范围限制

`base` 仍是固定内置内容标识，当前摘要是叠加包内容摘要，不是整个基础游戏资产的发布锁文件；正式发布须加入基础包构建清单。快照冻结的是已选包配置与元数据，不是把所有松散文件复制为不可变文件系统；运行中外部手工修改资源不受支持。

采用“开始对局后必须重启进程换包”，是因为现有全局 Catalog、模型引用和失败缓存尚未全部版本化；不宣称清 DefStore 就能安全热切换。启动前可切换候选包；不要在此阶段实例化持有长期资源引用的完整对局。

双应用仍是运行库验证入口。过渡包为保证依赖完整，暂时包含游戏/编辑器共同源码与第三方依赖；尚未实现最终产品裁剪，也未包含本地忽略的大型转换资产。真实编辑器/游戏启动、内容分发和独立导出仍需后续验收。原根工程继续作为开发入口。

BehaviorRegistry 的真实技能注册接入、完整 manifest/依赖校验及全面架构依赖检查仍为后续任务。EntityId 当前仍为对局内身份，跨存档/跨对局请求必须另带会话身份，不能复用旧 ID。

## 验证入口

- tests/unit/selftest_entity_behavior.tscn：释放、替换、离树、零 creationNumber、绑定保留。
- tests/unit/selftest_command_request.tscn：错玩家、追加拒绝、NaN、订单不变。
- tests/unit/selftest_content_snapshot.tscn：冻结、数组副本、原地修改、搬迁、失败原子性、运行封闭。
- tests/integration/selftest_module_bindings_game.tscn：初始地图实体登记、重绑定后身份保留。
- tests/integration/selftest_match_end_game.tscn -- --restart：真实对局重开。
- `tools/workspace/Test-Apps.ps1 -Godot <Godot executable>`：同步后分别导入和运行双应用；错误日志不可仅凭进程返回 0 忽略。

本轮未进行画质或长期性能改善验收，不降低 AI 更新频率，不修改 HUD 布局。

实际结果（Godot 4.7.2）：实体 16、请求 11、内容 14、物品 57、治疗 20、命令输入 8、真实地图重绑定 30、对局重开 23、架构门禁 11，共 9 组 190 项通过。根工程导入无脚本解析错误；双应用同步、导入、运行库冒烟通过。日志位于 `tmp/fix-*.log` 和 `tmp/app-validation/`。

环境仍有系统证书/用户设置写入提示；双应用未携带外部转换数据，会提示基础定义表缺失。上述冒烟只验证代码依赖与运行接口，不把缺少内容的壳当作可发布游戏。
