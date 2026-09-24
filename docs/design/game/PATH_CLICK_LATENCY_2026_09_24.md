# 点击移动寻路耗时修复（2026-09-24）

## 原因与修改

点击移动在 CommandRouter 中逐个同步执行 UnitNavigator.go_to_wc3。脚本 A* 的节点扩展和净空检查昂贵；原路径拉直对每个后续格点重新扫描从锚点开始的整条线段，长路径产生近似平方级采样。导航失败后，即使脱困起点没变也再次搜索。

- 默认搜索改用 Godot AStarGrid2D，Octile 代价、禁止穿墙角；静态与动态阻挡按相同 Chebyshev 净空膨胀。缓存持有数组独立快照，支持原地修改后的失效；每次查询临时应用他人预约并完整恢复。
- 常用净空 0/1 在地图装配及动态路径刷新时预热；显式修改 max_nodes 仍走原脚本限额后端。默认原生后端完整搜索，不再把展开 48000 格误当作不可达。保留脚本后端用于对照。
- 路径拉直改为指数探测及区间细化；仅接受通过完整线段可走性检查的候选。净空检查仅在单次同步查询内缓存，不跨调用保留位置/预约结果。
- 起点不变不重试失败搜索；热点统计增加 move_command、path_search、path_smoothing。

路径代价和可达性保持验证，等价最短路径的选择及平滑拐点允许不同。没有修改单位速度、AI 更新频率或画质。原生网格 API 依据 [Godot 文档](https://docs.godotengine.org/en/stable/classes/class_astargrid2d.html)。

## 测量

本地 Windows，Godot 4.6.3 console，headless。没有隔离后台应用；这是 CPU 命令耗时，不是渲染帧率、鼠标拾取或完整输入到显示延迟。

256×256 合成长墙：起点 (100,40)、终点 (150,40)，墙延伸至 y=219。两种净空各执行三次，最后封闭通道验证不可达。初始版本日志 `tmp/path-click-before.log`，最终日志 `tmp/click-selftest_path_click_latency.log`。

| 场景 | 修改前单次 ms | 最终单次 ms |
|---|---:|---:|
| 绕墙，净空 0（三次） | 1604 / 1556 / 1896 | 32.7 / 15.5 / 17.2 |
| 绕墙，净空 1（三次） | 5705 / 4626 / 5130 | 40.0 / 27.8 / 26.1 |
| 封闭通道不可达 | 3373 | 18.2 |

真实 EI 固定出生点，禁用对手扩张，加载完成后暂停世界，以实际 CommandRouter 对本地可控单位下单，随后停止；每种规模测试四个固定相对目标。最终 `tmp/click-selftest_move_click_game.log`：单单位 0.953 / 14.215 / 4.344 / 2.288 ms；七单位 7.599 / 62.395 / 30.700 / 15.479 ms。包含落点不合法和合法但不可达的失败结果。没有同条件真实地图修改前记录，不据此计算真实点击加速比例。

一次候选跳点搜索在合成长墙更快，但 EI 不可达目标单兵达到约 470 ms、七单位约 695 ms，最终关闭该选项。早期全地图 88 个实体的批量探测包含中立/敌方，不能作为正常玩家编队验收；正式夹具已筛选本地可控单位。

## 验证与边界

- 新增 selftest_path_click_latency：80 个固定种子随机地图，比对脚本/原生可达性及最短路径代价；逐格检查静态/动态阻挡、净空、预约归属、对角墙角和拉直线段。另验证失败不重复搜索，以及 1024 格可见路径仅需少量射线探测。
- 新增真实场景 selftest_move_click_game：实际移动命令返回、失败数与停止状态；正常卸载，最终无 ERROR/WARNING。
- 现有 selftest_match_round2 1098 项、selftest_navigation_module 14 项、group_move、pathfinding_integration 通过。git diff --check 通过。
- Lost Temple 的 selftest_path_grid 因缺少应用路径下的 terrain-heightfield.json 失败，未算作通过。首次真实地图测试误用 -s 启动带 Autoload 依赖的 SceneTree 脚本，出现编译错误；已改为常规 Node 场景入口，最终运行通过。

七单位最差约 62 ms，仍超过 60 FPS 的单帧预算；当前批量命令仍同步累加，没有宣称完全消除卡顿。后续如需大量单位严格控制输入帧，应引入带取消/替换语义的寻路调度，并单独验收旧结果失效、停止、死亡、重开及动态障碍。此次未做 GUI 鼠标操作或长期活动对战验收。

复现：

```powershell
node tools/godot-mcp/scripts/run-selftest.mjs path_click_latency
python tools/workspace/sync_packages.py --app game --test integration/selftest_move_click_game.tscn
& '<Godot console executable>' --headless --path apps/game res://tests/integration/selftest_move_click_game.tscn
```
