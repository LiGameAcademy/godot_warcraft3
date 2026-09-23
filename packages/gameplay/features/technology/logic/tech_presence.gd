class_name TechPresence
extends RefCounted

## 玩家已完工建筑/单位存在性（供 Requires 判定）。
## 升级链：需要 htow 时，hkee/hcas 也算满足（经典 Melee）。

## 人族竖切：祭坛训四英雄；兵营只训步兵/火枪手。
const VERTICAL_TRAINS := {
	"halt": ["Hamg", "Hmkg", "Hpal", "Hblm"],
	"hbar": ["hfoo", "hrif"],
	"htow": ["hpea"],
	"hkee": ["hpea"],
	"hcas": ["hpea"],
}

## 人族竖切：主城升本链。
const VERTICAL_BUILDING_UPGRADES := {
	"htow": "hkee",
	"hkee": "hcas",
}

## 人族竖切：兵营顶盾；铁匠武器/护甲（近战+远程各一条）。
const VERTICAL_RESEARCHES := {
	"hbar": ["Rhde"],
	"hbla": ["Rhme", "Rhar", "Rhla", "Rhra"],
}

## rarm 在 UpgradeData 里常为 "-"；经典人族护甲升级每级 +2。
const DEFAULT_RARM_PER_LEVEL := 2.0

## 对局会话弱引用：战斗/HUD 按 owner 查 PlayerStock 升级等级。
static var _session_ref: WeakRef = null

## Melee 简化：每位玩家同时场上英雄上限。
const MAX_HEROES_PER_PLAYER := 1

const _HERO_IDS := {
	"Hamg": true,
	"Hmkg": true,
	"Hpal": true,
	"Hblm": true,
}

## 需求 id → 可满足它的 typeId 集合（含自身）。
const _EQUIV := {
	"htow": ["htow", "hkee", "hcas"],
	"hkee": ["hkee", "hcas"],
	"hcas": ["hcas"],
}


static func is_hero_id(unit_id: String) -> bool:
	return bool(_HERO_IDS.get(unit_id.strip_edges(), false))


## MatchBootstrap / Director 开局后绑定；对局结束可传 null。
static func bind_session(session: GameSession) -> void:
	_session_ref = weakref(session) if session != null else null


static func bound_session() -> GameSession:
	if _session_ref == null:
		return null
	return _session_ref.get_ref() as GameSession


static func stock_for_owner(owner_id: int) -> PlayerStock:
	var session := bound_session()
	if session == null:
		return null
	return session.stocks.get(owner_id) as PlayerStock


static func stock_for_unit(unit: Node) -> PlayerStock:
	if unit == null or not is_instance_valid(unit):
		return null
	var d: Dictionary = unit.get_meta("unit_data", {})
	return stock_for_owner(int(d.get("owner", -1)))


## unit_host 下、指定 owner、已完工建筑的 typeId → 数量。
static func collect_owned_buildings(unit_host: Node, owner_id: int) -> Dictionary:
	var out: Dictionary = {}
	if unit_host == null:
		return out
	for c in unit_host.get_children():
		if not (c is Node3D) or not is_instance_valid(c):
			continue
		var node := c as Node3D
		var d: Dictionary = node.get_meta("unit_data", {})
		if int(d.get("owner", -1)) != owner_id:
			continue
		var tid := str(d.get("typeId", "")).strip_edges()
		if tid.is_empty() or not BuildingCatalog.is_building(tid):
			continue
		if bool(node.get_meta("under_construction", false)):
			continue
		out[tid] = int(out.get(tid, 0)) + 1
	return out


## 场上英雄数量（人族四英雄 id）。
static func count_heroes(unit_host: Node, owner_id: int) -> int:
	var n := 0
	if unit_host == null:
		return 0
	for c in unit_host.get_children():
		if not (c is Node3D) or not is_instance_valid(c):
			continue
		var d: Dictionary = (c as Node3D).get_meta("unit_data", {})
		if int(d.get("owner", -1)) != owner_id:
			continue
		var tid := str(d.get("typeId", "")).strip_edges()
		if _HERO_IDS.has(tid):
			n += 1
	return n


