class_name MapDebugGridLayer
extends Node3D

## 调试栅格层：向地面 / 悬崖等已激活 ShaderMaterial 写入 dbg_* uniform。
## 不属某一渲染子系统；地形、水体、悬崖、寻路预览共用。


@export var terrain_layer: MapTerrainLayer = null
@export var cliffs_layer: MapCliffLayer = null
@export var ramps_layer: MapRampLayer = null

@export var show_tile_grid: bool = true ## 大黄网 512u
@export var show_path_grid: bool = true ## 中白网 128u
@export var show_fine_grid: bool = true ## 小灰网 32u

var _enabled: bool = true
## null | Dictionary{tile,path,fine} 非空时覆盖 @export（编辑器 ViewGridLevel）
var _override: Variant = null


func _ready() -> void:
	_resolve_layers()


func build(_ctx: MapBuildContext = null) -> void:
	_resolve_layers()
	_override = null
	_apply()
	AppLog.info(
		AppLog.Layer.PRESENT,
		"DebugGrid",
		"tile=%s path=%s fine=%s mats=%d"
		% [_eff_tile(), _eff_path(), _eff_fine(), _collect_materials().size()]
	)


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	_apply()


func set_grid_flags(show_tile: bool, show_path: bool, show_fine: bool) -> void:
	_override = {"tile": show_tile, "path": show_path, "fine": show_fine}
	_apply()


func _eff_tile() -> bool:
	if _override is Dictionary:
		return bool(_override["tile"])
	return show_tile_grid


func _eff_path() -> bool:
	if _override is Dictionary:
		return bool(_override["path"])
	return show_path_grid


func _eff_fine() -> bool:
	if _override is Dictionary:
		return bool(_override["fine"])
	return show_fine_grid


func _resolve_layers() -> void:
	if terrain_layer == null:
		terrain_layer = get_node_or_null("../Terrain") as MapTerrainLayer
	if cliffs_layer == null:
		cliffs_layer = get_node_or_null("../Cliffs") as MapCliffLayer
	if ramps_layer == null:
		ramps_layer = get_node_or_null("../Ramps") as MapRampLayer


func _apply() -> void:
	_resolve_layers()
	var t := _eff_tile() if _enabled else false
	var p := _eff_path() if _enabled else false
	var f := _eff_fine() if _enabled else false
	var mats := _collect_materials()
	if mats.is_empty() and (t or p or f):
		# 地图尚未 build 时 active_material 为空属正常（Director 会在加载后再 apply）。
		AppLog.debug(
			AppLog.Layer.PRESENT,
			"DebugGrid",
			"暂无材质（地形未生成），跳过本次 apply"
		)
		return
	for mat in mats:
		mat.set_shader_parameter("dbg_grid_tile", t)
		mat.set_shader_parameter("dbg_grid_path", p)
		mat.set_shader_parameter("dbg_grid_fine", f)
	AppLog.debug(
		AppLog.Layer.PRESENT,
		"DebugGrid",
		"apply tile=%s path=%s fine=%s → %d mats" % [t, p, f, mats.size()]
	)


func _collect_materials() -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	if is_instance_valid(terrain_layer) and terrain_layer.has_method("get_debug_materials"):
		out.append_array(terrain_layer.get_debug_materials())
	if is_instance_valid(cliffs_layer) and cliffs_layer.has_method("get_debug_materials"):
		out.append_array(cliffs_layer.get_debug_materials())
	if is_instance_valid(ramps_layer) and ramps_layer.has_method("get_debug_materials"):
		out.append_array(ramps_layer.get_debug_materials())
	return out
