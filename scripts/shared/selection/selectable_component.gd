class_name SelectableComponent
extends Node

## 可选单位/建筑：拾取数据 + 选中环显示。
## SelectionRing 由 InteractionSetup 注入，不自行实例化/查找节点树。

const GROUP := "wc3_selectable"					## 分组名。
const UNIT_RING_SLK_MUL := 1.85					## 单位环缩放系数。
const UNIT_RING_MESH_BLEND := 0.42				## 单位环 mesh 半径混合系数。
const DEFAULT_UNIT_RADIUS := 0.40				## 单位默认拾取半径。
const DEFAULT_BUILDING_RADIUS := 1.20			## 建筑默认拾取半径。
const MESH_RADIUS_EXPAND_UNIT := 1.05			## 单位 mesh 半径扩展系数。
const MESH_RADIUS_EXPAND_BUILDING := 1.12		## 建筑 mesh 半径扩展系数。
const MAX_BUILDING_PICK_RADIUS := 1.70			## 建筑最大拾取半径。
const MAX_UNIT_PICK_RADIUS := 0.85				## 单位最大拾取半径。

## 环类型。
enum RingKind {
	OWN = 1,									## 己方。
	NEUTRAL = 2,								## 中立。
	ENEMY = 3,									## 敌对。
	ALLY = 4,									## 友方。
}										

## 中立/敌对默认不可框选（金矿点选仍可）
@export var allow_marquee: bool = true
## 选中环。
@export var selection_ring: SelectionRing

var _host: Node3D = null						## 宿主。
var _pick_radius: float = -1.0					## 拾取半径。
var _ring_diameter: float = -1.0				## 选中环直径。
var _is_selected: bool = false					## 是否选中。
var _is_hovered: bool = false					## 是否悬停预览（未选中时）。
var _last_primary: bool = true					## 上次是否主选。
var _last_multi: int = 1						## 上次选中数量。


func _ready() -> void:
	_host = get_parent() as Node3D
	add_to_group(GROUP)
	_refresh_allow_marquee()

## 绑定选中环。
func bind_ring(ring: SelectionRing) -> void:
	selection_ring = ring

## 获取宿主。
func host() -> Node3D:
	if _host == null or not is_instance_valid(_host):
		_host = get_parent() as Node3D
	return _host

## 计算类型 ID。
func type_id() -> String:
	var h := host()
	if h == null:
		return ""
	var d: Dictionary = h.get_meta("unit_data", {})
	return str(d.get("typeId", "")).strip_edges()

## 计算所属阵营。
func owner_id() -> int:
	var h := host()
	if h == null:
		return -1
	var d: Dictionary = h.get_meta("unit_data", {})
	return int(d.get("owner", -1))

## 判断是否为建筑。
func is_building() -> bool:
	return BuildingVisual.is_building(type_id())

## 计算环类型。
func ring_kind() -> int:
	var tid := type_id()
	if tid == "ngol":
		return RingKind.NEUTRAL
	if owner_id() >= 12:
		return RingKind.NEUTRAL
	return RingKind.OWN

## 计算拾取半径。
func pick_radius_world() -> float:
	if _pick_radius > 0.0:
		return _pick_radius
	var h := host()
	if h == null:
		return DEFAULT_UNIT_RADIUS
	var tid := type_id()
	var is_bldg := is_building()
	var r := DEFAULT_BUILDING_RADIUS if is_bldg else DEFAULT_UNIT_RADIUS
	var from_collision := false
	if not tid.is_empty():
		Wc3DefStore.ensure_table(UnitBalanceDef.TABLE_NAME)
		var bal: Resource = Wc3DefStore.get_row(UnitBalanceDef.TABLE_NAME, tid)
		if bal is UnitBalanceDef:
			var col := (bal as UnitBalanceDef).collision
			if col > 0.0:
				r = col * Wc3Coords.WORLD_SCALE
				from_collision = true
		if not from_collision:
			Wc3DefStore.ensure_table(UnitUiDef.TABLE_NAME)
			var row: Resource = Wc3DefStore.get_row(UnitUiDef.TABLE_NAME, tid)
			if row is UnitUiDef:
				var sc := (row as UnitUiDef).scale
				if sc > 1.0:
					r = maxf(r, sc * Wc3Coords.WORLD_SCALE * 0.5)
	var mesh_r := _mesh_xz_diameter(h) * 0.45
	if mesh_r > r:
		if is_bldg:
			r = minf(mesh_r, r * MESH_RADIUS_EXPAND_BUILDING)
		elif not from_collision:
			r = minf(mesh_r, r * MESH_RADIUS_EXPAND_UNIT)
	var cap := MAX_BUILDING_PICK_RADIUS if is_bldg else MAX_UNIT_PICK_RADIUS
	_pick_radius = clampf(r, 0.12, cap)
	return _pick_radius

