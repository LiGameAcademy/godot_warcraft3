class_name BuildingCatalog
extends RefCounted

## F2 建筑 catalog：按 id 查造价/时间/占地/path_tex 等建造字段。
##
## 数据权威：Wc3DefStore（UnitBalance + UnitData）；本类不复制数据，只做便捷封装。
## 复用编辑器侧 Wc3IdCatalog.parse_path_tex_cells 解析 path_tex → footprint 格数。
##
## 跟 Wc3IdCatalog 区别：
## - Wc3IdCatalog：编辑器 UI 用（id → display + file + num_var + is_building）
## - BuildingCatalog：游戏建造管线用（id → 造价/时间/占地/path_tex 强类型接口）
##
## 人族竖切可造：Farm / Altar / Barracks / Lumber Mill / Blacksmith。
## 命令卡 = UnitFunc Builds ∩ 本表；科技升级建筑后置。

## 人族竖切可造建筑（Builds ∩ 本表）。
const VERTICAL_BUILDING_IDS := ["hhou", "halt", "hbar", "hlum", "hbla"]
## 兼容旧名（= VERTICAL_BUILDING_IDS）。
const F2_BUILDING_IDS := VERTICAL_BUILDING_IDS


## id 是否在 def 中存在（UnitBalance + UnitData 都有行）。
static func exists(building_id: String) -> bool:
	return _get_balance(building_id) != null and _get_data(building_id) != null


## 是否建筑（UnitBalance.isbldg=true）。
## 注意：isbldg 与"有 goldcost/path_tex"交叉判定；本类以 isbldg 为权威（与 WC3 对象编辑器一致）。
static func is_building(building_id: String) -> bool:
	var bal := _get_balance(building_id)
	return bal != null and bal.isbldg


## 建造金币消耗。
static func get_gold_cost(building_id: String) -> int:
	var bal := _get_balance(building_id)
	return bal.goldcost if bal != null else 0


## 建造木材消耗。
static func get_lumber_cost(building_id: String) -> int:
	var bal := _get_balance(building_id)
	return bal.lumbercost if bal != null else 0


## 建造时间（秒；读 bldtm；F2 不区分训练 vs 建造，统一 bldtm）。
static func get_build_time(building_id: String) -> float:
	var bal := _get_balance(building_id)
	return float(bal.bldtm) if bal != null else 0.0


## 完工后提供的人口上限（Farm=6；Altar/Barracks=0）。
## SLK 中 fmade 字段是字符串（"6" 或 " - "）；def 已 int() 解析，"- " → 0。
static func get_food_made(building_id: String) -> int:
	var bal := _get_balance(building_id)
	return bal.fmade if bal != null else 0


## 占用人口（建筑多为 0；金矿 / 中立建筑可能 > 0）。
static func get_food_used(building_id: String) -> int:
	var bal := _get_balance(building_id)
	return bal.fused if bal != null else 0


## 最大生命值。
static func get_hp(building_id: String) -> int:
	var bal := _get_balance(building_id)
	return bal.hp if bal != null else 0


## 修理金币（UnitBalance.goldRep；多工加速时额外消耗基准）。
static func get_gold_rep(building_id: String) -> int:
	var bal := _get_balance(building_id)
	if bal == null:
		return 0
	return bal.gold_rep if bal.gold_rep > 0 else bal.goldcost


## 修理木材。
static func get_lumber_rep(building_id: String) -> int:
	var bal := _get_balance(building_id)
	if bal == null:
		return 0
	return bal.lumber_rep if bal.lumber_rep > 0 else bal.lumbercost


## 修理时间基准（秒；UnitBalance.reptm；≤0 时回退 bldtm）。
static func get_repair_time(building_id: String) -> float:
	var bal := _get_balance(building_id)
	if bal == null:
		return 0.0
	if bal.reptm > 0:
		return float(bal.reptm)
	return float(bal.bldtm)


## 护甲类型（fort / small / medium / large / hero / divine / none）。
static func get_def_type(building_id: String) -> String:
	var bal := _get_balance(building_id)
	return bal.def_type if bal != null else ""


## path_tex 文件名（如 "PathTextures\4x4SimpleSolid.tga"）。
## 供 pathing 层 / PlacementGhost / 寻路合法性共用。
static func get_path_tex(building_id: String) -> String:
	var dat := _get_data(building_id)
	return dat.path_tex if dat != null else ""


## 占地格数（pathing 单元；path_tex 文件名 `WxH` 解析）。
## 例：hhou "4x4SimpleSolid.tga" → (4, 4)；halt "10x10Simple.tga" → (10, 10)。
## 无法解析（path_tex = "none" / 空）返回 (0, 0)。
static func get_footprint(building_id: String) -> Vector2i:
	return Wc3IdCatalog.parse_path_tex_cells(get_path_tex(building_id))


## 碰撞半径（WC3：UnitBalance.collision；用于非建筑 / 软分离）。
## 建筑选址以 footprint 为权威；此字段供 unit 间软分离（建筑周边 1 格避让）参考。
static func get_collision(building_id: String) -> float:
	var bal := _get_balance(building_id)
	return bal.collision if bal != null else 0.0


## UnitBalance.preventPlace（如 unbuildable / unwalkable；`_` = 无）。
static func get_prevent_place(building_id: String) -> String:
	var bal := _get_balance(building_id)
	return bal.prevent_place if bal != null else ""


## UnitBalance.requirePlace（如 blighted；`_` = 无）。
static func get_require_place(building_id: String) -> String:
	var bal := _get_balance(building_id)
	return bal.require_place if bal != null else ""


# --- 内部 ---

static func _get_balance(building_id: String) -> UnitBalanceDef:
	if building_id.is_empty():
		return null
	var store: Node = _get_def_store()
	if store == null:
		return null
	store.ensure_table(UnitBalanceDef.TABLE_NAME)
	return store.get_row(UnitBalanceDef.TABLE_NAME, building_id) as UnitBalanceDef


static func _get_data(building_id: String) -> UnitDataDef:
	if building_id.is_empty():
		return null
	var store: Node = _get_def_store()
	if store == null:
		return null
	store.ensure_table(UnitDataDef.TABLE_NAME)
	return store.get_row(UnitDataDef.TABLE_NAME, building_id) as UnitDataDef


static func _get_def_store() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Wc3DefStore")
