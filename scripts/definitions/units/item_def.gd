class_name ItemDef
extends Resource

## 物品静态定义（ItemData.slk 一行）。

const TABLE_NAME := "Items"
const SLK_REL_PATH := "Units/ItemData.json"
const PRIMARY_KEY := "itemID"

@export var item_id: String = ""
@export var comment: String = ""
@export var version: int = 0
@export var item_class: String = ""
@export var level: int = 0
@export var old_level: int = 0
@export var abil_list: String = ""
@export var cooldown_id: String = ""
@export var ignore_cd: bool = false
@export var uses: int = 0
@export var prio: int = 0
@export var usable: bool = false
@export var perishable: bool = false
@export var droppable: bool = true
@export var pawnable: bool = true
@export var sellable: bool = true
@export var pick_random: bool = false
@export var powerup: bool = false
@export var drop: bool = false
@export var stock_max: int = 0
@export var stock_regen: int = 0
@export var stock_start: int = 0
@export var gold_cost: int = 0
@export var lumber_cost: int = 0
@export var hp: int = 0
@export var morph: bool = false
@export var armor: String = ""
@export var file: String = ""
@export var scale: float = 1.0
@export var color_r: int = 255
@export var color_g: int = 255
@export var color_b: int = 255
@export var in_beta: bool = false


## 显示名：优先 comment，否则 item_id。
func display_name() -> String:
	var c := comment.strip_edges()
	return c if not c.is_empty() else item_id


static func from_slk_record(rec: Dictionary) -> ItemDef:
	var d := ItemDef.new()
	d.item_id = str(rec.get("itemID", "")).strip_edges()
	d.comment = str(rec.get("comment", "")).strip_edges()
	d.version = int(rec.get("version", 0))
	d.item_class = str(rec.get("class", "")).strip_edges()
	d.level = int(rec.get("Level", 0))
	d.old_level = int(rec.get("oldLevel", 0))
	d.abil_list = str(rec.get("abilList", "")).strip_edges()
	d.cooldown_id = str(rec.get("cooldownID", "")).strip_edges()
	d.ignore_cd = int(rec.get("ignoreCD", 0)) != 0
	d.uses = int(rec.get("uses", 0))
	d.prio = int(rec.get("prio", 0))
	d.usable = int(rec.get("usable", 0)) != 0
	d.perishable = int(rec.get("perishable", 0)) != 0
	d.droppable = int(rec.get("droppable", 1)) != 0
	d.pawnable = int(rec.get("pawnable", 1)) != 0
	d.sellable = int(rec.get("sellable", 1)) != 0
	d.pick_random = int(rec.get("pickRandom", 0)) != 0
	d.powerup = int(rec.get("powerup", 0)) != 0
	d.drop = int(rec.get("drop", 0)) != 0
	d.stock_max = int(rec.get("stockMax", 0))
	d.stock_regen = int(rec.get("stockRegen", 0))
	d.stock_start = int(rec.get("stockStart", 0))
	d.gold_cost = int(rec.get("goldcost", 0))
	d.lumber_cost = int(rec.get("lumbercost", 0))
	d.hp = int(rec.get("HP", 0))
	d.morph = int(rec.get("morph", 0)) != 0
	d.armor = str(rec.get("armor", "")).strip_edges()
	d.file = str(rec.get("file", "")).replace("\\", "/").strip_edges()
	d.scale = float(rec.get("scale", 1.0))
	d.color_r = int(rec.get("colorR", 255))
	d.color_g = int(rec.get("colorG", 255))
	d.color_b = int(rec.get("colorB", 255))
	d.in_beta = int(rec.get("InBeta", 0)) != 0
	return d


static func register_to(store: Node) -> void:
	if store == null or not store.has_method("register_table"):
		push_error("ItemDef: 无法注册到 DefStore")
		return
	store.register_table(TABLE_NAME, SLK_REL_PATH, PRIMARY_KEY, from_slk_record)
