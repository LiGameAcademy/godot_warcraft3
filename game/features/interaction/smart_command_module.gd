class_name SmartCommandModule
extends Node

## 右键智能目标解析、交互闪选与状态文案。
## 下发命令仍经 CommandRouter；本模块不持有 GameDirector 类型。

const SMART_BUILDING_FOOT_PX := 40.0

var _unit_selector: Node
var _rts_camera: Node
var _tree_registry: TreeRegistry
var _ground_items: Node3D
var _ground_at_screen: Callable
var _is_gold_mine: Callable


func configure(deps: Dictionary) -> void:
	_unit_selector = deps.get("unit_selector") as Node
	_rts_camera = deps.get("rts_camera") as Node
	_tree_registry = deps.get("tree_registry") as TreeRegistry
	_ground_items = deps.get("ground_items") as Node3D
	_ground_at_screen = deps.get("ground_at_screen", Callable()) as Callable
	_is_gold_mine = deps.get("is_gold_mine", Callable()) as Callable


func shutdown() -> void:
	_unit_selector = null
	_rts_camera = null
	_tree_registry = null
	_ground_items = null
	_ground_at_screen = Callable()
	_is_gold_mine = Callable()


func _exit_tree() -> void:
	shutdown()


func resolve_smart_target(screen_pos: Vector2, selected: Array) -> SmartTarget:
	var ground_goal := screen_to_goal_wc3(screen_pos)
	if _ground_items != null and _rts_camera != null and _rts_camera.has_method("get_camera"):
		var cam: Camera3D = _rts_camera.call("get_camera") as Camera3D
		if cam != null:
			var item := GroundItemVisual.pick_at(_ground_items, cam, screen_pos)
			if item != null:
				var target := SmartTarget.new()
				target.kind = SmartTarget.Kind.ITEM
				target.node = item
				target.goal_wc3 = Wc3Coords.godot_to_wc3_xy(item.global_position)
				return target
	var best: SmartTarget = null
	var best_score := INF

	var picked: Node3D = null
	if _unit_selector != null and _unit_selector.has_method("pick_at"):
		picked = _unit_selector.call("pick_at", screen_pos) as Node3D

	if picked != null and _gold_mine(picked):
		var s := screen_score_node(picked, screen_pos)
		if s < best_score:
			best_score = s
			best = SmartTarget.gold_mine(picked, node_goal_wc3(picked, ground_goal))

	if _tree_registry != null:
		var cn := _tree_registry.pick_cn_at_screen(screen_pos)
		if cn >= 0:
			var tree_goal := _tree_registry.get_pos_wc3(cn)
			if tree_goal == Vector2.INF:
				tree_goal = ground_goal
			var s2 := screen_score_tree(cn, screen_pos)
			if s2 < best_score:
				best_score = s2
				best = SmartTarget.tree(cn, tree_goal)

	if (
		picked != null
		and is_own_dropoff_building(picked, selected)
		and selection_any_carrying(selected)
	):
		var foot_drop := screen_score_node(picked, screen_pos)
		# 须点得够近，避免主城大胶囊抢走「点附近地面移动」
		if foot_drop <= SMART_BUILDING_FOOT_PX:
			var s3 := foot_drop + 18.0
			if s3 < best_score:
				best_score = s3
				best = SmartTarget.dropoff(picked, node_goal_wc3(picked, ground_goal))

	# 未完工建筑 → 增派建造（也须脚底够近）
	if picked != null and UnitLife.is_under_construction(picked):
		var foot_site := screen_score_node(picked, screen_pos)
		if foot_site <= SMART_BUILDING_FOOT_PX:
			var s4 := foot_site - 8.0
			if s4 < best_score:
				best_score = s4
				best = SmartTarget.build_site(picked, node_goal_wc3(picked, ground_goal))

	# 敌对单位 → Attack（优先于纯地面，低于矿/树/交货/工地）；友军不走智能攻击
	if picked != null and CombatQuery.any_can_auto_attack(selected, picked):
		var s5 := screen_score_node(picked, screen_pos)
		if s5 < best_score:
			best_score = s5
			best = SmartTarget.enemy_unit(picked, node_goal_wc3(picked, ground_goal))

	if best != null:
		flash_smart_interact_target(best)
		return best
	if ground_goal == Vector2.INF:
		return null
	return SmartTarget.ground(ground_goal)


## 右键交互反馈：金矿 / 建筑 / 树木统一闪选中环（不改左键选中集合）。
func flash_smart_interact_target(target: SmartTarget) -> void:
	if target == null:
		return
	match target.kind:
		SmartTarget.Kind.TREE:
			flash_tree_target(target.tree_cn)
		SmartTarget.Kind.GOLD_MINE:
			flash_unit_interact_ring(target.node, InteractableComponent.SmartKind.GOLD_MINE, false)
		SmartTarget.Kind.DROPOFF:
			flash_unit_interact_ring(target.node, InteractableComponent.SmartKind.DROPOFF, false)
		SmartTarget.Kind.BUILD_SITE:
			flash_unit_interact_ring(target.node, InteractableComponent.SmartKind.BUILD_SITE, false)
		_:
			pass


func flash_unit_interact_ring(node: Node3D, kind: int, flash_model: bool) -> void:
	if node == null or not is_instance_valid(node):
		return
	InteractionSetup.attach(node, kind)
	var ic := InteractionSetup.get_interactable(node)
	if ic != null:
		ic.flash(0.65, flash_model)


func flash_tree_target(creation_number: int) -> void:
	if _tree_registry == null or creation_number < 0:
		return
	var node := _tree_registry.ensure_promoted(creation_number)
	if node != null:
		flash_unit_interact_ring(node, InteractableComponent.SmartKind.TREE, true)


