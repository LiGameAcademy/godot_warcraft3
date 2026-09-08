class_name TeamRegistry
extends Node

## 会话级「队伍 / 营地」注册表（Game Logic · ai）。
## - 玩家单位（owner<12）按 owner 聚成 team（`p<owner>`）。
## - 中立野怪（owner≥12 且可战斗）按物理距离聚类成 camp（`c<n>`）。
## 营地共用 home（成员中心点），营地 leash / 营友助攻 / 盟友挨打参战走 camp_id / team_id。
##
## 与 UnitAI 的关系：UnitAI 仅持 camp_id / team_id；增减成员、聚类、home 重算、
## 盟友挨打广播均在本表，**不**在 UnitAI（避免每只野怪各扫全场）。
## 落点：挂到 SessionRoot（与 Wc3DefStore 同级），全程常驻；Director 入场收一次。
##
## 后置接口（本阶段不开）：同营 sleep-rules 联动；夜晚 aggro 倍率走 UnitAI 的 _aggro_range_mult。

## 玩家 team id 前缀：`p<owner>`，如 `p0` / `p1`。
const PLAYER_TEAM_PREFIX := "p"
## 中立营地 id 前缀：`c<n>`，n 自增。
const CAMP_PREFIX := "c"

## 营地聚类半径（WC3 距离单位）；同 owner 且两两距离 ≤ 该阈值的野怪视为同一营地。
const CAMP_CLUSTER_RADIUS_WC3 := 900.0
## 单营地最大成员数（防御性上限，避免野生大群误并）。
const CAMP_MAX_MEMBERS := 16

## 与 UnitAI.ALLY_ALERT_RADIUS_WC3 同口径，盟友挨打广播半径。
const ALLY_ALERT_RADIUS_WC3 := 900.0

## 营地 leash 默认半径（WC3 原作约 1300，简化到 1200）。
const CAMP_LEASH_WC3 := 1200.0

## 默认节点名（挂 SessionRoot 用）
const NODE_NAME := "TeamRegistry"

## 玩家 team 索引：team_id（`p<owner>`）→ Array[Node3D]。
var _player_teams: Dictionary = {}
## 营地索引：camp_id（`c<n>`）→ Dictionary {members: Array[Node3D], home: Vector2}。
var _camps: Dictionary = {}
## 成员 → 所属 group_id 反查（`p<owner>` 或 `c<n>`）。
var _member_group: Dictionary = {}
## 单位 Node3D 上 meta 写入：`team_id` / `camp_id`（仅持有其一）。
const META_GROUP_ID := "wc3_team_group_id"
## 单调递增 camp 编号。
var _next_camp_n: int = 1


## 挂到 SessionRoot（与 Wc3DefStore 同位置）。
static func attach(session_root: Node) -> TeamRegistry:
	if session_root == null:
		return null
	var existing := session_root.get_node_or_null(NODE_NAME) as TeamRegistry
	if existing != null:
		return existing
	var reg := TeamRegistry.new()
	reg.name = NODE_NAME
	session_root.add_child(reg)
	return reg


## 从任意节点往上找已挂的 TeamRegistry。
static func get_for(node: Node) -> TeamRegistry:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.find_child(NODE_NAME, true, false) as TeamRegistry


func has_member(body: Node3D) -> bool:
	return body != null and _member_group.has(body.get_instance_id())


func group_of(body: Node3D) -> String:
	if body == null:
		return ""
	var id := body.get_instance_id()
	if not _member_group.has(id):
		return ""
	return str(_member_group[id])


func is_player_team(group_id: String) -> bool:
	return group_id.begins_with(PLAYER_TEAM_PREFIX)


func is_camp(group_id: String) -> bool:
	return group_id.begins_with(CAMP_PREFIX)


## 把单个新生成的中立野怪并入最近的现存 camp。
## - 仅中立（owner≥12）单位参与；玩家/建筑不入营。
## - 阈值内（默认 CAMP_CLUSTER_RADIUS_WC3）才算同营；否则 no-op（保持 ad-hoc 聚类稳定边界，
##   避免野怪飘到画面外被并到不相关的营）。
## - 已有 camp_id 的单位跳过；返回 true 表示入营 / 已在营，false 表示未入。
## 配合 Director._ensure_unit_ai 末尾调用，处理训练/召唤/水元素等后续野怪的入营。
func attach_to_nearest_camp(body: Node3D, threshold_wc3: float = CAMP_CLUSTER_RADIUS_WC3) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	if not CombatQuery.is_alive_in_world(body):
		return false
	var tid := CombatQuery.type_id_of(body)
	if tid.is_empty():
		return false
	if BuildingCatalog.is_building(tid) or BuildingVisual.is_building(tid):
		return false
	var oid := CombatQuery.owner_of(body)
	if not CombatQuery.is_neutral_owner(oid):
		return false
	# 已在营地中：直接返回 true
	var existing := group_of(body)
	if not existing.is_empty() and is_camp(existing):
		return true
	# 找最近营地
	var best_camp := ""
	var best_dist := INF
	var here := Wc3Coords.godot_to_wc3_xy(body.global_position)
	for gid in _camps.keys():
		var home: Vector2 = home_of(str(gid))
		if home == Vector2.INF:
			continue
		var d := here.distance_to(home)
		if d < best_dist:
			best_dist = d
			best_camp = str(gid)
	if best_camp.is_empty() or best_dist > threshold_wc3:
		return false
	# 写入：member → group 索引 + meta + 营地成员列表 + 重新算 home
	var data: Dictionary = _camps.get(best_camp, {})
	var members: Array = (data.get("members", []) as Array).duplicate()
	members.append(body)
	data["members"] = members
	data["home"] = _cluster_home(members)
	_camps[best_camp] = data
	_bind_member_meta(body, best_camp)
	return true


