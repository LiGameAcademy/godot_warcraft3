class_name ItemDef
extends Resource

## Units/ItemData.slk 一行定义。
##
## 职责：物品静态数据（分类、等级、技能、冷却、库存、造价、模型与染色等）。

const TABLE_NAME := "Items"
const SLK_REL_PATH := "Units/ItemData.json"
const PRIMARY_KEY := "itemID"

@export var item_id: String = "" ## 主键（四字符物品 ID）
@export var comment: String = "" ## 人类可读备注（常作显示名回退）
@export var version: int = 0 ## 数据版本标记
@export var item_class: String = "" ## 物品分类：Permanent / Charged / PowerUp / Artifact…
@export var level: int = 0 ## 物品等级（商店分层/掉落权重）
@export var old_level: int = 0 ## 旧版等级字段（兼容）
@export var abil_list: String = "" ## 物品携带的技能 ID 列表（逗号分隔）
@export var cooldown_id: String = "" ## 共享冷却组 ID（同组物品共用 CD）
@export var ignore_cd: bool = false ## 是否忽略冷却
@export var uses: int = 0 ## 使用次数（0 常表示无限/非充能）
@export var prio: int = 0 ## AI 拾取/使用优先级
@export var usable: bool = false ## 是否为主动可使用物品
@export var perishable: bool = false ## 用完是否消失（消耗品）
@export var droppable: bool = true ## 是否可主动丢弃
@export var pawnable: bool = true ## 是否可抵押给商店
@export var sellable: bool = true ## 是否可出售
@export var pick_random: bool = false ## 是否可出现在随机掉落池
@export var powerup: bool = false ## 是否为拾取即生效类（Powerup）
@export var drop: bool = false ## 持有者死亡时是否掉落
@export var stock_max: int = 0 ## 商店最大库存
@export var stock_regen: int = 0 ## 库存补充间隔（秒）
@export var stock_start: int = 0 ## 开局库存
@export var gold_cost: int = 0 ## 购买金币价格
@export var lumber_cost: int = 0 ## 购买木材价格
@export var hp: int = 0 ## 物品「生命」（可被攻击的物品/可破坏物）
@export var morph: bool = false ## 是否会变形/切换形态
@export var armor: String = "" ## 受击护甲音效类型
@export var file: String = "" ## 地面模型路径
@export var scale: float = 1.0 ## 模型缩放
@export var color_r: int = 255 ## 染色 R（0–255）
@export var color_g: int = 255 ## 染色 G
@export var color_b: int = 255 ## 染色 B
@export var in_beta: bool = false ## 是否属于 RoC（非 TFT）数据标记


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