func screen_score_node(node: Node3D, screen_pos: Vector2) -> float:
	if _unit_selector != null and _unit_selector.has_method("screen_foot_distance"):
		return float(_unit_selector.call("screen_foot_distance", node, screen_pos))
	if _rts_camera == null:
		return INF
	var cam: Camera3D = null
	if _rts_camera.has_method("get_camera"):
		cam = _rts_camera.call("get_camera") as Camera3D
	if cam == null or node == null:
		return INF
	if cam.is_position_behind(node.global_position):
		return INF
	return cam.unproject_position(node.global_position).distance_to(screen_pos)


func screen_score_tree(creation_number: int, screen_pos: Vector2) -> float:
	if _tree_registry == null:
		return INF
	var pos_wc3 := _tree_registry.get_pos_wc3(creation_number)
	if pos_wc3 == Vector2.INF:
		return INF
	var gpos := Wc3Coords.wc3_xy_to_godot(pos_wc3.x, pos_wc3.y, 0.0)
	# 尽量用条目高度
	var entry: Dictionary = _tree_registry.get_entry(creation_number)
	var p: Dictionary = entry.get("position", {})
	if not p.is_empty():
		gpos = Wc3Coords.wc3_xy_to_godot(
			float(p.get("x", pos_wc3.x)),
			float(p.get("y", pos_wc3.y)),
			float(p.get("z", 0.0))
		)
	var cam: Camera3D = null
	if _unit_selector != null and _unit_selector.get("camera") != null:
		cam = _unit_selector.get("camera") as Camera3D
	elif _rts_camera != null and _rts_camera.has_method("get_camera"):
		cam = _rts_camera.call("get_camera") as Camera3D
	if cam == null:
		return INF
	if cam.is_position_behind(gpos):
		return INF
	return cam.unproject_position(gpos).distance_to(screen_pos)


func screen_to_goal_wc3(screen_pos: Vector2) -> Vector2:
	if not _ground_at_screen.is_valid():
		return Vector2.INF
	var hit: Vector3 = _ground_at_screen.call(screen_pos)
	if hit == Vector3.INF:
		return Vector2.INF
	var inv := 1.0 / Wc3Coords.WORLD_SCALE
	return Vector2(hit.x * inv, -hit.z * inv)


func node_goal_wc3(node: Node3D, fallback: Vector2) -> Vector2:
	if node == null or not is_instance_valid(node):
		return fallback
	return Wc3Coords.godot_to_wc3_xy(node.global_position)


func is_own_dropoff_building(building: Node3D, selected: Array) -> bool:
	if building == null or not is_instance_valid(building):
		return false
	if UnitLife.is_under_construction(building):
		return false
	var bd: Dictionary = building.get_meta("unit_data", {})
	var tid := str(bd.get("typeId", "")).strip_edges()
	if ReceiveResources.capability_for_type(tid) == int(ReceiveResources.Kind.NONE):
		return false
	var b_owner := int(bd.get("owner", -1))
	for n in selected:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var ud: Dictionary = (n as Node).get_meta("unit_data", {})
		if int(ud.get("owner", -2)) == b_owner:
			return true
	return false


## 选中单位里是否有人负重（空闲农民点主城不当送回）。
func selection_any_carrying(selected: Array) -> bool:
	for n in selected:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var hc := (n as Node).get_node_or_null("HarvestController") as HarvestController
		if hc != null and hc.is_carrying():
			return true
	return false


func format_smart_status(result: Dictionary) -> String:
	var harvested := int(result.get("harvested", 0))
	var returned := int(result.get("returned", 0))
	var moved := int(result.get("moved", 0))
	var rallied := int(result.get("rallied", 0))
	var kind := str(result.get("kind", ""))
	var goal: Vector2 = result.get("goal_wc3", Vector2.INF)
	match kind:
		"Item":
			return "前往拾取道具" if moved > 0 else "请选择有空位的己方英雄拾取"
		"GoldMine":
			if harvested > 0 and moved > 0:
				return "智能 · 采金 %d · 移动 %d" % [harvested, moved]
			if harvested > 0:
				return "采集金币 · %d 单位" % harvested
		"Tree":
			if harvested > 0 and moved > 0:
				return "智能 · 伐木 %d · 移动 %d" % [harvested, moved]
			if harvested > 0:
				return "采集木材 · %d 单位" % harvested
		"Dropoff":
			if returned > 0 and moved > 0:
				return "智能 · 送回 %d · 移动 %d" % [returned, moved]
			if returned > 0:
				return "送回资源 · %d 单位" % returned
		"BuildSite":
			var built := int(result.get("built", 0))
			if built > 0:
				return "加入建造 · %d 单位" % built
	if rallied > 0 and moved > 0 and goal != Vector2.INF:
		return "智能 · 集结 %d · 移动 %d → (%.0f, %.0f)" % [rallied, moved, goal.x, goal.y]
	if rallied > 0 and goal != Vector2.INF:
		match kind:
			"GoldMine":
				return "集结点 → 金矿 · %d 建筑" % rallied
			"Tree":
				return "集结点 → 树木 · %d 建筑" % rallied
			_:
				return "集结点 → (%.0f, %.0f) · %d 建筑" % [goal.x, goal.y, rallied]
	if moved > 0 and goal != Vector2.INF:
		return "移动 → (%.0f, %.0f) · %d 单位" % [goal.x, goal.y, moved]
	if int(result.get("failed", 0)) > 0 and goal != Vector2.INF:
		return "无法到达 (%.0f, %.0f)" % [goal.x, goal.y]
	return "智能 · %s" % kind


func _gold_mine(node: Node3D) -> bool:
	if _is_gold_mine.is_valid():
		return bool(_is_gold_mine.call(node))
	return false
