class_name ItemDef
extends Resource

## 物品静态定义（ItemData.slk 一行）。

const TABLE_NAME := "Items"
const SLK_REL_PATH := "Units/ItemData.json"
const PRIMARY_KEY := "itemID"

@export var item_id: String = ""				## 物品ID
@export var comment: String = ""				## 注释
@export var version: int = 0					## 版本
@export var item_class: String = ""				## 物品类型
@export var level: int = 0						## 等级	
@export var old_level: int = 0					## 旧等级
@export var abil_list: String = ""				## 技能列表
@export var cooldown_id: String = ""			## 冷却ID
@export var ignore_cd: bool = false				## 忽略冷却
@export var uses: int = 0						## 使用次数
@export var prio: int = 0						## 优先级	
@export var usable: bool = false				## 可使用
@export var perishable: bool = false			## 可消耗
@export var droppable: bool = true				## 可掉落
@export var pawnable: bool = true				## 可交换
@export var sellable: bool = true				## 可出售
@export var pick_random: bool = false			## 可随机
@export var powerup: bool = false				## 可强化
@export var drop: bool = false					## 可掉落
@export var stock_max: int = 0					## 库存最大
@export var stock_regen: int = 0				## 库存生成
@export var stock_start: int = 0				## 库存起始
@export var gold_cost: int = 0					## 金币消耗
@export var lumber_cost: int = 0				## 木材消耗
@export var hp: int = 0							## 生命值
@export var morph: bool = false					## 变形
@export var armor: String = ""					## 护甲
@export var file: String = ""					## 文件
@export var scale: float = 1.0					## 缩放
@export var color_r: int = 255					## 颜色R
@export var color_g: int = 255					## 颜色G
@export var color_b: int = 255					## 颜色B
@export var in_beta: bool = false				## 是否在Beta


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
