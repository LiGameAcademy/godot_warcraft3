# 对局导航

`NavigationModule` 是随对局创建的 Node，不注册为 Autoload。它拥有 PathQuery、UnitCrowdQuery、PathCellReservation 和对地图寻路/高度数据的引用。地图数据本身仍由 MapLoader 提供。

## 生命周期与接口

- `initialize(map_root, ensure_visual)`：地图就绪后调用；重新调用先释放旧绑定。单位视觉装配通过一个明确的 Callable 注入，暂沿用现有单位装配入口。
- `ensure_navigator(unit)`：复用或创建单位组件，绑定共享查询和预约、应用移动参数，并只订阅一次移动状态信号。
- `apply_move_stats(unit, nav)`：单位形态改变后刷新移动参数。
- `bind_pathing(value)` / `refresh_dynamic_pathing()`：接入开局、建筑变更和召唤导致的寻路数据刷新。
- `locomotion_changed`：通知界面刷新，不直接依赖 HUD 或 Director。
- `shutdown()`：幂等；停止仍存活的组件，释放预约、清除依赖和信号。单位退出场景时移除弱引用跟踪，避免持续积累。

## 性能要点

- `PathQuery`：默认使用 Godot 原生 `AStarGrid2D`，八邻接 Octile 代价且禁止穿墙角；按净空缓存地图网格，静态/动态数组内容改变时失效。预约按查询玩家临时加入并在返回前恢复。常用净空 0/1 在地图初始化及动态路径刷新时预热。
- 脚本 A* 保留为差分对照及自定义 `max_nodes` 限额后端；默认原生搜索不再受脚本的 48000 展开上限限制。关闭跳点搜索，避免 EI 不可达目标退化。
- 路径拉直使用指数探测和区间细化，每个接受的线段仍经过完整采样；净空结果仅在单次同步查询内复用。等价代价路径的形状及拉直拐点可能变化。
- 脱困没有改变起点时不重复失败搜索。可选热点统计增加 `move_command`、`path_search`、`path_smoothing`，可分辨一次点击批量调用与单次搜索/后处理的开销。
- `UnitCrowdQuery`：同帧共享空间哈希；传送等大幅改坐标后须 `invalidate()`（群体传送已接）。
- 预约格仍每帧写入；`PathCellReservation` 在格集不变时也会重试被占格。

预约冲突规则与移动参数保持；大量单位仍逐个同步求路，不提供每帧固定预算保证。

## 验证

```powershell
godot --headless --path apps/game res://tests/unit/selftest_navigation_module.tscn
godot --headless --path apps/game res://tests/unit/selftest_match_round2.tscn
godot --headless --path apps/game --script res://tests/unit/selftest_group_move.gd
godot --headless --path apps/game --script res://tests/unit/selftest_pathfinding_integration.gd
godot --headless --path apps/game res://tests/integration/selftest_match_end_game.tscn -- --restart
```