## 营地 home（成员中心点）。无成员或未注册 → Vector2.INF。
func home_of(group_id: String) -> Vector2:
	if not _camps.has(group_id):
		return Vector2.INF
	return (_camps[group_id] as Dictionary).get("home", Vector2.INF) as Vector2


## 营地存活成员拷贝（Array[Node3D]，无效成员已剔除）。
func members_of(group_id: String) -> Array:
	if not _camps.has(group_id):
		return []
	return _filter_alive((_camps[group_id] as Dictionary).get("members", []) as Array)


## 玩家团队存活成员拷贝。
func player_members_of(team_id: String) -> Array:
	if not _player_teams.has(team_id):
		return []
	return _filter_alive(_player_teams[team_id] as Array)


## 入场时一次性：玩家 owner 索引 + 中立距离聚类营地。
## 同一单位重复调 → 仅 `_member_group` 重写，旧的 group 引用会被剔除。
func cluster_and_bind(host: Node) -> Dictionary:
	var result := {"players": 0, "camps": 0, "units": 0}
	if host == null:
		return result
	_reset()
	# 1) 玩家 owner 索引（先把 owner 相同的全部塞进同一个 player team）
	var by_owner: Dictionary = {}
	for c in host.get_children():
		if not _is_bindable_unit(c):
			continue
		var body := c as Node3D
		var oid := CombatQuery.owner_of(body)
		if CombatQuery.is_neutral_owner(oid):
			continue
		by_owner.get_or_add(oid, []).append(body)
	for oid in by_owner.keys():
		var members: Array = by_owner[oid]
		var team_id := "%s%d" % [PLAYER_TEAM_PREFIX, int(oid)]
		_player_teams[team_id] = members
		for m in members:
			_bind_member_meta(m, team_id)
		result["players"] += 1
		result["units"] += members.size()
	# 2) 中立野怪按距离聚类营地
	var neutrals: Array = []
	for c in host.get_children():
		if not _is_bindable_unit(c):
			continue
		var body2 := c as Node3D
		var oid2 := CombatQuery.owner_of(body2)
		if not CombatQuery.is_neutral_owner(oid2):
			continue
		neutrals.append(body2)
	# 朴素 O(N²) 单链聚类：同一簇任两距离 ≤ 阈值即合并（与 WC3 单营地≤16 一致足够）。
	var clustered: Array = []
	for n in neutrals:
		var body3 := n as Node3D
		var merged := false
		for cluster in clustered:
			for existing in (cluster as Array):
				if CombatQuery.distance_wc3(body3, existing as Node3D) <= CAMP_CLUSTER_RADIUS_WC3:
					(cluster as Array).append(body3)
					merged = true
					break
			if merged:
				break
		if not merged:
			clustered.append([body3])
	for cluster in clustered:
		if (cluster as Array).is_empty():
			continue
		var camp_id := "%s%d" % [CAMP_PREFIX, _next_camp_n]
		_next_camp_n += 1
		var home := _cluster_home(cluster as Array)
		_camps[camp_id] = {"members": (cluster as Array).duplicate(), "home": home}
		for m2 in (cluster as Array):
			_bind_member_meta(m2, camp_id)
		result["camps"] += 1
		result["units"] += (cluster as Array).size()
	return result


## 死亡/离场后调用：从 group 移除。
## - 玩家 team 不重算（玩家 home 无意义）。
## - 营地 home **不**随成员变化重算：WC3 原作营地 home 固定（编辑器预设锚点），
##   我们 ad-hoc 聚类也在 cluster_and_bind 一次性确定 home 后保持不变。
##   成员漂走 / 阵亡后 home 仍是首次聚类中心，避免 leash 锚点跟着漂。
func on_unit_gone(body: Node3D) -> void:
	if body == null:
		return
	var gid := group_of(body)
	if gid.is_empty():
		return
	_member_group.erase(body.get_instance_id())
	body.set_meta(META_GROUP_ID, "")
	if is_camp(gid):
		var data: Dictionary = _camps.get(gid, {})
		var members: Array = (data.get("members", []) as Array).filter(func(x): return x != body and is_instance_valid(x))
		if members.is_empty():
			_camps.erase(gid)
			return
		data["members"] = members
		# home 锁定：见函数注释，不重算
		_camps[gid] = data