## 场上英雄 + 训练队列中的英雄 + 阵亡待复活（占英雄名额，对齐 WC3）。
static func count_heroes_with_queues(unit_host: Node, owner_id: int) -> int:
	var n := count_heroes(unit_host, owner_id)
	n += HeroDeathRegistry.dead_count(owner_id)
	if unit_host == null:
		return n
	for c in unit_host.get_children():
		if not (c is Node3D) or not is_instance_valid(c):
			continue
		var d: Dictionary = (c as Node3D).get_meta("unit_data", {})
		if int(d.get("owner", -1)) != owner_id:
			continue
		var q := (c as Node3D).get_node_or_null("TrainQueue") as TrainQueue
		if q == null:
			continue
		for e in q.snapshot():
			var uid := str((e as Dictionary).get("unit_id", ""))
			# 复活队列已从 DeathRegistry 取出，不再计入 dead_count，需在此补回
			if _HERO_IDS.has(uid):
				n += 1
	return n


static func is_upgrade_queued(unit_host: Node, owner_id: int, upgrade_id: String) -> bool:
	var want := upgrade_id.strip_edges()
	if unit_host == null or want.is_empty():
		return false
	for c in unit_host.get_children():
		if not (c is Node3D) or not is_instance_valid(c):
			continue
		var d: Dictionary = (c as Node3D).get_meta("unit_data", {})
		if int(d.get("owner", -1)) != owner_id:
			continue
		var q := (c as Node3D).get_node_or_null("TrainQueue") as TrainQueue
		if q == null:
			continue
		for e in q.snapshot():
			if str((e as Dictionary).get("unit_id", "")) == want:
				return true
	return false


## 玩家是否已满足 required_id（含升级链等价）。
static func owns_requirement(owned_buildings: Dictionary, required_id: String) -> bool:
	var rid := required_id.strip_edges()
	if rid.is_empty():
		return true
	var alts: Array = _EQUIV.get(rid, [rid])
	for a in alts:
		if int(owned_buildings.get(str(a), 0)) > 0:
			return true
	return false


## 未满足的 Requires 列表（保持原顺序）。
## researched：upgradeid→level；require_levels：upgradeid→最低等级（缺省 1）。
static func missing_requires(
	owned_buildings: Dictionary,
	requires: PackedStringArray,
	researched: Dictionary = {},
	require_levels: Dictionary = {}
) -> PackedStringArray:
	var out := PackedStringArray()
	for r in requires:
		var rid := str(r)
		var need := maxi(int(require_levels.get(rid, 1)), 1)
		if int(researched.get(rid, 0)) >= need:
			continue
		# 建筑类需求：仅当要求等级为 1 时可用场上建筑等价满足
		if need <= 1 and owns_requirement(owned_buildings, rid):
			continue
		out.append(rid)
	return out


## 竖切：建筑 Upgrade= ∩ 锁死表；无表则空（禁止非竖切升本）。
static func filter_vertical_building_upgrade(building_id: String, target_id: String) -> String:
	var from_id := building_id.strip_edges()
	var want := target_id.strip_edges()
	var allow = VERTICAL_BUILDING_UPGRADES.get(from_id, null)
	if allow == null:
		return ""
	if str(allow) != want:
		return ""
	return want


## UnitFunc Upgrade= 目标建筑 id（无则空）。
static func building_upgrade_target(building_id: String) -> String:
	var raw := str(CommandButtonCatalog.get_shared().get_unit_ui(building_id).get("upgrade", "")).strip_edges()
	if raw.is_empty() or raw == "_" or raw == "-":
		return ""
	# 偶发 CSV，只取首项
	var first := raw.split(",")[0].strip_edges()
	return filter_vertical_building_upgrade(building_id, first)


## 升本造价：目标总价 − 当前总价（对齐 Melee 差价；下限 0）。
static func building_upgrade_gold(from_id: String, to_id: String) -> int:
	return maxi(0, BuildingCatalog.get_gold_cost(to_id) - BuildingCatalog.get_gold_cost(from_id))


static func building_upgrade_lumber(from_id: String, to_id: String) -> int:
	return maxi(0, BuildingCatalog.get_lumber_cost(to_id) - BuildingCatalog.get_lumber_cost(from_id))


static func building_upgrade_time(to_id: String) -> float:
	return BuildingCatalog.get_build_time(to_id)


