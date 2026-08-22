class_name BlizzardAreaDecal
extends Node3D

## 暴风雪区域地面贴花（Present）：半径对齐 AreaN，引导期间常驻。

const TEX_REL := "ReplaceableTextures/Selection/SelectionCircleMed.png"
const COLOR := Color(0.45, 0.72, 1.0, 0.42)
const EDGE_COLOR := Color(0.65, 0.88, 1.0, 0.65)
const Y_OFFSET_WC3 := 6.0

var _age: float = 0.0
var _lifetime: float = 3.0
var _mi: MeshInstance3D = null


static func spawn(
	parent: Node,
	center_wc3: Vector2,
	radius_wc3: float,
	lifetime_sec: float,
	heightfield: Wc3Heightfield = null
) -> BlizzardAreaDecal:
	if parent == null or center_wc3 == Vector2.INF:
		return null
	var fx := BlizzardAreaDecal.new()
	fx.name = "BlizzardAreaDecal"
	parent.add_child(fx)
	fx._setup(center_wc3, radius_wc3, lifetime_sec, heightfield)
	return fx


func _setup(
	center_wc3: Vector2,
	radius_wc3: float,
	lifetime_sec: float,
	heightfield: Wc3Heightfield
) -> void:
	_lifetime = maxf(lifetime_sec, 0.2)
	_age = 0.0
	var z := 0.0
	if heightfield != null and heightfield.is_valid():
		z = heightfield.interpolated_height(center_wc3.x, center_wc3.y)
	global_position = Wc3Coords.wc3_xy_to_godot(
		center_wc3.x, center_wc3.y, z + Y_OFFSET_WC3 * Wc3Coords.WORLD_SCALE
	)
	var diam_g := maxf(radius_wc3 * 2.0 * Wc3Coords.WORLD_SCALE, 0.5)
	_mi = MeshInstance3D.new()
	_mi.name = "DecalMesh"
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plane := PlaneMesh.new()
	plane.size = Vector2(diam_g, diam_g)
	plane.orientation = PlaneMesh.FACE_Y
	_mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.render_priority = 20
	mat.albedo_color = COLOR
	var tex: Texture2D = RuntimeAssets.load_converted_texture(TEX_REL)
	if tex != null:
		mat.albedo_texture = tex
		mat.albedo_color = EDGE_COLOR
	_mi.material_override = mat
	add_child(_mi)
	set_process(true)


func _process(delta: float) -> void:
	_age += delta
	if _mi == null:
		return
	var mat := _mi.material_override as StandardMaterial3D
	if mat != null:
		var pulse := 0.85 + 0.15 * sin(_age * 8.0)
		var base_a := EDGE_COLOR.a if mat.albedo_texture != null else COLOR.a
		mat.albedo_color.a = base_a * pulse
	if _age >= _lifetime:
		queue_free()
