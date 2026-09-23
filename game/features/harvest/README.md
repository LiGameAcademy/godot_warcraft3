# 采集模块

HarvestModule 管理采集组件、TreeRegistry、金矿枯竭及倒塌回收。GameSession / PlayerStock 仍是资源账本；导航直接使用 NavigationModule。负重、交付、状态变化和矿点枯竭通过信号通知界面，不依赖 GameDirector。

对局装配时 configure，地图就绪后 setup_trees / wire_mines。shutdown 断开组件和矿点信号，终止采集，清理组件依赖和树木注册表；过期倒塌回调通过代次检查失效。组件跟踪使用弱引用，退出场景时移除。

回归：selftest_harvest_module、selftest_gold_mine_depleted、selftest_economy_supply，以及 selftest_match_end_game --restart。