## 竖切：建筑 Trains ∩ 锁死表；无表则原样返回。
static func filter_vertical_trains(
	building_id: String, trains: PackedStringArray
) -> PackedStringArray:
	return _filter_vertical_ids(building_id, trains, VERTICAL_TRAINS)


## 竖切：建筑 Researches ∩ 锁死表；无表则原样返回。
static func filter_vertical_researches(
	building_id: String, researches: PackedStringArray
) -> PackedStringArray:
	return _filter_vertical_ids(building_id, researches, VERTICAL_RESEARCHES)


static func _filter_vertical_ids(
	building_id: String, ids: PackedStringArray, table: Dictionary
) -> PackedStringArray:
	var allow = table.get(building_id.strip_edges(), null)
	if allow == null:
		return ids
	var have: Dictionary = {}
	for t in ids:
		have[str(t)] = true
	var out := PackedStringArray()
	for a in allow:
		var id := str(a)
		if have.has(id):
			out.append(id)
	return out


## 显示名（命令卡 tip）；缺 Name 则回退 id。
static func display_name(unit_id: String) -> String:
	var cat := CommandButtonCatalog.get_shared()
	var row := cat.get_unit_ui(unit_id)
	var n := str(row.get("name", "")).strip_edges()
	if n.is_empty():
		row = cat.get_upgrade_ui(unit_id)
		n = str(row.get("name", "")).strip_edges()
	return n if not n.is_empty() else unit_id


static func requires_tip(missing: PackedStringArray) -> String:
	if missing.is_empty():
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for m in missing:
		parts.append(display_name(str(m)))
	return "需要：" + ", ".join(parts)


static func get_upgrade(upgrade_id: String) -> UpgradeDataDef:
	var uid := upgrade_id.strip_edges()
	if uid.is_empty():
		return null
	var store := _def_store()
	if store == null or not store.has_method("ensure_table") or not store.has_method("get_row"):
		return null
	store.ensure_table(UpgradeDataDef.TABLE_NAME)
	return store.get_row(UpgradeDataDef.TABLE_NAME, uid) as UpgradeDataDef


static func is_upgrade_id(upgrade_id: String) -> bool:
	return get_upgrade(upgrade_id) != null


static func upgrade_max_level(upgrade_id: String) -> int:
	var d := get_upgrade(upgrade_id)
	return maxi(d.maxlevel, 1) if d != null else 1


## 下一可研究等级；已满则 0。
static func upgrade_next_level(upgrade_id: String, current_level: int) -> int:
	var max_lv := upgrade_max_level(upgrade_id)
	var cur := maxi(current_level, 0)
	if cur >= max_lv:
		return 0
	return cur + 1


## 研究第 target_level 级的金价（1-based）。
static func upgrade_gold_at_level(upgrade_id: String, target_level: int) -> int:
	var d := get_upgrade(upgrade_id)
	if d == null:
		return 0
	var lv := maxi(target_level, 1)
	return int(round(d.goldbase + d.goldmod * float(lv - 1)))


static func upgrade_lumber_at_level(upgrade_id: String, target_level: int) -> int:
	var d := get_upgrade(upgrade_id)
	if d == null:
		return 0
	var lv := maxi(target_level, 1)
	return int(round(d.lumberbase + d.lumbermod * float(lv - 1)))


static func upgrade_time_at_level(upgrade_id: String, target_level: int) -> float:
	var d := get_upgrade(upgrade_id)
	if d == null:
		return 0.0
	var lv := maxi(target_level, 1)
	return d.timebase + d.timemod * float(lv - 1)


static func upgrade_gold(upgrade_id: String) -> int:
	return upgrade_gold_at_level(upgrade_id, 1)


static func upgrade_lumber(upgrade_id: String) -> int:
	return upgrade_lumber_at_level(upgrade_id, 1)


static func upgrade_time(upgrade_id: String) -> float:
	return upgrade_time_at_level(upgrade_id, 1)


## UpgradeFunc：Requires / Requires1 / Requires2 对应研究第 1/2/3 级的前置。
static func upgrade_requires_for_level(upgrade_id: String, target_level: int) -> PackedStringArray:
	var row := CommandButtonCatalog.get_shared().get_upgrade_ui(upgrade_id)
	var key := "requires"
	var lv := maxi(target_level, 1)
	if lv >= 2:
		key = "requires%d" % (lv - 1)
	return _split_csv_ids(str(row.get(key, "")))


