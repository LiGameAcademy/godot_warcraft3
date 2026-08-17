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
static func in_attack_range(attacker: Node3D, target: Node3D, hysteresis: float = 0.0) -> bool:
	var lim := attack_range_wc3(attacker) + hysteresis
	return distance_wc3(attacker, target) <= lim


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
	if target is Node3D and UnitLife.get_life(target as Node3D) <= 0.0:
		return false
	var tid := type_id_of(target)
	if tid == "ngol" or tid == "sloc":
		return false
	return true


## 显式 Attack 合法目标（含友军强制攻击，对齐 WC3 A 点单位）。
static func is_valid_attack_target(attacker: Node, target: Node) -> bool:
	if not _attack_target_basics(attacker, target):
		return false
	if is_hostile(attacker, target):
		return true
	# 同玩家友军（含未完工己方建筑）
	var oa := owner_of(attacker)
	return oa >= 0 and oa == owner_of(target)


## 自动索敌 / 智能右键：仅敌对（不强制打友军）。
static func is_auto_acquire_target(attacker: Node, target: Node) -> bool:
	return _attack_target_basics(attacker, target) and is_hostile(attacker, target)


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
