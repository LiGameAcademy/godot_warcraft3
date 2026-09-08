class_name CombatQuery
extends RefCounted

## 敌对 / 射程 / 索敌 / 合法攻击目标（Logic · 纯查询）。

const NEUTRAL_OWNER_MIN := 12			## 中立 owner 最小 ID

## 获取单位所有者
static func owner_of(node: Node) -> int:
	if node == null or not is_instance_valid(node):
		return -1
	var d: Dictionary = node.get_meta("unit_data", {})
	return int(d.get("owner", -1))

## 获取单位类型 ID
static func type_id_of(node: Node) -> String:
	if node == null or not is_instance_valid(node):
		return ""
	var d: Dictionary = node.get_meta("unit_data", {})
	return str(d.get("typeId", "")).strip_edges()

## 是否中立所有者
static func is_neutral_owner(owner_id: int) -> bool:
	return owner_id >= NEUTRAL_OWNER_MIN or owner_id < 0


## 本地玩家是否可对该单位下达指令（点选仍可观察非己方）。
static func is_controllable(node: Node, local_player: int) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var oid := owner_of(node)
	if is_neutral_owner(oid):
		return false
	return oid == local_player


## 仍在场且存活（非尸体）：命令 / 移动过滤用。
static func is_alive_in_world(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if not WorldMembership.is_in_world(node):
		return false
	if node is Node3D:
		var body := node as Node3D
		if _current_life(body) <= 0.0:
			return false
		var vis := Unit.of(body)
		if vis != null and vis.is_dying():
			return false
	return true


## 获取单位平衡定义
static func balance_of(node: Node) -> UnitBalanceDef:
	var tid := type_id_of(node)
	if tid.is_empty():
		return null
	var store := _def_store()
	if store == null:
		return null
	store.ensure_table(UnitBalanceDef.TABLE_NAME)
	return store.get_row(UnitBalanceDef.TABLE_NAME, tid) as UnitBalanceDef

## 获取单位 UnitData 定义。
static func unit_data_of(node: Node) -> UnitDataDef:
	var tid := type_id_of(node)
	if tid.is_empty():
		return null
	var store := _def_store()
	if store == null:
		return null
	store.ensure_table(UnitDataDef.TABLE_NAME)
	return store.get_row(UnitDataDef.TABLE_NAME, tid) as UnitDataDef


## 获取单位武器定义
static func weapons_of(node: Node) -> UnitWeaponsDef:
	var tid := type_id_of(node)
	if tid.is_empty():
		return null
	var store := _def_store()
	if store == null:
		return null
	store.ensure_table(UnitWeaponsDef.TABLE_NAME)
	return store.get_row(UnitWeaponsDef.TABLE_NAME, tid) as UnitWeaponsDef

## 获取定义存储
static func _def_store() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Wc3DefStore")

## 是否有武器
static func has_weapon(node: Node) -> bool:
	var w := weapons_of(node)
	if w == null:
		return false
	if w.weaps_on != 0:
		return true
	return w.dice1 > 0 or w.dmgplus1 > 0.0 or w.avgdmg1 > 0.0

## 获取攻击范围
static func attack_range_wc3(node: Node) -> float:
	var w := weapons_of(node)
	if w == null:
		return 100.0
	return maxf(w.range_n1, 16.0)

## 获取范围缓冲
static func range_buff_wc3(node: Node) -> float:
	var w := weapons_of(node)
	if w == null:
		return 0.0
	return maxf(w.rng_buff1, 0.0)

## 获取获取范围
static func acquire_range_wc3(node: Node) -> float:
	var w := weapons_of(node)
	if w == null:
		return 500.0
	return maxf(w.acquire, attack_range_wc3(node))

## 获取冷却时间
static func cooldown_sec(node: Node) -> float:
	var w := weapons_of(node)
	if w == null:
		return 1.5
	return maxf(w.cool1, 0.1)

## 伤害点（攻击开始后多久结算伤害，秒）。
static func damage_point_sec(node: Node) -> float:
	var w := weapons_of(node)
	if w == null:
		return 0.0
	var cool := maxf(w.cool1, 0.1)
	return clampf(w.dmgpt1, 0.0, cool)


## 武器弹道类型字符串（weapTp1）。
static func weapon_tp(node: Node) -> String:
	var w := weapons_of(node)
	if w == null:
		return ""
	return w.weap_tp1.strip_edges().to_lower()


## 投送分类：instant（含 normal）/ missile（含 bounce·splash·line）/ artillery。
enum Delivery {
	INSTANT = 0,
	MISSILE = 1,
	ARTILLERY = 2,
}


## 由 weapTp 字符串分类（无 DefStore 也可测）。
static func classify_weap_tp(tp: String) -> int:
	var t := tp.strip_edges().to_lower()
	if t.is_empty() or t == "_" or t == "-" or t == "instant" or t == "normal":
		return Delivery.INSTANT
	if t == "artillery" or t == "aline":
		return Delivery.ARTILLERY
	# missile / mbounce / msplash / mline / …
	if t.begins_with("m") or t == "missile":
		return Delivery.MISSILE
	return Delivery.INSTANT


static func delivery_kind(node: Node) -> int:
	return classify_weap_tp(weapon_tp(node))


## Logic 是否等弹道飞行后再 DamagePipeline（真 missile；instant 火枪仍 dmgpt 瞬时伤）。
static func uses_projectile_travel(node: Node) -> bool:
	return delivery_kind(node) == Delivery.MISSILE


## Present 是否需要弹道壳（远程手感；含 hrif 的 instant）。
static func wants_projectile_visual(node: Node) -> bool:
	if uses_projectile_travel(node):
		return true
	return attack_range_wc3(node) >= 200.0


## UnitFunc 行（CommandButtonCatalog；键已小写）。
static func unit_func_row(type_id: String) -> Dictionary:
	var tid := type_id.strip_edges()
	if tid.is_empty():
		return {}
	return CommandButtonCatalog.get_shared().get_unit_ui(tid)


## WC3 Missileart/模型路径 → asset-converted 相对逻辑路径（.gltf）。
static func normalize_model_art(raw: String) -> String:
	var p := raw.strip_edges().replace("\\", "/")
	if p.is_empty():
		return ""
	while p.begins_with("/"):
		p = p.substr(1)
	var lower := p.to_lower()
	if lower.ends_with(".mdl") or lower.ends_with(".mdx"):
		p = p.substr(0, p.length() - 4) + ".gltf"
	elif lower.ends_with(".blp"):
		p = p.substr(0, p.length() - 4) + ".png"
	return p


static func _unit_func_missile_art_raw(type_id: String) -> String:
	var row := unit_func_row(type_id)
	return str(row.get("missileart", "")).strip_edges()


## 真 missile 飞行模型（Hamg→FireBall）。instant 远程为空（飞的是空，命中用 impact）。
## 真 missile 飞行模型（Hamg→FireBall）。instant 远程也可能带 Missileart 作飞弹壳。
static func weapon_missile_art(node: Node) -> String:
	return missile_art_for_type(type_id_of(node))


static func missile_art_for_type(type_id: String) -> String:
	var art := normalize_model_art(_unit_func_missile_art_raw(type_id))
	if not art.is_empty():
		return art
	# 兜底：经典大法师火球
	if type_id.strip_edges() == "Hamg":
		return "Abilities/Weapons/FireBallMissile/FireBallMissile.gltf"
	return ""


## 命中特效：instant 远程用 Missileart 作 Impact；真 missile 到点也播同款 Birth/命中。
static func weapon_impact_art(node: Node) -> String:
	var tid := type_id_of(node)
	if uses_projectile_travel(node):
		return missile_art_for_type(tid)
	return impact_art_for_type(tid)


static func impact_art_for_type(type_id: String) -> String:
	var art := normalize_model_art(_unit_func_missile_art_raw(type_id))
	if not art.is_empty():
		return art
	if _IMPACT_ART_BY_TYPE.has(type_id):
		return str(_IMPACT_ART_BY_TYPE[type_id])
	return ""


## 是否用可见曳光/飞弹体（真 missile 或带 Missileart 的 instant 远程）。
static func wants_tracer_visual(node: Node) -> bool:
	if uses_projectile_travel(node):
		return true
	if not weapon_missile_art(node).is_empty():
		return true
	return wants_projectile_visual(node)


## 弹道速度（WC3 单位/秒）：UnitFunc.Missilespeed → 兜底表 → 默认。
const DEFAULT_MISSILE_SPEED_WC3 := 900.0
const _MISSILE_SPEED_BY_TYPE := {
	"hrif": 1900.0,
	"Hamg": 900.0,
	"earc": 900.0,
	"esen": 900.0,
}


static func missile_speed_wc3(node: Node) -> float:
	return missile_speed_for_type(type_id_of(node))


static func missile_speed_for_type(type_id: String) -> float:
	var tid := type_id.strip_edges()
	var row := unit_func_row(tid)
	var raw := str(row.get("missilespeed", "")).strip_edges()
	if not raw.is_empty() and raw.is_valid_float():
		var s := float(raw)
		if s > 1.0:
			return s
	if _MISSILE_SPEED_BY_TYPE.has(tid):
		return float(_MISSILE_SPEED_BY_TYPE[tid])
	return DEFAULT_MISSILE_SPEED_WC3


## 弹道弧度（UnitFunc.Missilearc；0=平直）。Present 可用，Logic 飞时仍按直线时长。
static func missile_arc(node: Node) -> float:
	return missile_arc_for_type(type_id_of(node))


static func missile_arc_for_type(type_id: String) -> float:
	var row := unit_func_row(type_id)
	var raw := str(row.get("missilearc", "")).strip_edges()
	if raw.is_empty() or not raw.is_valid_float():
		return 0.0
	return clampf(float(raw), 0.0, 1.0)


## 兼容旧硬编码命中表（UnitFunc 缺失时）。
const _IMPACT_ART_BY_TYPE := {
	"hrif": "Abilities/Weapons/Rifle/RifleImpact.gltf",
}


static func travel_time_sec(dist_wc3: float, speed_wc3: float) -> float:
	return maxf(dist_wc3, 0.0) / maxf(speed_wc3, 1.0)


## 发射点（相对单位原点的 WC3 偏移；高度用 launch_z）。
static func launch_offset_wc3(node: Node) -> Vector3:
	var w := weapons_of(node)
	if w == null:
		return Vector3(0.0, 0.0, 60.0)
	return Vector3(w.launch_x, w.launch_y, maxf(w.launch_z, 40.0))


static func impact_z_wc3(node: Node) -> float:
	var w := weapons_of(node)
	if w == null:
		return 60.0
	return maxf(w.impact_z, 40.0)


static func min_attack_range_wc3(node: Node) -> float:
	var w := weapons_of(node)
	if w == null:
		return 0.0
	return maxf(w.min_range, 0.0)

## 获取距离
static func distance_wc3(a: Node3D, b: Node3D) -> float:
	if a == null or b == null:
		return INF
	var pa := Wc3Coords.godot_to_wc3_xy(a.global_position)
	var pb := Wc3Coords.godot_to_wc3_xy(b.global_position)
	return pa.distance_to(pb)

## 是否在出手射程内。
## 只用 range_n1（+ hysteresis）；RngBuff1 是追击/保持交战容差，不能整段加进出手判定
## （步兵 range=90、buff=250 → 误判成 340）。
## min_range>0 时过近不可打（竖切多数单位为 0）。
static func in_attack_range(attacker: Node3D, target: Node3D, hysteresis: float = 0.0) -> bool:
	var d := distance_wc3(attacker, target)
	var lim := attack_range_wc3(attacker) + hysteresis
	if d > lim:
		return false
	var min_r := min_attack_range_wc3(attacker)
	if min_r > 0.0 and d + hysteresis < min_r:
		return false
	return true


## 是否仍处于交战距离（出手射程 + RngBuff；用于冷却中不立刻取消、Hold 近距索敌等）。
static func in_engage_range(attacker: Node3D, target: Node3D, hysteresis: float = 0.0) -> bool:
	var lim := attack_range_wc3(attacker) + range_buff_wc3(attacker) + hysteresis
	return distance_wc3(attacker, target) <= lim


## 双方是否敌对（竖切简化）。
static func is_hostile(a: Node, b: Node) -> bool:
	if a == null or b == null or a == b:
		return false
	if not is_instance_valid(a) or not is_instance_valid(b):
		return false
	var oa := owner_of(a)
	var ob := owner_of(b)
	if oa == ob:
		return false
	if is_neutral_owner(oa) and is_neutral_owner(ob):
		return false
	return true


## 可受伤的攻击目标基础过滤（不含敌对判定）。
static func _attack_target_basics(attacker: Node, target: Node) -> bool:
	if attacker == null or target == null or attacker == target:
		return false
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return false
	if not WorldMembership.is_in_world(target):
		return false
	if target is Node3D and _current_life(target as Node3D) <= 0.0:
		return false
	var tid := type_id_of(target)
	if tid == "ngol" or tid == "sloc":
		return false
	return true


## 优先读 life meta（入场已 ensure）；避免测试期 UnitLife 类缓存未就绪时崩溃。
static func _current_life(node: Node3D) -> float:
	if node == null:
		return 0.0
	if node.has_meta("life"):
		return float(node.get_meta("life"))
	return UnitLife.get_life(node)


## 显式 Attack 合法目标（含友军强制攻击，对齐 WC3 A 点单位）。
static func is_valid_attack_target(attacker: Node, target: Node) -> bool:
	if not _attack_target_basics(attacker, target):
		return false
	if is_hostile(attacker, target):
		return true
	# 同玩家友军（含未完工己方建筑）
	var oa := owner_of(attacker)
	return oa >= 0 and oa == owner_of(target)


## 友军技能合法目标（治疗 / buff）。不含 SLK targs；优先用 is_valid_ability_unit_target。
static func is_valid_ally_spell_target(caster: Node, target: Node) -> bool:
	if caster == null or target == null:
		return false
	if not is_instance_valid(caster) or not is_instance_valid(target):
		return false
	if not _attack_target_basics(caster, target):
		return false
	var oa := owner_of(caster)
	return oa >= 0 and oa == owner_of(target)


## 点目标技能合法目标：基础过滤 + AbilityData.targs。
static func is_valid_ability_unit_target(caster: Node, target: Node, abil_id: String) -> bool:
	if caster == null or target == null:
		return false
	if not is_instance_valid(caster) or not is_instance_valid(target):
		return false
	# 自疗/自拍：_attack_target_basics 排除 self，改由 targs 的 self 决定。
	if caster == target:
		if not WorldMembership.is_in_world(target):
			return false
		if target is Node3D and _current_life(target as Node3D) <= 0.0:
			return false
		return AbilityTargetFilter.matches(caster, target, abil_id)
	if not _attack_target_basics(caster, target):
		return false
	return AbilityTargetFilter.matches(caster, target, abil_id)


## 敌军技能合法目标（减速 / 风暴之锤等）。不含 SLK targs；优先用 is_valid_ability_unit_target。
static func is_valid_hostile_spell_target(caster: Node, target: Node) -> bool:
	return is_auto_acquire_target(caster, target)


## 自动索敌 / 智能右键：仅敌对（不强制打友军）。
static func is_auto_acquire_target(attacker: Node, target: Node) -> bool:
	return _attack_target_basics(attacker, target) and is_hostile(attacker, target)


## 圆心 WC3 + 半径内、对 attacker 敌对的 Node3D 单位。
static func units_hostile_in_radius(
	unit_host: Node,
	attacker: Node3D,
	center_wc3: Vector2,
	radius_wc3: float
) -> Array:
	var out: Array = []
	if unit_host == null or attacker == null or center_wc3 == Vector2.INF:
		return out
	var r := maxf(radius_wc3, 0.0)
	for c in unit_host.get_children():
		if not (c is Node3D) or not is_instance_valid(c):
			continue
		var node := c as Node3D
		if not is_auto_acquire_target(attacker, node):
			continue
		var pos := Wc3Coords.godot_to_wc3_xy(node.global_position)
		if pos.distance_to(center_wc3) <= r:
			out.append(node)
	return out


## 单位碰撞半径（UnitBalance.collision）；建筑占地大，AOE 必须扣半径。
static func collision_radius_wc3(node: Node) -> float:
	var bal := balance_of(node)
	if bal != null and bal.collision > 0.0:
		return bal.collision
	return 16.0


## 技能 AOE 可受伤目标（不分敌我；对齐暴风雪等友伤）。
static func is_valid_spell_aoe_target(caster: Node, target: Node) -> bool:
	return _attack_target_basics(caster, target)


## 暴风雪等：半径内所有可受伤目标（不分敌我，含建筑；距离扣碰撞半径）。
static func units_blizzard_victims_in_radius(
	unit_host: Node,
	caster: Node3D,
	center_wc3: Vector2,
	radius_wc3: float
) -> Array:
	var out: Array = []
	if unit_host == null or caster == null or center_wc3 == Vector2.INF:
		return out
	var r := maxf(radius_wc3, 0.0)
	for c in unit_host.get_children():
		if not (c is Node3D) or not is_instance_valid(c):
			continue
		var node := c as Node3D
		if not is_valid_spell_aoe_target(caster, node):
			continue
		var pos := Wc3Coords.godot_to_wc3_xy(node.global_position)
		var col := collision_radius_wc3(node)
		if pos.distance_to(center_wc3) - col <= r:
			out.append(node)
	return out


## 圆心 WC3 + 半径内、与 provider 同玩家的友方 Node3D（含自身）。
static func units_friendly_in_radius(
	unit_host: Node,
	provider: Node3D,
	center_wc3: Vector2,
	radius_wc3: float
) -> Array:
	var out: Array = []
	if unit_host == null or provider == null or center_wc3 == Vector2.INF:
		return out
	var owner := owner_of(provider)
	if owner < 0:
		return out
	var r := maxf(radius_wc3, 0.0)
	for c in unit_host.get_children():
		if not (c is Node3D) or not is_instance_valid(c):
			continue
		var node := c as Node3D
		if owner_of(node) != owner:
			continue
		if not _attack_target_basics(provider, node) and node != provider:
			continue
		if node != provider and is_hostile(provider, node):
			continue
		var pos := Wc3Coords.godot_to_wc3_xy(node.global_position)
		if pos.distance_to(center_wc3) <= r:
			out.append(node)
	return out


## 是否有单位可以显式攻击该目标（含友军）。
static func any_can_attack(selected: Array, target: Node) -> bool:
	for n in selected:
		if n is Node3D and is_valid_attack_target(n, target) and has_weapon(n):
			return true
	return false


## 是否有单位会把目标当敌对索敌/智能攻击。
static func any_can_auto_attack(selected: Array, target: Node) -> bool:
	for n in selected:
		if n is Node3D and is_auto_acquire_target(n, target) and has_weapon(n):
			return true
	return false


## 在 host 子树中找 acquire 范围内最近敌对目标。
static func find_acquire_target(attacker: Node3D, host: Node, max_range: float = -1.0) -> Node3D:
	if attacker == null or host == null:
		return null
	var lim := max_range if max_range > 0.0 else acquire_range_wc3(attacker)
	var best: Node3D = null
	var best_d := lim
	for c in host.get_children():
		if not (c is Node3D):
			continue
		var other := c as Node3D
		if not is_auto_acquire_target(attacker, other):
			continue
		var d := distance_wc3(attacker, other)
		if d <= best_d:
			best_d = d
			best = other
	return best
