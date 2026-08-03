class_name UnitUiDef
extends Resource

## Units/unitUI.slk 一行定义。

const TABLE_NAME := "UnitUI"
const SLK_REL_PATH := "Units/unitUI.json"
const PRIMARY_KEY := "unitUIID"

@export var unit_uiid: String = ""
@export var sort_ui: String = ""
@export var file: String = ""
@export var file_ver_flags: int = 0
@export var unit_sound: String = ""
@export var tileset_specific: bool = false
@export var name_key: String = ""
@export var unit_class: String = ""
@export var special: bool = false
@export var campaign: bool = false
@export var in_editor: bool = false
@export var hidden_in_editor: bool = false
@export var hostile_pal: bool = false
@export var drop_items: bool = false
@export var nbmm_icon: bool = false
@export var use_click_helper: bool = false
@export var blend: float = 0.0
@export var scale: float = 0.0
@export var scale_bull: bool = false
@export var max_pitch: float = 0.0
@export var max_roll: float = 0.0
@export var elev_pts: float = 0.0
@export var elev_rad: float = 0.0
@export var fog_rad: float = 0.0
@export var walk: float = 0.0
@export var run: float = 0.0
@export var sel_z: float = 0.0
@export var weap1: String = ""
@export var weap2: String = ""
@export var team_color: int = 0
@export var custom_team_color: bool = false
@export var armor: String = ""
@export var model_scale: float = 0.0
@export var red: int = 0
@export var green: int = 0
@export var blue: int = 0
@export var uber_splat: String = ""
@export var unit_shadow: String = ""
@export var building_shadow: String = ""
@export var shadow_w: float = 0.0
@export var shadow_h: float = 0.0
@export var shadow_x: float = 0.0
@export var shadow_y: float = 0.0
@export var shadow_on_water: bool = false
@export var sel_circ_on_water: bool = false
@export var occ_h: float = 0.0
@export var in_beta: bool = false

## 显示名：优先 comment/name，否则主键。
func display_name() -> String:
	var c := name_key.strip_edges()
	return c if not c.is_empty() and c != "_" else unit_uiid

static func from_slk_record(rec: Dictionary) -> UnitUiDef:
	var d := UnitUiDef.new()
	d.unit_uiid = str(rec.get("unitUIID", "")).strip_edges()
	d.sort_ui = str(rec.get("sortUI", "")).strip_edges()
	d.file = str(rec.get("file", "")).replace("\\", "/").strip_edges()
	d.file_ver_flags = int(rec.get("fileVerFlags", 0))
	d.unit_sound = str(rec.get("unitSound", "")).strip_edges()
	d.tileset_specific = int(rec.get("tilesetSpecific", 0)) != 0
	d.name_key = str(rec.get("name", "")).strip_edges()
	d.unit_class = str(rec.get("unitClass", "")).strip_edges()
	d.special = int(rec.get("special", 0)) != 0
	d.campaign = int(rec.get("campaign", 0)) != 0
	d.in_editor = int(rec.get("inEditor", 0)) != 0
	d.hidden_in_editor = int(rec.get("hiddenInEditor", 0)) != 0
	d.hostile_pal = int(rec.get("hostilePal", 0)) != 0
	d.drop_items = int(rec.get("dropItems", 0)) != 0
	d.nbmm_icon = int(rec.get("nbmmIcon", 0)) != 0
	d.use_click_helper = int(rec.get("useClickHelper", 0)) != 0
	d.blend = float(rec.get("blend", 0.0))
	d.scale = float(rec.get("scale", 0.0))
	d.scale_bull = int(rec.get("scaleBull", 0)) != 0
	d.max_pitch = float(rec.get("maxPitch", 0.0))
	d.max_roll = float(rec.get("maxRoll", 0.0))
	d.elev_pts = float(rec.get("elevPts", 0.0))
	d.elev_rad = float(rec.get("elevRad", 0.0))
	d.fog_rad = float(rec.get("fogRad", 0.0))
	d.walk = float(rec.get("walk", 0.0))
	d.run = float(rec.get("run", 0.0))
	d.sel_z = float(rec.get("selZ", 0.0))
	d.weap1 = str(rec.get("weap1", "")).strip_edges()
	d.weap2 = str(rec.get("weap2", "")).strip_edges()
	d.team_color = int(rec.get("teamColor", 0))
	d.custom_team_color = int(rec.get("customTeamColor", 0)) != 0
	d.armor = str(rec.get("armor", "")).strip_edges()
	d.model_scale = float(rec.get("modelScale", 0.0))
	d.red = int(rec.get("red", 0))
	d.green = int(rec.get("green", 0))
	d.blue = int(rec.get("blue", 0))
	d.uber_splat = str(rec.get("uberSplat", "")).replace("\\", "/").strip_edges()
	d.unit_shadow = str(rec.get("unitShadow", "")).replace("\\", "/").strip_edges()
	d.building_shadow = str(rec.get("buildingShadow", "")).replace("\\", "/").strip_edges()
	d.shadow_w = float(rec.get("shadowW", 0.0))
	d.shadow_h = float(rec.get("shadowH", 0.0))
	d.shadow_x = float(rec.get("shadowX", 0.0))
	d.shadow_y = float(rec.get("shadowY", 0.0))
	d.shadow_on_water = int(rec.get("shadowOnWater", 0)) != 0
	d.sel_circ_on_water = int(rec.get("selCircOnWater", 0)) != 0
	d.occ_h = float(rec.get("occH", 0.0))
	d.in_beta = int(rec.get("InBeta", 0)) != 0
	return d

static func register_to(store: Node) -> void:
	if store == null or not store.has_method("register_table"):
		push_error("UnitUiDef: 无法注册到 DefStore")
		return
	store.register_table(TABLE_NAME, SLK_REL_PATH, PRIMARY_KEY, from_slk_record)