## 计算选中环直径。
func ring_diameter_world() -> float:
	if _ring_diameter > 0.0:
		return _ring_diameter
	var h := host()
	if h == null:
		return 1.1
	var tid := type_id()
	var info: Dictionary = {}
	var is_bldg := false
	if not tid.is_empty():
		Wc3DefStore.ensure_table(UnitBalanceDef.TABLE_NAME)
		var bal: Resource = Wc3DefStore.get_row(UnitBalanceDef.TABLE_NAME, tid)
		if bal is UnitBalanceDef:
			var ub := bal as UnitBalanceDef
			info["collision"] = ub.collision
			info["is_building"] = ub.isbldg
			is_bldg = ub.isbldg
		Wc3DefStore.ensure_table(UnitUiDef.TABLE_NAME)
		var ui: Resource = Wc3DefStore.get_row(UnitUiDef.TABLE_NAME, tid)
		if ui is UnitUiDef:
			info["def_scale"] = (ui as UnitUiDef).scale
		Wc3DefStore.ensure_table(UnitDataDef.TABLE_NAME)
		var ud: Resource = Wc3DefStore.get_row(UnitDataDef.TABLE_NAME, tid)
		if ud is UnitDataDef:
			info["path_tex"] = (ud as UnitDataDef).path_tex
	if not is_bldg:
		is_bldg = is_building()
	var diam_wc3 := Wc3IdCatalog.selection_diameter_wc3(info)
	var diam := diam_wc3 * Wc3Coords.WORLD_SCALE
	var sx := absf(h.scale.x)
	if sx > 1e-6 and sx < 0.5:
		diam /= sx
	if not is_bldg:
		diam *= UNIT_RING_SLK_MUL
		var mesh_d := _mesh_xz_diameter(h)
		if mesh_d > 0.2:
			diam = maxf(diam, mesh_d * UNIT_RING_MESH_BLEND)
		diam = clampf(diam, 0.36, 1.15)
	else:
		diam = clampf(diam, 0.5, 8.0)
	_ring_diameter = diam
	return _ring_diameter

## 显示选中环。
func show_selected(is_primary: bool, multi_count: int) -> void:
	_is_selected = true
	_is_hovered = false
	_last_primary = is_primary
	_last_multi = maxi(multi_count, 1)
	if selection_ring == null:
		return
	var kind := ring_kind()
	var col: Color = SelectionRing.COLOR_NEUTRAL if kind == RingKind.NEUTRAL else SelectionRing.COLOR_OWN
	if _last_multi > 1 and not is_primary:
		col.a *= 0.45
	selection_ring.show_selected(ring_diameter_world(), col)


## 悬停半透明环；已选中则忽略（保持选中外观）。
func show_hover() -> void:
	if _is_selected:
		return
	_is_hovered = true
	if selection_ring == null:
		return
	var kind := ring_kind()
	var col: Color = SelectionRing.COLOR_NEUTRAL if kind == RingKind.NEUTRAL else SelectionRing.COLOR_OWN
	selection_ring.show_hover(ring_diameter_world(), col)


## 清除悬停；若仍选中则还原选中环。
func hide_hover() -> void:
	if not _is_hovered:
		return
	_is_hovered = false
	if _is_selected:
		show_selected(_last_primary, _last_multi)
	elif selection_ring != null:
		selection_ring.hide_selected()


## 隐藏选中环。
func hide_selected() -> void:
	_is_selected = false
	_is_hovered = false
	if selection_ring != null:
		selection_ring.hide_selected()


## 交互闪环结束后：若仍选中则还原选中环。
func restore_ring_if_selected() -> void:
	if _is_selected:
		show_selected(_last_primary, _last_multi)
	elif selection_ring != null:
		selection_ring.hide_selected()

## 刷新是否允许框选。
func _refresh_allow_marquee() -> void:
	if ring_kind() == RingKind.NEUTRAL:
		allow_marquee = false

## 计算 mesh 的 xz 直径。
func _mesh_xz_diameter(node: Node3D) -> float:
	var aabb := AABB()
	var first := true
	for c in node.find_children("*", "VisualInstance3D", true, false):
		var vi := c as VisualInstance3D
		if vi == null or not vi.visible:
			continue
		var vname := str(vi.name)
		if vname == "SelectionRing" or vname == "DeathDropRing" or vname == "UberSplat":
			continue
		if _is_under_named(vi, "Pe2Root"):
			continue
		var local := vi.get_aabb()
		if local.size.length() < 1e-5:
			continue
		var xf: Transform3D = node.global_transform.affine_inverse() * vi.global_transform
		var box := xf * local
		if first:
			aabb = box
			first = false
		else:
			aabb = aabb.merge(box)
	if first:
		return 0.0
	return maxf(aabb.size.x, aabb.size.z)

## 判断节点是否在指定名称的节点下。
func _is_under_named(n: Node, root_name: String) -> bool:
	var p := n.get_parent()
	while p != null:
		if str(p.name) == root_name:
			return true
		p = p.get_parent()
	return false
