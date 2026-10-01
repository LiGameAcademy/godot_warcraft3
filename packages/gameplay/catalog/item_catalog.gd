class_name ItemCatalog
extends RefCounted

const DefinitionLayers: GDScript = preload("res://addons/rts_content/definitions/definition_layers.gd")

## 道具静态映射。数值读 ItemDef / AbilityDataDef；名称/图标读 ItemFunc+ItemStrings。
## 未实现效果不会冒充可用。

const FOLDER := "res://assets/slk-exported/Units"
const TEST_ITEMS := ["phea", "pman", "rde1"]
## 效果白名单：AbilityData.code（非 alias）
const EFFECT_CODES := ["AIhe", "AIma", "AIde"]
## 无 ItemFunc.Art 时的效果 → 图标回退
const ICON_FALLBACKS := {
	"AIhe": "ReplaceableTextures/CommandButtons/BTNPotionGreenSmall.png",
	"AIma": "ReplaceableTextures/CommandButtons/BTNPotionBlueSmall.png",
	"AIde": "ReplaceableTextures/CommandButtons/BTNRingGreen.png",
}

static var _ui: Dictionary = {}
static var _ui_loaded: bool = false


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


## 电脑值得拾取：当前效果白名单内（治疗 / 回蓝 / 护甲）。
static func is_ai_pickup_worth(id: String) -> bool:
	return effect(id) != null


## 首版只接受单效果的治疗、回蓝和护甲；组合效果留待整体支持。
static func effect(id: String) -> AbilityDataDef:
	var d := data(id)
	if d == null:
		return null
	var ids := d.abil_list.split(",", false)
	if ids.size() != 1:
		return null
	var s := store()
	if s == null:
		return null
	s.ensure_table(AbilityDataDef.TABLE_NAME)
	var ab := s.get_row(AbilityDataDef.TABLE_NAME, ids[0].strip_edges()) as AbilityDataDef
	if ab != null and ab.code_id in EFFECT_CODES and not d.powerup:
		return ab
	return null


static func title(id: String) -> String:
	_ensure_ui()
	var row: Dictionary = _ui.get(id, {})
	var name_s := str(row.get("name", "")).strip_edges()
	if not name_s.is_empty():
		return name_s
	var ab := effect(id)
	if ab != null:
		match ab.code_id:
			"AIhe":
				return "生命药水"
			"AIma":
				return "魔法药水"
			"AIde":
				return "守护指环 +%.0f" % ab.data_a_at(1)
	var d := data(id)
	return d.display_name() if d != null else id


static func icon(id: String) -> String:
	_ensure_ui()
	var row: Dictionary = _ui.get(id, {})
	var art := str(row.get("art", "")).strip_edges().replace("\\", "/")
	if not art.is_empty():
		return _art_to_png(art)
	var ab := effect(id)
	if ab != null:
		return str(ICON_FALLBACKS.get(ab.code_id, ""))
	return ""


static func tooltip(id: String) -> String:
	_ensure_ui()
	var row: Dictionary = _ui.get(id, {})
	var tip := str(row.get("tip", "")).strip_edges()
	var uber := str(row.get("ubertip", "")).strip_edges()
	var ab := effect(id)
	if ab == null:
		var base := tip if not tip.is_empty() else title(id)
		if not uber.is_empty():
			base = base + "\n" + uber
		return "%s\n效果未实现（可携带、丢弃）" % base
	# 有真实 Ubertip 时优先；否则按效果码拼数值
	if not tip.is_empty() or not uber.is_empty():
		var out := tip if not tip.is_empty() else title(id)
		if not uber.is_empty():
			out = out + "\n" + uber
		return out
	match ab.code_id:
		"AIhe":
			return "%s\n恢复 %.0f 生命；冷却 %.0f 秒。\n生命已满时不消耗。" % [title(id), ab.data_a_at(1), ab.cool_at(1)]
		"AIma":
			return "%s\n恢复 %.0f 魔法；冷却 %.0f 秒。\n魔法已满时不消耗。" % [title(id), ab.data_a_at(1), ab.cool_at(1)]
		"AIde":
			return "%s\n携带时增加 %.0f 护甲，同类可叠加。" % [title(id), ab.data_a_at(1)]
	return title(id)


## ItemDef.file → 逻辑相对路径（无扩展名时默认 .gltf 语义，由 resolved_model_path 择优）。
static func model_path(id: String) -> String:
	var d := data(id)
	if d == null or d.file.is_empty():
		return ""
	var p := d.file.replace("\\", "/").strip_edges()
	var lower := p.to_lower()
	if lower.ends_with(".mdl") or lower.ends_with(".mdx"):
		return p.substr(0, p.length() - 4) + ".gltf"
	if lower.ends_with(".glb") or lower.ends_with(".gltf"):
		return p
	return p + ".gltf"


## 磁盘上真实可加载的模型路径（优先 .gltf，回退 .glb）；无则空。
static func resolved_model_path(id: String) -> String:
	var logical := model_path(id)
	if logical.is_empty():
		return ""
	var stem := logical
	var lower := stem.to_lower()
	if lower.ends_with(".gltf"):
		stem = stem.substr(0, stem.length() - 5)
	elif lower.ends_with(".glb"):
		stem = stem.substr(0, stem.length() - 4)
	for ext in [".gltf", ".glb"]:
		var p := RuntimeAssets.converted_path(stem + ext)
		if RuntimeAssets.file_exists(p):
			return p
	# 仅有 .scn 时仍返回 .gltf 逻辑路径，交给 MapModelCache.resolve_model_scene
	var scn_probe := RuntimeAssets.resolve_model_scene(stem + ".gltf")
	if scn_probe.is_empty():
		scn_probe = RuntimeAssets.resolve_model_scene(stem + ".glb")
	if not scn_probe.is_empty():
		return RuntimeAssets.converted_path(stem + ".gltf")
	return ""


static func _art_to_png(art: String) -> String:
	var a := art.strip_edges().replace("\\", "/")
	var lower := a.to_lower()
	if lower.ends_with(".blp") or lower.ends_with(".tga"):
		return a.substr(0, a.length() - 4) + ".png"
	if not lower.ends_with(".png") and a.contains("/"):
		return a + ".png"
	return a


static func _ensure_ui() -> void:
	if _ui_loaded:
		return
	_ui_loaded = true
	_merge_ini(FOLDER.path_join("ItemFunc.txt"))
	_merge_ini(FOLDER.path_join("ItemStrings.txt"))


static func _merge_ini(res_path: String) -> void:
	var logical: String = res_path.trim_prefix("res://assets/slk-exported/")
	var rows: Dictionary = DefinitionLayers.read_rows(logical)
	for id: String in rows:
		if not _ui.has(id):
			_ui[id] = {}
		var target: Dictionary = _ui[id]
		target.merge(rows[id] as Dictionary, true)
