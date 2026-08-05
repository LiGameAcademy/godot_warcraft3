class_name UpgradeDataDef
extends Resource

## Units/UpgradeData.slk 一行定义。
##
## 职责：科技升级（造价/时间随等级、最多四级效果 effect/base/mod/code）。

const TABLE_NAME := "UpgradeData"
const SLK_REL_PATH := "Units/UpgradeData.json"
const PRIMARY_KEY := "upgradeid"

@export var upgradeid: String = "" ## 主键（四字符升级 ID）
@export var comment: String = "" ## 人类可读备注
@export var class_kind: String = "" ## 升级分类（class；编辑器分组）
@export var race: String = "" ## 所属种族
@export var sort_key: String = "" ## 编辑器排序键
@export var used: bool = false ## 是否在游戏中启用
@export var is_global: bool = false ## 是否为全局升级（影响全图/全队规则）
@export var maxlevel: int = 0 ## 最大可研究等级
@export var inherit: bool = false ## 是否继承前一级效果
@export var goldbase: float = 0.0 ## 1 级金币消耗
@export var goldmod: float = 0.0 ## 每升一级追加的金币
@export var lumberbase: float = 0.0 ## 1 级木材消耗
@export var lumbermod: float = 0.0 ## 每升一级追加的木材
@export var timebase: float = 0.0 ## 1 级研究时间（秒）
@export var timemod: float = 0.0 ## 每升一级追加的研究时间
@export var effect1: String = "" ## 效果 1 类型（如 rarm / ratd；见 UpgradeEffectMetaData）
@export var base1: float = 0.0 ## 效果 1 基础值
@export var mod1: float = 0.0 ## 效果 1 每级增量
@export var code1: String = "" ## 效果 1 目标码（单位/技能等 ID）
@export var effect2: String = "" ## 效果 2 类型
@export var base2: float = 0.0 ## 效果 2 基础值
@export var mod2: float = 0.0 ## 效果 2 每级增量
@export var code2: String = "" ## 效果 2 目标码
@export var effect3: String = "" ## 效果 3 类型
@export var base3: float = 0.0 ## 效果 3 基础值
@export var mod3: float = 0.0 ## 效果 3 每级增量
@export var code3: String = "" ## 效果 3 目标码
@export var effect4: String = "" ## 效果 4 类型
@export var base4: float = 0.0 ## 效果 4 基础值
@export var mod4: float = 0.0 ## 效果 4 每级增量
@export var code4: String = "" ## 效果 4 目标码
@export var version: int = 0 ## 数据版本标记
@export var in_beta: bool = false ## 是否属于 RoC（非 TFT）数据标记

## 显示名：优先 comment/name，否则主键。
func display_name() -> String:
	var c := comment.strip_edges()
	return c if not c.is_empty() and c != "_" else upgradeid

static func from_slk_record(rec: Dictionary) -> UpgradeDataDef:
	var d := UpgradeDataDef.new()
	d.upgradeid = str(rec.get("upgradeid", "")).strip_edges()
	d.comment = str(rec.get("comments", "")).strip_edges()
	d.class_kind = str(rec.get("class", "")).strip_edges()
	d.race = str(rec.get("race", "")).strip_edges()
	d.sort_key = str(rec.get("sort", "")).strip_edges()
	d.used = int(rec.get("used", 0)) != 0
	d.is_global = int(rec.get("global", 0)) != 0
	d.maxlevel = int(rec.get("maxlevel", 0))
	d.inherit = int(rec.get("inherit", 0)) != 0
	d.goldbase = float(rec.get("goldbase", 0.0))
	d.goldmod = float(rec.get("goldmod", 0.0))
	d.lumberbase = float(rec.get("lumberbase", 0.0))
	d.lumbermod = float(rec.get("lumbermod", 0.0))
	d.timebase = float(rec.get("timebase", 0.0))
	d.timemod = float(rec.get("timemod", 0.0))
	d.effect1 = str(rec.get("effect1", "")).strip_edges()
	d.base1 = float(rec.get("base1", 0.0))
	d.mod1 = float(rec.get("mod1", 0.0))
	d.code1 = str(rec.get("code1", "")).strip_edges()
	d.effect2 = str(rec.get("effect2", "")).strip_edges()
	d.base2 = float(rec.get("base2", 0.0))
	d.mod2 = float(rec.get("mod2", 0.0))
	d.code2 = str(rec.get("code2", "")).strip_edges()
	d.effect3 = str(rec.get("effect3", "")).strip_edges()
	d.base3 = float(rec.get("base3", 0.0))
	d.mod3 = float(rec.get("mod3", 0.0))
	d.code3 = str(rec.get("code3", "")).strip_edges()
	d.effect4 = str(rec.get("effect4", "")).strip_edges()
	d.base4 = float(rec.get("base4", 0.0))
	d.mod4 = float(rec.get("mod4", 0.0))
	d.code4 = str(rec.get("code4", "")).strip_edges()
	d.version = int(rec.get("version", 0))
	d.in_beta = int(rec.get("InBeta", 0)) != 0
	return d

static func register_to(store: Node) -> void:
	if store == null or not store.has_method("register_table"):
		push_error("UpgradeDataDef: 无法注册到 DefStore")
		return
	store.register_table(TABLE_NAME, SLK_REL_PATH, PRIMARY_KEY, from_slk_record)
