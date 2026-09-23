class_name IConstructionStrategy
extends RefCounted

## F2-A 契约：IConstructionStrategy（逻辑插件）。
## 四族差异收敛到 Strategy：人/兽/灵/亡 行为插件。
## 来源：docs/design/game/BUILD_SYSTEM.md §4.4
##
## 用法：
##   var strategy: IConstructionStrategy = HumanConstructionStrategy.new()
##   strategy.on_order_accepted(site, builder)
##   strategy.on_builder_arrived(site, builder)
##   if strategy.try_join(site, builder):
##       print("joined")
##   strategy.tick(site, dt)
##   strategy.on_cancel(site)
##   strategy.on_complete(site)

## 扣费后立即：人族创建半成品建筑；亡灵开始召唤
func on_order_accepted(_site: Node, _builder: Node3D) -> void:
	pass

## 工人到达工地：人族开始修；兽灵隐藏并占用
func on_builder_arrived(_site: Node, _builder: Node3D) -> void:
	pass

## 第二人 try join：人族 Repair 加入（true）；其它 false
func try_join(_site: Node, _builder: Node3D) -> bool:
	return false

## tick 推进进度（按 profile.progress_model 调速）
func tick(_site: Node, _delta: float) -> void:
	pass

## 取消：退款 + 释放工人 + 回滚 pathing
func on_cancel(_site: Node) -> void:
	pass

## 完工：刷建筑 + 人口 + Strategy.on_complete（消耗/释放工人）
func on_complete(_site: Node) -> void:
	pass
