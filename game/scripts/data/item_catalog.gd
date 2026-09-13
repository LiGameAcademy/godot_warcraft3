class_name ItemCatalog
extends RefCounted

## 道具静态映射。数值读 ItemDef / AbilityDataDef；未实现效果不会冒充可用。
const TEST_ITEMS := ["phea", "pman", "rde1"]
const ICONS := {
	"AIhe": "ReplaceableTextures/CommandButtons/BTNPotionGreenSmall.png",
	"AIma": "ReplaceableTextures/CommandButtons/BTNPotionBlueSmall.png",
	"AIde": "ReplaceableTextures/CommandButtons/BTNRingGreen.png",
}

static func store() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Wc3DefStore") if tree != null else null

static func data(id: String) -> ItemDef:
	var s := store()
	if s == null:
		return null
	s.ensure_table(ItemDef.TABLE_NAME)
	return s.get_row(ItemDef.TABLE_NAME, id) as ItemDef

static func all_ids() -> Array:
	var s := store()
	if s == null:
		return []
	s.ensure_table(ItemDef.TABLE_NAME)
	return s.get_ids(ItemDef.TABLE_NAME)

## 首版只接受单效果的治疗、回蓝和护甲；组合效果留待整体支持。
static func effect(id: String) -> AbilityDataDef:
	var d := data(id)
	if d == null:
		return null
	var ids := d.abil_list.split(",", false)
	if ids.size() != 1:
		return null
	var s := store()
	s.ensure_table(AbilityDataDef.TABLE_NAME)
	var ab := s.get_row(AbilityDataDef.TABLE_NAME, ids[0].strip_edges()) as AbilityDataDef
	if ab != null and ab.code_id in ["AIhe", "AIma", "AIde"] and not d.powerup:
		return ab
	return null

static func title(id: String) -> String:
	var ab := effect(id)
	if ab != null:
		match ab.code_id:
			"AIhe": return "生命药水"
			"AIma": return "魔法药水"
			"AIde": return "守护指环 +%.0f" % ab.data_a_at(1)
	var d := data(id)
	return d.display_name() if d != null else id

static func icon(id: String) -> String:
	var ab := effect(id)
	return str(ICONS.get(ab.code_id, "")) if ab != null else ""

static func tooltip(id: String) -> String:
	var ab := effect(id)
	if ab == null:
		return "%s\n效果未实现（可携带、丢弃）" % title(id)
	match ab.code_id:
		"AIhe": return "%s\n恢复 %.0f 生命；冷却 %.0f 秒。\n生命已满时不消耗。" % [title(id), ab.data_a_at(1), ab.cool_at(1)]
		"AIma": return "%s\n恢复 %.0f 魔法；冷却 %.0f 秒。\n魔法已满时不消耗。" % [title(id), ab.data_a_at(1), ab.cool_at(1)]
		"AIde": return "%s\n携带时增加 %.0f 护甲，同类可叠加。" % [title(id), ab.data_a_at(1)]
	return title(id)

static func model_path(id: String) -> String:
	var d := data(id)
	if d == null or d.file.is_empty():
		return ""
	return d.file.get_basename() + ".glb"
