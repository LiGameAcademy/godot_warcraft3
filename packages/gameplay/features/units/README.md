# 单位功能

UnitsModule 是单位创建、AI/英雄装配和形态变化的公开入口。内部 UnitFormService 处理民兵转换和建筑升级事务；UnitModelPresenter 负责模型实例替换、动画/粒子/交互组件绑定。

形态转换保留实体节点、creationNumber 和生命比例，停止旧订单并刷新移动/战斗能力；民兵寻找本单位 owner 的主城。建筑升级沿用合法的纵向升级链及 owner 资源账本。完成后发出 form_changed，HUD 与血条由外部订阅，不由事务代码直接操作。

configure 绑定对局依赖；shutdown 停止并解绑已装配的民兵控制器，释放表现层对地图的引用。保留原对局根生命周期，不引入 Autoload。

测试：selftest_units_module、selftest_militia.tscn、selftest_production_module、selftest_unit_forms_game（双方民兵转换/超时收回/建筑升级）。
