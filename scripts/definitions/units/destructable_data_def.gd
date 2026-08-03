class_name DestructableDataDef
extends Resource

## Units/DestructableData.slk 一行定义。

const TABLE_NAME := "DestructableData"
const SLK_REL_PATH := "Units/DestructableData.json"
const PRIMARY_KEY := "DestructableID"

@export var destructable_id: String = ""
@export var category: String = ""
@export var tilesets: String = ""
@export var tileset_specific: bool = false
@export var file: String = ""
@export var lightweight: bool = false
@export var fat_los: bool = false
@export var tex_id: int = 0
@export var tex_file: String = ""
@export var comment: String = ""
@export var name_key: String = ""
@export var editor_suffix: String = ""
@export var dood_class: String = ""
@export var use_click_helper: bool = false
@export var on_cliffs: bool = false
@export var on_water: bool = false
@export var can_place_dead: bool = false
@export var walkable: bool = false
@export var cliff_height: float = 0.0
@export var targ_type: String = ""
@export var armor: String = ""
@export var num_var: int = 0
@export var hp: int = 0
@export var occ_h: float = 0.0
@export var fly_h: float = 0.0
@export var fixed_rot: float = 0.0
@export var sel_size: float = 0.0
@export var min_scale: float = 0.0
@export var max_scale: float = 0.0
@export var can_place_rand_scale: bool = false
@export var max_pitch: float = 0.0
@export var max_roll: float = 0.0
@export var radius: float = 0.0
@export var fog_radius: float = 0.0
@export var fog_vis: bool = false
@export var path_tex: String = ""
@export var path_tex_death: String = ""
@export var death_snd: String = ""
@export var shadow: String = ""
@export var color_r: int = 0
@export var color_g: int = 0
@export var color_b: int = 0
@export var show_in_mm: bool = false
@export var use_mm_color: bool = false
@export var mm_red: int = 0
@export var mm_green: int = 0
@export var mm_blue: int = 0
@export var build_time: int = 0
@export var repair_time: int = 0
@export var gold_rep: int = 0
@export var lumber_rep: int = 0
@export var user_list: bool = false
@export var in_beta: bool = false
@export var version: int = 0
@export var selectable: bool = false
@export var selcircsize: float = 0.0
@export var portraitmodel: String = ""

## 显示名：优先 comment/name，否则主键。
func display_name() -> String:
	var c := comment.strip_edges()
	return c if not c.is_empty() and c != "_" else destructable_id

static func from_slk_record(rec: Dictionary) -> DestructableDataDef:
	var d := DestructableDataDef.new()
	d.destructable_id = str(rec.get("DestructableID", "")).strip_edges()
	d.category = str(rec.get("category", "")).strip_edges()
	d.tilesets = str(rec.get("tilesets", "")).strip_edges()
	d.tileset_specific = int(rec.get("tilesetSpecific", 0)) != 0
	d.file = str(rec.get("file", "")).replace("\\", "/").strip_edges()
	d.lightweight = int(rec.get("lightweight", 0)) != 0
	d.fat_los = int(rec.get("fatLOS", 0)) != 0
	d.tex_id = int(rec.get("texID", 0))
	d.tex_file = str(rec.get("texFile", "")).replace("\\", "/").strip_edges()
	d.comment = str(rec.get("comment", "")).strip_edges()
	d.name_key = str(rec.get("Name", "")).strip_edges()
	d.editor_suffix = str(rec.get("EditorSuffix", "")).strip_edges()
	d.dood_class = str(rec.get("doodClass", "")).strip_edges()
	d.use_click_helper = int(rec.get("useClickHelper", 0)) != 0
	d.on_cliffs = int(rec.get("onCliffs", 0)) != 0
	d.on_water = int(rec.get("onWater", 0)) != 0
	d.can_place_dead = int(rec.get("canPlaceDead", 0)) != 0
	d.walkable = int(rec.get("walkable", 0)) != 0
	d.cliff_height = float(rec.get("cliffHeight", 0.0))
	d.targ_type = str(rec.get("targType", "")).strip_edges()
	d.armor = str(rec.get("armor", "")).strip_edges()
	d.num_var = int(rec.get("numVar", 0))
	d.hp = int(rec.get("HP", 0))
	d.occ_h = float(rec.get("occH", 0.0))
	d.fly_h = float(rec.get("flyH", 0.0))
	d.fixed_rot = float(rec.get("fixedRot", 0.0))
	d.sel_size = float(rec.get("selSize", 0.0))
	d.min_scale = float(rec.get("minScale", 0.0))
	d.max_scale = float(rec.get("maxScale", 0.0))
	d.can_place_rand_scale = int(rec.get("canPlaceRandScale", 0)) != 0
	d.max_pitch = float(rec.get("maxPitch", 0.0))
	d.max_roll = float(rec.get("maxRoll", 0.0))
	d.radius = float(rec.get("radius", 0.0))
	d.fog_radius = float(rec.get("fogRadius", 0.0))
	d.fog_vis = int(rec.get("fogVis", 0)) != 0
	d.path_tex = str(rec.get("pathTex", "")).replace("\\", "/").strip_edges()
	d.path_tex_death = str(rec.get("pathTexDeath", "")).replace("\\", "/").strip_edges()
	d.death_snd = str(rec.get("deathSnd", "")).strip_edges()
	d.shadow = str(rec.get("shadow", "")).replace("\\", "/").strip_edges()
	d.color_r = int(rec.get("colorR", 0))
	d.color_g = int(rec.get("colorG", 0))
	d.color_b = int(rec.get("colorB", 0))
	d.show_in_mm = int(rec.get("showInMM", 0)) != 0
	d.use_mm_color = int(rec.get("useMMColor", 0)) != 0
	d.mm_red = int(rec.get("MMRed", 0))
	d.mm_green = int(rec.get("MMGreen", 0))
	d.mm_blue = int(rec.get("MMBlue", 0))
	d.build_time = int(rec.get("buildTime", 0))
	d.repair_time = int(rec.get("repairTime", 0))
	d.gold_rep = int(rec.get("goldRep", 0))
	d.lumber_rep = int(rec.get("lumberRep", 0))
	d.user_list = int(rec.get("UserList", 0)) != 0
	d.in_beta = int(rec.get("InBeta", 0)) != 0
	d.version = int(rec.get("version", 0))
	d.selectable = int(rec.get("selectable", 0)) != 0
	d.selcircsize = float(rec.get("selcircsize", 0.0))
	d.portraitmodel = str(rec.get("portraitmodel", "")).replace("\\", "/").strip_edges()
	return d

static func register_to(store: Node) -> void:
	if store == null or not store.has_method("register_table"):
		push_error("DestructableDataDef: 无法注册到 DefStore")
		return
	store.register_table(TABLE_NAME, SLK_REL_PATH, PRIMARY_KEY, from_slk_record)
