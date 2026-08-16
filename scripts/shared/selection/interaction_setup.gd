class_name InteractionSetup
extends RefCounted

## 单位/树 promote 时装配：SelectionRing 场景 + Selectable + Interactable，并注入依赖。
## 不靠节点名查找临时闪环；幂等（重复调用只补齐缺失）。

const RING_SCENE := preload("res://scenes/selection/selection_ring.tscn")

## 装配：SelectionRing 场景 + Selectable + Interactable，并注入依赖。
## 幂等；已有 Selectable 时用 type_id 短路，避免重复 BuildingVisual/DefStore。
static func attach(host: Node3D, smart_kind: int = 0) -> void:
	if host == null or not is_instance_valid(host):
		push_error("InteractionSetup.attach: host is null or not is_instance_valid")
		return
	var ring := _ensure_ring(host)
	var sel := _ensure_selectable(host, ring)
	var kind_none := 0
	var tid := sel.type_id()
	var need_interact := smart_kind != kind_none
	if not need_interact:
		need_interact = (
			tid == "ngol"
			or host.has_meta("tree_runtime")
			or host.has_meta("doodad_data")
			or BuildingVisual.is_building(tid)
		)
	if need_interact:
		_ensure_interactable(host, ring, sel, smart_kind)

## 获取 Selectable 组件。
static func get_selectable(host: Node3D) -> SelectableComponent:
	if host == null:
		return null
	return host.get_node_or_null("Selectable") as SelectableComponent

## 获取 Interactable 组件。
static func get_interactable(host: Node3D) -> InteractableComponent:
	if host == null:
		return null
	return host.get_node_or_null("Interactable") as InteractableComponent

## 确保 SelectionRing 场景存在。
static func _ensure_ring(host: Node3D) -> SelectionRing:
	var ring := host.get_node_or_null("SelectionRing") as SelectionRing
	if ring != null:
		return ring
	ring = RING_SCENE.instantiate() as SelectionRing
	if ring == null:
		return null
	ring.name = "SelectionRing"
	ring.visible = false
	host.add_child(ring)
	return ring

## 确保 Selectable 组件存在。
static func _ensure_selectable(host: Node3D, ring: SelectionRing) -> SelectableComponent:
	var sel := host.get_node_or_null("Selectable") as SelectableComponent
	if sel == null:
		sel = SelectableComponent.new()
		sel.name = "Selectable"
		host.add_child(sel)
	sel.bind_ring(ring)
	return sel

## 确保 Interactable 组件存在。
static func _ensure_interactable(
	host: Node3D,
	ring: SelectionRing,
	sel: SelectableComponent,
	smart_kind: int
) -> InteractableComponent:
	var ic := host.get_node_or_null("Interactable") as InteractableComponent
	if ic == null:
		ic = InteractableComponent.new()
		ic.name = "Interactable"
		host.add_child(ic)
	if smart_kind != 0:
		ic.smart_kind = smart_kind
	ic.bind_dependencies(ring, sel)
	return ic
