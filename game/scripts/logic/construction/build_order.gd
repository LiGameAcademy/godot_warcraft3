class_name BuildOrder
extends RefCounted

## F2 建造命令 data struct。
## 农民接到 BUILD Order：building_id + 工地 wc3_xy。
## BuildController.start_build 验证 + 扣资源 + 走向工地；到位后 F2-5 接管 timer。
##
## 状态机：
##   PENDING     → start_build 刚验过 + 扣资源
##   MOVING      → 农民走向工地
##   BUILDING    → 到位，开始建造（F2-5 接管）
##   CANCELLED   → 玩家取消（已退款 50%）
##   DONE        → 完工（F2-5 触发）

const STATE_PENDING := 0
const STATE_MOVING := 1
const STATE_BUILDING := 2
const STATE_CANCELLED := 3
const STATE_DONE := 4


## 工厂方法：构造一份 BUILD 命令。
## [param p_building_id] 4 字符建筑 id（hhou / halt / hbar）。
## [param p_site_wc3] 工地中心（WC3 XY）。
## [param p_builder] 接令农民（建造期间由 F2-5 隐藏 / 变工地）。
static func create(p_building_id: String, p_site_wc3: Vector2, p_builder: Node3D) -> BuildOrder:
	var o := BuildOrder.new()
	o.building_id = p_building_id
	o.site_wc3 = p_site_wc3
	o.builder = p_builder
	return o


## 4 字符建筑 id（hhou / halt / hbar）。
var building_id: String = ""
## 工地中心（WC3 坐标；footprint 围绕此点放置）。
var site_wc3: Vector2 = Vector2.INF
## 接令农民（建造期间由 F2-5 隐藏 / 变工地）。
var builder: Node3D = null
## 当前状态。
var state: int = STATE_PENDING
## 资源快照（取消时按 50% 退款）。
var gold_spent: int = 0
var lumber_spent: int = 0
## 建造总时长（秒；冗余存以便 UI 直接读，避免再查 BuildingCatalog）。
var build_time_sec: float = 0.0
