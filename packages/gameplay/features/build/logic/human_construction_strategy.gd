class_name HumanConstructionStrategy
extends IConstructionStrategy

## F2-B Human ConstructionStrategy。
## 工人可见；支持 join_via_repair；进度按 active_builders 加速。
## 来源：docs/design/game/BUILD_SYSTEM.md §4.4

## join_via_repair：返 true（人族多工）— 实际限制由 BuildSite.max_builders 决定
func try_join(_site: Node, _builder: Node3D) -> bool:
	return true

## on_order_accepted：人族立即派 primary builder path 去工地
## on_builder_arrived：人 visible（不隐藏）；BuildSite.add_builder
## on_cancel：释放 active_builders（visible + IDLE）
## on_complete：释放 active_builders
## tick：BuildSite 自己推进进度（N 工人 → N× 基准速率；0 人暂停）
