class_name MeleeVictoryRules
extends RefCounted

## 对战建筑清场规则。会话仅在开局生成完毕后传 armed=true。
## 官方说明按团队全部建筑判负；主城损毁本身不代表失败。
## 此处只计算快照，结算锁存、停止模拟与界面由会话负责。
static func evaluate(unit_host: Node, player_teams: Dictionary, armed: bool = false) -> Dictionary:
	var result := {"finished": false, "draw": false, "winner_team": -1, "defeated_teams": []}
	if not armed or not is_instance_valid(unit_host):
		return result
	var buildings_by_team: Dictionary = {}
	for player in player_teams:
		buildings_by_team[int(player_teams[player])] = 0
	if buildings_by_team.size() < 2:
		return result
	for unit in unit_host.get_children():
		if not unit is Node3D or UnitLife.get_life(unit) <= 0.0:
			continue
		var player := CombatQuery.owner_of(unit)
		if not player_teams.has(player) or not BuildingCatalog.is_building(CombatQuery.type_id_of(unit)):
			continue
		# 未完工工地也是真实建筑；不以可交互状态排除暂时隐藏的建筑。
		var team := int(player_teams[player])
		buildings_by_team[team] += 1
	var surviving: Array[int] = []
	var defeated: Array[int] = []
	for team in buildings_by_team:
		if buildings_by_team[team] > 0:
			surviving.append(int(team))
		else:
			defeated.append(int(team))
	surviving.sort()
	defeated.sort()
	result.defeated_teams = defeated
	result.finished = surviving.size() <= 1
	# 同一已结算快照双方均无建筑时判和；精确原版同帧行为仍待对照。
	result.draw = surviving.is_empty()
	if surviving.size() == 1:
		result.winner_team = surviving[0]
	return result
