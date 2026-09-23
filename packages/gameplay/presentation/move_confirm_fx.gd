class_name MoveConfirmFx
extends Node3D
## 右键命令确认箭头：WC3 `UI/Feedback/Confirmation`。
##
## 原作语义：
## - 移动 / 巡逻等 → 绿色
## - 攻击 / 攻击移动 → 红色
## Confirmation.mdx 的 geoset 走 Replaceable TeamColor 占位；转换后若不染色就是灰金属色。
## 本类在实例化后强制反馈色（不跟玩家队色走）。

const CONFIRM_REL := "UI/Feedback/Confirmation/Confirmation.glb"
const FALLBACK_TEX := "ReplaceableTextures/Selection/SelectionCircleMed.png"
const LIFETIME_SEC := 1.15
const FALLBACK_DIAM := 1.2

## 与原作反馈色接近（非 TeamColor00 玩家红）
const COLOR_MOVE := Color(0.2, 1.0, 0.28, 1.0)
const COLOR_ATTACK := Color(1.0, 0.12, 0.08, 1.0)

enum Kind {
	MOVE,
	ATTACK,
}

var _cache: MapModelCache = null
var _inst: Node3D = null
var _age: float = 0.0
var _kind: int = Kind.MOVE


func setup(cache: MapModelCache) -> void:
	_cache = cache


func play_at_wc3(
	wc3_xy: Vector2,
	heightfield: Wc3Heightfield = null,
	kind: int = Kind.MOVE
) -> void:
	_clear_inst()
	_age = 0.0
	_kind = kind
	var z := 0.0
	if heightfield != null and heightfield.is_valid():
		z = heightfield.interpolated_height(wc3_xy.x, wc3_xy.y)
	global_position = Wc3Coords.wc3_xy_to_godot(wc3_xy.x, wc3_xy.y, z + 2.0)
	_inst = _spawn()
	if _inst == null:
		_inst = _spawn_fallback_ring()
	if _inst == null:
		queue_free()
		return
	_visual_parent().add_child(_inst)
	_apply_feedback_color(_inst, _feedback_color())
	_try_play_anim(_inst)
	set_process(true)


func _visual_parent() -> Node3D:
	var n := get_node_or_null("VisualRoot") as Node3D
	return n if n != null else self


func _feedback_color() -> Color:
	return COLOR_ATTACK if _kind == Kind.ATTACK else COLOR_MOVE


func _process(delta: float) -> void:
	_age += delta
	if _inst is MeshInstance3D:
		var mi := _inst as MeshInstance3D
		var mat := mi.material_override as StandardMaterial3D
		if mat != null:
			var a := clampf(1.0 - (_age / LIFETIME_SEC), 0.0, 1.0)
			mat.albedo_color.a = a
	if _age >= LIFETIME_SEC:
		queue_free()


func _spawn() -> Node3D:
	var path := RuntimeAssets.converted_path(CONFIRM_REL)
	if _cache != null:
		var n := _cache.instance_glb(path)
		if n != null:
			return n
	if ResourceLoader.exists(path):
		var packed := load(path)
		if packed is PackedScene:
			return (packed as PackedScene).instantiate() as Node3D
	return null


## 把 TeamColor 占位 / 箭头材质染成反馈色。
## 为何不用 apply_team_color(玩家色)：确认箭头是命令反馈色，固定绿/红，不跟队色走。
func _apply_feedback_color(root: Node, color: Color) -> void:
	if root == null:
		return
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for si in range(mi.mesh.get_surface_count()):
			var base: Material = mi.get_active_material(si)
			var sm := StandardMaterial3D.new()
			if base is StandardMaterial3D:
				var src := base as StandardMaterial3D
				sm = src.duplicate() as StandardMaterial3D
				# 队色占位贴图本身是灰/紫块，清掉才能显出纯反馈色
				if _is_team_color_placeholder(sm.albedo_texture):
					sm.albedo_texture = null
			sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sm.albedo_color = color
			sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			sm.cull_mode = BaseMaterial3D.CULL_DISABLED
			sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			sm.render_priority = 30
			# 箭头灰度贴图（RallyArrow2）保留，用 albedo 乘绿/红
			mi.set_surface_override_material(si, sm)


func _is_team_color_placeholder(tex: Texture2D) -> bool:
	if tex == null:
		return false
	var p := str(tex.resource_path).replace("\\", "/").to_lower()
	var n := str(tex.resource_name).to_lower()
	return (
		p.contains("team_color")
		or p.contains("placeholders/team_color")
		or p.contains("teamcolor")
		or n.contains("team_color")
		or n.contains("teamcolor")
	)


func _spawn_fallback_ring() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "ConfirmFallback"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plane := PlaneMesh.new()
	plane.size = Vector2(FALLBACK_DIAM, FALLBACK_DIAM)
	plane.orientation = PlaneMesh.FACE_Y
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.render_priority = 25
	mat.albedo_color = _feedback_color()
	var tex: Texture2D = RuntimeAssets.load_converted_texture(FALLBACK_TEX)
	if tex != null:
		mat.albedo_texture = tex
	mi.material_override = mat
	return mi


func _try_play_anim(root: Node) -> void:
	var ap := _find_ap(root)
	if ap == null:
		return
	ap.active = true
	var names := ap.get_animation_list()
	if names.is_empty():
		return
	var anim := str(names[0])
	for n in names:
		var leaf := str(n)
		var slash := leaf.rfind("/")
		if slash >= 0:
			leaf = leaf.substr(slash + 1)
		var low := leaf.to_lower()
		if low.begins_with("stand") or low.begins_with("birth") or low.begins_with("death"):
			anim = str(n)
			break
	ap.play(anim)


func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var f := _find_ap(c)
		if f:
			return f
	return null


func _clear_inst() -> void:
	if _inst != null and is_instance_valid(_inst):
		_inst.queue_free()
	_inst = null


func _exit_tree() -> void:
	_clear_inst()