## 盟友挨打广播：调本接口把同 team/camp 闲置单位一起拉去打 attacker。
## - 玩家 team：仅当触发源非 IDLE（已 ENGAGED 或受击）才拉；
##   拉到后这些单位走 try_engage（仍是 AI 自动接管，仍受 `_player_occupied` 节流）。
## - 营地：所有存活成员都可拉（营地即整队）；同样走 try_engage。
##
## `attacker`：攻击者 Node3D。
## `radius_wc3`：默认 ALLY_ALERT_RADIUS_WC3。
## 返回：成功参战的队友数。
func notify_ally_engaged(
	source: Node3D, attacker: Node3D, radius_wc3: float = ALLY_ALERT_RADIUS_WC3
) -> int:
	if source == null or attacker == null or not is_instance_valid(attacker):
		return 0
	var gid := group_of(source)
	if gid.is_empty():
		return 0
	var source_ai := UnitAI.of(source)
	var require_active := is_player_team(gid)
	var source_active := (
		source_ai != null
		and (source_ai.is_engaged() or source_ai.is_asleep() == false and _is_source_under_attack(source_ai))
	)
	if require_active and not source_active and source_ai != null and not source_ai.is_engaged():
		return 0
	var center := source.global_position
	var center_wc3 := Wc3Coords.godot_to_wc3_xy(center)
	var members: Array = []
	if is_player_team(gid):
		members = player_members_of(gid)
	else:
		members = members_of(gid)
	var joined := 0
	# 营地成员：WC3 语义是"整组拉"，不限制 assist 半径（不论多远都拉）。
	# 玩家 team：限制 assist 半径（默认 ALLY_ALERT_RADIUS_WC3 = 900）。
	var use_distance_gate := not is_camp(gid)
	for m in members:
		var other := m as Node3D
		if other == source or not is_instance_valid(other):
			continue
		if use_distance_gate:
			var other_wc3 := Wc3Coords.godot_to_wc3_xy(other.global_position)
			if other_wc3.distance_to(center_wc3) > radius_wc3:
				continue
		var ai := UnitAI.of(other)
		if ai == null:
			continue
		if not ai.allows_ally_engage():
			continue
		if not CombatQuery.is_auto_acquire_target(other, attacker):
			continue
		if ai.try_engage(attacker):
			joined += 1
	return joined


## 可选调试：dump 当前 group 状态。
func debug_summary() -> Dictionary:
	var p := {}
	for k in _player_teams.keys():
		p[str(k)] = (player_members_of(str(k))).size()
	var c := {}
	for k in _camps.keys():
		c[str(k)] = {
			"members": (members_of(str(k))).size(),
			"home": home_of(str(k)),
		}
	return {"players": p, "camps": c}


func _reset() -> void:
	_player_teams.clear()
	_camps.clear()
	_member_group.clear()
	_next_camp_n = 1


func _is_bindable_unit(n: Node) -> bool:
	if not (n is Node3D):
		return false
	var body := n as Node3D
	var tid := CombatQuery.type_id_of(body)
	if tid.is_empty():
		return false
	if BuildingCatalog.is_building(tid) or BuildingVisual.is_building(tid):
		return false
	if not CombatQuery.is_alive_in_world(body):
		return false
	# 注：has_weapon 在 UnitAI.default_profile_for 已把关；本表只做 owner / 建筑过滤。
	return true


func _bind_member_meta(body: Node3D, group_id: String) -> void:
	if body == null:
		return
	_member_group[body.get_instance_id()] = group_id
	body.set_meta(META_GROUP_ID, group_id)


func _cluster_home(members: Array) -> Vector2:
	var alive := _filter_alive(members)
	if alive.is_empty():
		return Vector2.INF
	var acc := Vector2.ZERO
	for m in alive:
		acc += Wc3Coords.godot_to_wc3_xy((m as Node3D).global_position)
	return acc / float(alive.size())


func _filter_alive(arr: Array) -> Array:
	var out: Array = []
	for x in arr:
		var body := x as Node3D
		if body == null or not is_instance_valid(body):
			continue
		if not CombatQuery.is_alive_in_world(body):
			continue
		out.append(body)
	return out


## 触发源是否处于「正在被打」状态：life meta 在过去一帧下降过 / 当前 life < max。
## 简化：当前玩家 team 联防**仅**依赖 is_engaged；受击反击（U1）会立即把 source 切到
## ENGAGED 并触发本广播，故无需再判断受击状态。该钩子保留供后续"生命正在下降"等
## 触发源扩展（接 `_last_damage_frame` meta），当前阶段始终 false。
func _is_source_under_attack(_ai: UnitAI) -> bool:
	return false
