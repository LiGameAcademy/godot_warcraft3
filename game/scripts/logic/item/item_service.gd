class_name ItemService
extends Node

## 会话道具生命周期；场景接线负责表现，Logic 不创建 Mesh。
signal ground_spawned(ground: GroundItem)
signal message(text: String)
var ground_host: Node3D
var heightfield: Wc3Heightfield
var drops := ItemDropTable.new()

func configure(host: Node3D, hf: Wc3Heightfield, map_dir: String) -> void:
	ground_host = host
	heightfield = hf
	if not map_dir.is_empty():
		var info := RuntimeAssets.read_json_dict(map_dir.path_join("info.json"))
		drops.tables = info.get("randomItemTables", [])

func spawn(item: ItemInstance, xy: Vector2, fallback_height: float = 0.0) -> GroundItem:
	if item == null or item.holder_id != 0 or not is_instance_valid(ground_host):
		return null
	for child in ground_host.get_children():
		if child is GroundItem and not child.claimed and child.item.instance_id == item.instance_id:
			return null
	var ground := GroundItem.new()
	ground.name = "Item_%d" % item.instance_id
	ground.item = item
	var z := heightfield.interpolated_height(xy.x, xy.y) if heightfield != null else fallback_height
	ground.position = Wc3Coords.wc3_xy_to_godot(xy.x, xy.y, z)
	ground_host.add_child(ground)
	ground_spawned.emit(ground)
	return ground

func drop_from(unit: Node3D, slot: int) -> bool:
	var inv := Inventory.of(unit)
	if inv == null or not CombatQuery.is_alive_in_world(unit):
		return false
	var item := inv.item_at(slot)
	if item == null:
		return false
	var d := ItemCatalog.data(item.type_id)
	if d == null or not d.droppable:
		message.emit("该道具不能丢弃")
		return false
	item = inv.remove_at(slot)
	var xy := Wc3Coords.godot_to_wc3_xy(unit.global_position)
	if spawn(item, xy, unit.global_position.y / Wc3Coords.WORLD_SCALE) == null:
		inv.insert(item, slot)
		return false
	message.emit("已丢弃 %s" % ItemCatalog.title(item.type_id))
	return true

## 必须在 HeroDeathRegistry 保存前执行，先按 drop 标记移走必掉物。
func prepare_hero_death(unit: Node3D) -> void:
	var inv := Inventory.of(unit)
	if inv == null:
		return
	for i in range(Inventory.CAPACITY):
		var item := inv.item_at(i)
		if item != null and ItemCatalog.data(item.type_id).drop:
			item = inv.remove_at(i)
			if spawn(item, Wc3Coords.godot_to_wc3_xy(unit.global_position), unit.global_position.y / Wc3Coords.WORLD_SCALE) == null:
				# 地面容器尚未就绪或已销毁时，保留实例供随后的死亡登记保存。
				inv.insert(item, i)
				message.emit("死亡掉落失败，道具已保留：%s" % ItemCatalog.title(item.type_id))

func on_unit_died(unit: Node3D, _killer: Node3D = null) -> void:
	if not is_instance_valid(unit) or bool(unit.get_meta("items_death_processed", false)):
		return
	unit.set_meta("items_death_processed", true)
	var ud: Dictionary = unit.get_meta("unit_data", {})
	var xy := Wc3Coords.godot_to_wc3_xy(unit.global_position)
	var index := 0
	for id in drops.roll(ud):
		spawn(ItemInstance.create(id), xy + Vector2(index * 48.0, 0.0), unit.global_position.y / Wc3Coords.WORLD_SCALE)
		index += 1
	for diagnostic in drops.diagnostics:
		message.emit(diagnostic)
		push_warning("ItemDropTable: " + diagnostic)
