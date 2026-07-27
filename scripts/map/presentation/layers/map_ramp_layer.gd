class_name MapRampLayer
extends Node3D

## 斜坡表现层：消费 Collect placements，编排地形/悬崖 API，挂 CliffTrans。
## 当前阶段：不挖洞、不藏崖、不挂模——避免在 Present 完成前污染地形/悬崖。
##
## 目标流水线（Present 实装时）：
##   1. ctx.ensure_ramp_topology()
##   2. dig = Wc3RampCollect.plan_dig_mask(hf, ramp) 中「相对直崖的增量」
##      terrain.apply_dig_mask(romp_only) / terrain.undig_tiles(entrances)
##   3. cliffs.hide_at_tiles(entrances + clifftrans tiles)
##   4. 挂 CliffTrans MultiMesh；入口低角 +0.5

@export var terrain: MapTerrainLayer
@export var cliffs: MapCliffLayer

var last_placement_count: int = 0


func build(ctx: MapBuildContext) -> void:
	_clear_children()
	last_placement_count = 0
	if ctx == null:
		return
	# Collect 可缓存供调试/后续挂模；本阶段不对地形/悬崖施加任何副作用。
	ctx.ensure_ramp_topology()
	if ctx.ramp != null:
		last_placement_count = ctx.ramp.non_phantom_count()
	# Present 未启用：故意不调用 terrain.apply_dig_mask / undig_tiles / cliffs.hide_at_tiles


func _clear_children() -> void:
	for c in get_children():
		c.queue_free()
