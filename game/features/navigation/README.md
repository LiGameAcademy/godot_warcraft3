# 对局导航

`NavigationModule` 是随对局创建的 Node，不注册为 Autoload。它拥有 PathQuery、UnitCrowdQuery、PathCellReservation 和对地图寻路/高度数据的引用。地图数据本身仍由 MapLoader 提供。

## 生命周期与接口

- `initialize(map_root, ensure_visual)`：地图就绪后调用；重新调用先释放旧绑定。单位视觉装配通过一个明确的 Callable 注入，暂沿用现有单位装配入口。
- `ensure_navigator(unit)`：复用或创建单位组件，绑定共享查询和预约、应用移动参数，并只订阅一次移动状态信号。
- `apply_move_stats(unit, nav)`：单位形态改变后刷新移动参数。
- `bind_pathing(value)` / `refresh_dynamic_pathing()`：接入开局、建筑变更和召唤导致的寻路数据刷新。
- `locomotion_changed`：通知界面刷新，不直接依赖 HUD 或 Director。
- `shutdown()`：幂等；停止仍存活的组件，释放预约、清除依赖和信号。单位退出场景时移除弱引用跟踪，避免持续积累。

查询算法、预约冲突规则、移动参数及画面效果保持原状。共享的转向、阵型等基础算法暂留在原公共目录，本轮迁移四个直接归导航所有的脚本并保留 UID。

## 验证

Godot 4.7.2，无渲染运行：

```powershell
godot --headless --path . res://tests/unit/selftest_navigation_module.tscn
godot --headless --path . res://tests/unit/selftest_match_round2.tscn
godot --headless --path . --script res://tests/unit/selftest_group_move.gd
godot --headless --path . --script res://tests/unit/selftest_pathfinding_integration.gd
godot --headless --path . res://tests/integration/selftest_match_end_game.tscn -- --restart
```

模块测试覆盖组件复用、服务身份、重复订阅、重新绑定、旧预约释放、单位移除和幂等销毁；真实地图重开测试确认旧导航模块被释放且新对局使用新的预约服务。