## 单级效果值：inherit=0 时 total = base+(level-1)*mod；护甲缺省按每级 +2。
static func upgrade_effect_bonus(upgrade_id: String, level: int) -> Dictionary:
	## {effect: String, amount: float}
	var empty := {"effect": "", "amount": 0.0}
	var d := get_upgrade(upgrade_id)
	if d == null or level <= 0:
		return empty
	var effect := str(d.effect1).strip_edges().to_lower()
	if effect.is_empty() or effect == "_" or effect == "-":
		return empty
	var base := d.base1
	var mod := d.mod1
	# SLK 里 "-" 被 float() 成 0；rarm 用经典默认。
	if effect == "rarm" and absf(base) < 0.0001 and absf(mod) < 0.0001:
		base = DEFAULT_RARM_PER_LEVEL
		mod = DEFAULT_RARM_PER_LEVEL
	var amount := base + float(level - 1) * mod
	if d.inherit:
		# 累加各级：Σ(base+(i-1)*mod)
		amount = 0.0
		for i in range(1, level + 1):
			var b := base
			var m := mod
			if effect == "rarm" and absf(d.base1) < 0.0001 and absf(d.mod1) < 0.0001:
				b = DEFAULT_RARM_PER_LEVEL
				m = DEFAULT_RARM_PER_LEVEL
			amount += b + float(i - 1) * m
	return {"effect": effect, "amount": amount}


## 单位 UnitBalance.upgrades 中与 researched 匹配的攻击骰伤加成（ratd）。
static func unit_attack_bonus(unit: Node) -> float:
	return _unit_effect_bonus(unit, "ratd")


## 单位护甲科技加成（rarm）。
static func unit_armor_bonus(unit: Node) -> float:
	return _unit_effect_bonus(unit, "rarm")


## 单位当前适用的攻击/护甲科技等级（取匹配 id 中最高已研究等级；无则 0）。
static func unit_upgrade_level(unit: Node, id_set: Dictionary) -> int:
	var bal := _balance_of(unit)
	var stock := stock_for_unit(unit)
	if bal == null or stock == null:
		return 0
	var best := 0
	for part in str(bal.upgrades).split(",", false):
		var id := str(part).strip_edges()
		if id.is_empty() or id == "_" or id == "-":
			continue
		if not id_set.has(id):
			continue
		best = maxi(best, stock.upgrade_level(id))
	return best


static func _unit_effect_bonus(unit: Node, want_effect: String) -> float:
	var bal := _balance_of(unit)
	var stock := stock_for_unit(unit)
	if bal == null or stock == null:
		return 0.0
	var total := 0.0
	var want := want_effect.strip_edges().to_lower()
	for part in str(bal.upgrades).split(",", false):
		var id := str(part).strip_edges()
		if id.is_empty() or id == "_" or id == "-":
			continue
		var lv := stock.upgrade_level(id)
		if lv <= 0:
			continue
		var fx := upgrade_effect_bonus(id, lv)
		if str(fx.get("effect", "")) == want:
			total += float(fx.get("amount", 0.0))
	return total


## 避免 TechPresence ↔ CombatQuery 循环 class_name 依赖（会拖垮选中/建造等全图逻辑）。
static func _balance_of(unit: Node) -> UnitBalanceDef:
	if unit == null or not is_instance_valid(unit):
		return null
	var d: Dictionary = unit.get_meta("unit_data", {})
	var tid := str(d.get("typeId", "")).strip_edges()
	if tid.is_empty():
		return null
	var store := _def_store()
	if store == null or not store.has_method("ensure_table") or not store.has_method("get_row"):
		return null
	store.ensure_table(UnitBalanceDef.TABLE_NAME)
	return store.get_row(UnitBalanceDef.TABLE_NAME, tid) as UnitBalanceDef


static func _split_csv_ids(raw: String) -> PackedStringArray:
	var out := PackedStringArray()
	var s := raw.strip_edges()
	if s.is_empty() or s == "_" or s == "-":
		return out
	for part in s.split(",", false):
		var id := str(part).strip_edges()
		if not id.is_empty() and id != "_" and id != "-":
			out.append(id)
	return out


static func _def_store() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Wc3DefStore")
