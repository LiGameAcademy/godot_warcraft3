class_name InteractableComponent
extends Node

## 可右键交互目标：闪环反馈。SelectionRing / Selectable 由 InteractionSetup 注入。

const GROUP := "wc3_interactable"

## 智能类型。
enum SmartKind {
	NONE = 0,									## 无。
	GOLD_MINE = 1,								## 金矿。
	TREE = 2,									## 树。
	DROPOFF = 3,								## 掉落点。
	BUILD_SITE = 4,								## 建筑工地。
}

@export var smart_kind: int = SmartKind.NONE		## 智能类型。
## 树等可闪模型 emission；建筑默认只闪环
@export var flash_model_default: bool = false
@export var selection_ring: SelectionRing			## 选中环。
@export var selectable: SelectableComponent			## 可选单位/建筑。

var _host: Node3D = null						## 宿主。

func _ready() -> void:
	_host = get_parent() as Node3D
	add_to_group(GROUP)
	if smart_kind == SmartKind.NONE:
		smart_kind = _infer_kind()

## 绑定依赖。
func bind_dependencies(ring: SelectionRing, sel: SelectableComponent) -> void:
	selection_ring = ring
	selectable = sel

## 获取宿主。
func host() -> Node3D:
	if _host == null or not is_instance_valid(_host):
		_host = get_parent() as Node3D
	return _host

## 右键命中反馈：注入的环上播黄闪；结束后还原选中态。
func flash(duration: float = 0.65, flash_model: bool = false) -> void:
	var diam := 1.15
	if selectable != null:
		diam = selectable.ring_diameter_world()
	elif smart_kind == SmartKind.TREE:
		diam = 1.15
	if selection_ring != null:
		selection_ring.play_interact_flash(
			diam,
			duration,
			SelectionRing.COLOR_NEUTRAL,
			Callable(self, "_on_flash_finished")
		)
	var do_model := flash_model or flash_model_default or smart_kind == SmartKind.TREE
	if do_model:
		var h := host()
		if h != null:
			TargetFlashFx.flash_model_emission(h, duration)

## 闪环结束回调。
func _on_flash_finished() -> void:
	if selectable != null:
		selectable.restore_ring_if_selected()
	elif selection_ring != null:
		selection_ring.hide_selected()

## 推断智能类型。
func _infer_kind() -> int:
	var h := host()
	if h == null:
		return SmartKind.NONE
	if h.has_meta("tree_runtime") or h.has_meta("doodad_data"):
		flash_model_default = true
		return SmartKind.TREE
	var d: Dictionary = h.get_meta("unit_data", {})
	var tid := str(d.get("typeId", "")).strip_edges()
	if tid == "ngol":
		return SmartKind.GOLD_MINE
	if UnitLife.is_under_construction(h):
		return SmartKind.BUILD_SITE
	if ReceiveResources.capability_for_type(tid) != int(ReceiveResources.Kind.NONE):
		return SmartKind.DROPOFF
	return SmartKind.NONE
