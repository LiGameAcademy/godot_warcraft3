class_name CommandCard
extends RefCounted

## 行动面板组装（HUD 命令格）——数据驱动。
## - 图标 / 槽位 / 热键 / Tip ← CommandButtonCatalog（Func+Strings）
## - 技能列表 ← UnitAbilities.abilList
## - 训练 / 建造列表 ← UnitFunc Trains / Builds
## - action_id 与运行时态（执行中、买不起）仍由本类按 Order 映射组装
##
## 建造：主卡只放种族 Build 技能（如 AHbu）；点开后进入二级建筑列表 + 取消。

const ACTION_MOVE := "move"
const ACTION_STOP := "stop"
const ACTION_HOLD := "hold"
const ACTION_ATTACK := "attack"
const ACTION_PATROL := "patrol"
const ACTION_HARVEST_GOLD := "harvest_gold"
const ACTION_RETURN_GOODS := "return_goods"
const ACTION_BUILD_PREFIX := "build:" ## 建造按钮 action_id 前缀
const ACTION_OPEN_BUILD := "open_build" ## 进入建造二级面板
const ACTION_CLOSE_BUILD := "close_build" ## 退出建造二级面板
const ACTION_TRAIN_PREFIX := "train:" ## 训练单位：train:hpea
const ACTION_REVIVE_PREFIX := "revive:" ## 祭坛复活：revive:Hamg
const ACTION_RESEARCH_PREFIX := "research:" ## 研究科技：research:Rhde
const ACTION_DEFEND := "defend"
const ACTION_CALL_TO_ARMS := "call_to_arms"
const ACTION_SET_RALLY := "set_rally"
const ACTION_ABILITY_PREFIX := "ability:" ## ability:AHwe
const ACTION_PASSIVE_PREFIX := "passive:" ## 被动光环，不可点击
const ACTION_OPEN_HERO_SKILLS := "open_hero_skills"
const ACTION_CLOSE_HERO_SKILLS := "close_hero_skills"
const ACTION_LEARN_PREFIX := "learn:" ## learn:AHwe

const CMD_MOVE := "CmdMove"
const CMD_STOP := "CmdStop"
const CMD_HOLD := "CmdHoldPos"
const CMD_ATTACK := "CmdAttack"
const CMD_PATROL := "CmdPatrol"
const CMD_RALLY := "CmdRally"
const CMD_CANCEL_BUILD := "CmdCancelBuild"

## 种族 → Build 技能（与 BUILD_SYSTEM.md 一致；人族竖切用 AHbu）
const _RACE_BUILD_ABIL := {
	"human": "AHbu",
	"orc": "AObu",
	"nightelf": "AEbu",
	"undead": "AUbu",
	"naga": "AGbu",
}

## Order → 本竖切已接线的 action（未列出的技能有 Art 也不上卡，避免空按钮）
## use_un：携带资源时切 Unart（仅 harvest）
const _ORDER_SPEC := {
	"harvest": {"action": ACTION_HARVEST_GOLD, "un_action": ACTION_RETURN_GOODS},
	"townbellon": {"action": ACTION_CALL_TO_ARMS},
	## 农民/民兵 Amil：Order=militia / Unorder=militiaoff
	"militia": {"action": ACTION_CALL_TO_ARMS},
	"defend": {"action": ACTION_DEFEND},
}


static func _cat() -> CommandButtonCatalog:
	return CommandButtonCatalog.get_shared()


static func _empty_card() -> Array[Dictionary]:
	var card: Array[Dictionary] = []
	card.resize(12)
	for i in range(12):
		card[i] = {}
	return card


static func _place(card: Array[Dictionary], entry: Dictionary) -> void:
	if entry.is_empty():
		return
	var slot := int(entry.get("slot", -1))
	if slot < 0 or slot >= card.size():
		return
	card[slot] = entry


## 通用入口：按单位 typeId + 运行时态组装 12 格。
## state 键：
##   move_executing / carrying / harvest_executing / return_executing
##   include_locomotion（默认：非建筑 true）
##   build_allowlist / building_ids（可造列表；主卡只显示 Build 入口）
##   build_menu_open（true → 二级建筑面板）
##   can_afford（历史名）：建造按钮是否解锁/可点；仅 Requires，不含资源
##   building_executing（与 building_ids 等长）
##   build_disabled_reasons（与 building_ids 等长；未解锁 tip）
##   owned_buildings（typeId→count；训练 Requires 判定）
##   researched（upgradeid→level；研究完成 / 技能 Requires）
##   defend_active（顶盾开启 → Unart 停盾图标）
##   hide_trains（true：隐藏训兵按钮，仍可显示集结点；建造中用）
##   worker_race（可选；空则按 human）
##   ability_cd（Dictionary abil_id→剩余秒，命令卡灰显/执行中）
##   ability_mana_ok（false → 全部英雄技能不可用；优先用 ability_mana_ok_map）
##   ability_mana_ok_map（abil_id→bool，按技能魔法是否足够）
static func for_unit(unit_id: String, state: Dictionary = {}) -> Array[Dictionary]:
	var uid := unit_id.strip_edges()
	var cat := _cat()
	if uid.is_empty():
		return _empty_card()

	var building_ids := _resolve_building_ids(uid, state)
	if bool(state.get("build_menu_open", false)) and not building_ids.is_empty():
		return for_build_menu(building_ids, state)
	if bool(state.get("hero_skill_menu_open", false)) and TechPresence.is_hero_id(uid):
		return for_hero_skill_menu(uid, state)

	var card := _empty_card()
	var is_bldg := BuildingCatalog.is_building(uid)
	var include_loco := bool(state.get("include_locomotion", not is_bldg))
	if include_loco:
		_place_locomotion(card, cat, bool(state.get("move_executing", false)))

	var training_unit := str(state.get("training_unit", "")).strip_edges()
	var queued: Dictionary = {}
	var tq_raw: Variant = state.get("train_queue", [])
	if tq_raw is Array:
		for e in tq_raw as Array:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			var qid := str((e as Dictionary).get("unit_id", ""))
			if qid.is_empty():
				continue
			queued[qid] = int(queued.get(qid, 0)) + 1
	var owned: Dictionary = state.get("owned_buildings", {}) as Dictionary
	if owned == null:
		owned = {}
	var researched: Dictionary = state.get("researched", {}) as Dictionary
	if researched == null:
		researched = {}
	var hero_slots_full := bool(state.get("hero_slots_full", false))
	var hide_trains := bool(state.get("hide_trains", false))
	var trains := TechPresence.filter_vertical_trains(uid, cat.get_trains(uid))
	var dead_heroes: Array = state.get("dead_heroes", []) as Array
	if dead_heroes == null:
		dead_heroes = []
	var dead_type_ids: Dictionary = {}
	if not hide_trains and BuildingCatalog.is_building(uid):
		var revive_slot := 0
		for dead in dead_heroes:
			if typeof(dead) != TYPE_DICTIONARY:
				continue
			var d: Dictionary = dead
			var hid := str(d.get("type_id", "")).strip_edges()
			if hid.is_empty() or not TechPresence.is_hero_id(hid):
				continue
			# 同 type 只放一格（最早阵亡的那只）
			if dead_type_ids.has(hid):
				continue
			dead_type_ids[hid] = true
			var lv := maxi(int(d.get("level", 1)), 1)
			var gold := HeroDeathRegistry.revive_cost(lv)
			var sec := HeroDeathRegistry.revive_time_sec(lv)
			var exec := training_unit == hid or queued.has(hid)
			var opts_r := {
				"enabled": true,
				"executing": exec,
				"badge_level": lv,
				"cost_line": "复活 · %d金 · %.0fs" % [gold, sec],
				"slot_override": clampi(revive_slot, 0, 3),
			}
			revive_slot += 1
			var entry_r := cat.unit_hud_entry(hid, ACTION_REVIVE_PREFIX + hid, opts_r)
			if not entry_r.is_empty():
				entry_r["badge_level"] = lv
			_place(card, entry_r)
	if not hide_trains:
		for tid in trains:
			# 已有同 type 阵亡登记时只显示复活，不重复「训新英雄」
			if TechPresence.is_hero_id(tid) and dead_type_ids.has(tid):
				continue
			var exec := training_unit == tid or queued.has(tid)
			var missing := TechPresence.missing_requires(
				owned, UnitRequiresCatalog.get_shared().get_requires(tid), researched
			)
			var train_ok := missing.is_empty()
			var opts := {"enabled": train_ok, "executing": exec}
			if not train_ok:
				opts["disabled_reason"] = TechPresence.requires_tip(missing)
			elif TechPresence.is_hero_id(tid) and hero_slots_full:
				opts["enabled"] = false
				opts["disabled_reason"] = "英雄数量已达上限"
			_place(card, cat.unit_hud_entry(tid, ACTION_TRAIN_PREFIX + tid, opts))
		var researches := TechPresence.filter_vertical_researches(uid, cat.get_researches(uid))
		for rid in researches:
			# 原作：研究完成后按钮消失（不是置灰留在卡上）
			if int(researched.get(rid, 0)) > 0:
				continue
			var exec := training_unit == rid or queued.has(rid)
			var opts := {
				"enabled": true,
				"executing": exec,
				"cost_line": _upgrade_cost_line(rid),
			}
			_place(card, cat.upgrade_hud_entry(rid, ACTION_RESEARCH_PREFIX + rid, opts))

	var carrying := bool(state.get("carrying", false))
	var hl := maxi(int(state.get("hero_level", 1)), 1)
	var ab_levels: Dictionary = state.get("ability_levels", {}) as Dictionary
	if ab_levels == null:
		ab_levels = {}
	for abil_id in cat.get_all_abil_list(uid):
		_place_supported_ability(
			card, cat, str(abil_id), uid, state, carrying, owned, researched, hl, ab_levels
		)
	# 农民/民兵：Amil 战斗号召（SLK 常不在 abilList，需显式落卡）
	if uid == "hpea" or uid == "hmil":
		_place_supported_ability(
			card, cat, "Amil", uid, state, carrying, owned, researched, hl, ab_levels
		)

	if TechPresence.is_hero_id(uid):
		_place_hero_skill_opener(card, cat, state)

	if not building_ids.is_empty():
		_place_build_opener(card, cat, str(state.get("worker_race", "human")))

	# 可训练建筑：集结点（CmdRally）；建造中也保留
	if not trains.is_empty():
		_place(
			card,
			cat.command_hud_entry(
				CMD_RALLY,
				ACTION_SET_RALLY,
				{"enabled": true, "executing": false}
			)
		)

	return card


## 建造二级面板：建筑按 UnitFunc Buttonpos 落格 + 取消（Esc）。
static func for_build_menu(
	building_ids: PackedStringArray, state: Dictionary = {}
) -> Array[Dictionary]:
	var cat := _cat()
	var card := _empty_card()
	var can_afford: PackedInt32Array = state.get("can_afford", PackedInt32Array()) as PackedInt32Array
	var building_executing: PackedInt32Array = state.get(
		"building_executing", PackedInt32Array()
	) as PackedInt32Array
	var disabled_reasons: PackedStringArray = state.get(
		"build_disabled_reasons", PackedStringArray()
	) as PackedStringArray
	if can_afford == null:
		can_afford = PackedInt32Array()
	if building_executing == null:
		building_executing = PackedInt32Array()
	if disabled_reasons == null:
		disabled_reasons = PackedStringArray()
	for i in range(building_ids.size()):
		var bid := str(building_ids[i])
		var ok := i < can_afford.size() and int(can_afford[i]) != 0
		var exec := i < building_executing.size() and int(building_executing[i]) != 0
		var reason := ""
		if i < disabled_reasons.size():
			reason = str(disabled_reasons[i]).strip_edges()
		var opts := {
			"enabled": ok,
			"executing": exec,
			"cost_line": _building_cost_line(bid),
		}
		if not ok and not reason.is_empty():
			opts["disabled_reason"] = reason
		var entry := cat.unit_hud_entry(bid, ACTION_BUILD_PREFIX + bid, opts)
		if entry.is_empty():
			entry = _build_button_fallback(bid, ok, exec, -1, reason)
		_place(card, entry)
	_place_build_cancel(card, cat)
	return card


## 英雄技能学习二级面板：可学英雄技能（Buttonpos 与命令卡一致）+ 取消（右下）。
static func for_hero_skill_menu(unit_id: String, state: Dictionary = {}) -> Array[Dictionary]:
	var cat := _cat()
	var card := _empty_card()
	var hl := maxi(int(state.get("hero_level", 1)), 1)
	var ab_levels: Dictionary = state.get("ability_levels", {}) as Dictionary
	if ab_levels == null:
		ab_levels = {}
	var points := maxi(int(state.get("hero_skill_points", 0)), 0)
	for abil_id in cat.get_hero_abil_list(unit_id):
		var id := str(abil_id).strip_edges()
		if id.is_empty():
			continue
		var ab := AbilityCatalog.data(id)
		if ab == null:
			continue
		var cur := maxi(int(ab_levels.get(id, 0)), 0)
		var max_lv := ab.clamp_level(ab.levels)
		if cur >= max_lv:
			continue
		var req_hl := ab.required_hero_level_for_rank(cur)
		var meets_level := hl >= req_hl
		var can := points > 0 and meets_level
		var row := cat.get_ability(id)
		var lv_line := "等级 %d / %d" % [cur, max_lv]
		lv_line += " · 需英雄 %d 级" % req_hl
		if points <= 0:
			lv_line += "\n|cffff6060无可用技能点|r"
		elif not meets_level:
			lv_line += "\n|cffff6060英雄等级不足|r"
		var reason := ""
		if points <= 0:
			reason = "无可用技能点"
		elif not meets_level:
			reason = "需要英雄 %d 级" % req_hl
		var opts := {
			"enabled": can,
			"executing": false,
			"disabled_reason": reason,
			"ability_level": maxi(cur, 1),
			"badge_level": cur + 1 if cur < max_lv else cur,
			"tooltip_all_levels": true,
			"learn_menu": true,
		}
		opts["cost_line"] = lv_line
		var entry := cat.make_hud_entry(row, ACTION_LEARN_PREFIX + id, opts)
		_place(card, entry)
	_place(
		card,
		cat.command_hud_entry(
			CMD_CANCEL_BUILD,
			ACTION_CLOSE_HERO_SKILLS,
			{"enabled": true, "executing": false, "slot_override": 11}
		)
	)
	return card


static func _resolve_building_ids(unit_id: String, state: Dictionary) -> PackedStringArray:
	var building_ids: PackedStringArray = state.get("building_ids", PackedStringArray()) as PackedStringArray
	if building_ids == null:
		building_ids = PackedStringArray()
	if not building_ids.is_empty():
		return building_ids
	var allow: PackedStringArray = state.get("build_allowlist", PackedStringArray()) as PackedStringArray
	if allow == null or allow.is_empty():
		return PackedStringArray()
	return _cat().filter_builds(unit_id, allow)


static func build_ability_id(race: String) -> String:
	var key := race.strip_edges().to_lower()
	if key.is_empty():
		key = "human"
	return str(_RACE_BUILD_ABIL.get(key, "AHbu"))


## 常规机动四键 + 攻击：Move/Stop/Hold/Attack + Patrol（槽位来自 CommandFunc Buttonpos）。
static func _place_locomotion(card: Array[Dictionary], cat: CommandButtonCatalog, move_executing: bool) -> void:
	_place(
		card,
		cat.command_hud_entry(
			CMD_MOVE,
			ACTION_MOVE,
			{"executing": move_executing, "enabled": true}
		)
	)
	_place(
		card,
		cat.command_hud_entry(
			CMD_STOP,
			ACTION_STOP,
			{"executing": false, "enabled": true}
		)
	)
	_place(
		card,
		cat.command_hud_entry(
			CMD_HOLD,
			ACTION_HOLD,
			{"executing": false, "enabled": true}
		)
	)
	_place(
		card,
		cat.command_hud_entry(
			CMD_ATTACK,
			ACTION_ATTACK,
			{"executing": false, "enabled": true}
		)
	)
	_place(
		card,
		cat.command_hud_entry(
			CMD_PATROL,
			ACTION_PATROL,
			{"executing": false, "enabled": true}
		)
	)


static func _place_supported_ability(
	card: Array[Dictionary],
	cat: CommandButtonCatalog,
	abil_id: String,
	unit_id: String,
	state: Dictionary,
	carrying: bool,
	owned: Dictionary = {},
	researched: Dictionary = {},
	hero_level: int = 1,
	ability_levels: Dictionary = {}
) -> void:
	var order := cat.get_ability_order(abil_id)
	if AbilityCatalog.is_passive_aura(abil_id):
		_place_passive_aura(card, cat, abil_id, unit_id, state, hero_level, ability_levels)
		return
	if order.is_empty():
		return
	if order == "defend":
		var spec: Dictionary = _ORDER_SPEC[order]
		var use_un := false
		var action_id := str(spec.get("action", ""))
		var opts := {"enabled": true, "executing": false}
		var missing := TechPresence.missing_requires(
			owned, cat.get_ability_requires(abil_id), researched
		)
		if not missing.is_empty():
			opts["enabled"] = false
			opts["disabled_reason"] = TechPresence.requires_tip(missing)
		else:
			use_un = bool(state.get("defend_active", false))
			opts["executing"] = use_un
			opts["use_un"] = use_un
		var entry := cat.ability_hud_entry(abil_id, action_id, opts)
		_place(card, entry)
		return
	if order == "harvest":
		var spec_h: Dictionary = _ORDER_SPEC[order]
		var use_un_h := carrying
		var action_id_h := str(spec_h.get("un_action" if use_un_h else "action", ""))
		var opts_h := {"enabled": true, "executing": false, "use_un": use_un_h}
		if use_un_h:
			opts_h["executing"] = bool(state.get("return_executing", false))
		else:
			opts_h["executing"] = bool(state.get("harvest_executing", false))
		var entry_h := cat.ability_hud_entry(abil_id, action_id_h, opts_h)
		_place(card, entry_h)
		return
	if order == "townbellon":
		var spec_t: Dictionary = _ORDER_SPEC[order]
		var entry_t := cat.ability_hud_entry(
			abil_id, str(spec_t.get("action", ACTION_CALL_TO_ARMS)), {"enabled": true}
		)
		_place(card, entry_t)
		return
	# 农民 Amil / 民兵收回：同一 action，民兵态切 Unart（BTNBacktoWork）
	if order == "militia":
		var is_mil := unit_id == "hmil" or bool(state.get("militia_active", false))
		var entry_m := cat.ability_hud_entry(
			abil_id,
			ACTION_CALL_TO_ARMS,
			{"enabled": true, "use_un": is_mil, "executing": is_mil}
		)
		_place(card, entry_m)
		return
	if not AbilityCatalog.is_supported(abil_id):
		return
	var lv := AbilityCatalog.level_for_unit_type(
		unit_id, abil_id, hero_level, ability_levels
	)
	if lv <= 0:
		return
	var cd_map: Dictionary = state.get("ability_cd", {}) as Dictionary
	var cd_total_map: Dictionary = state.get("ability_cd_total", {}) as Dictionary
	var cd_left := maxf(float(cd_map.get(abil_id, 0.0)), 0.0)
	var cd_total := maxf(float(cd_total_map.get(abil_id, 0.0)), 0.0)
	var opts_a := {
		"enabled": true,
		"executing": false,
		"ability_level": lv,
		"badge_level": lv,
	}
	# 未满足 Requires 时技能灰显（含 Ainf→Rhpt×2 等）
	var missing_abil := TechPresence.missing_requires(
		owned,
		cat.get_ability_requires(abil_id),
		researched,
		cat.get_ability_require_levels(abil_id)
	)
	if not missing_abil.is_empty():
		opts_a["enabled"] = false
		opts_a["disabled_reason"] = TechPresence.requires_tip(missing_abil)
	if cd_left > 0.0:
		opts_a["enabled"] = false
		opts_a["disabled_reason"] = "冷却中"
		# 扇形进度：保留彩色图标，不走 DIS；ratio=剩余/总时长
		var tot := cd_total if cd_total > 0.01 else cd_left
		opts_a["cooldown_ratio"] = clampf(cd_left / tot, 0.0, 1.0)
		opts_a["keep_icon_on_cd"] = true
	elif not bool((state.get("ability_mana_ok_map", {}) as Dictionary).get(abil_id, state.get("ability_mana_ok", true))):
		if bool(opts_a.get("enabled", true)):
			opts_a["enabled"] = false
			opts_a["disabled_reason"] = "法力不足"
	if abil_id == "AHav" and bool(state.get("avatar_active", false)):
		opts_a["executing"] = true
		opts_a["use_un"] = true
	var auto_map: Dictionary = state.get("ability_autocast", {}) as Dictionary
	if AbilityAutoCast.supports(abil_id):
		var auto_on := bool(auto_map.get(abil_id, false))
		opts_a["use_un"] = not auto_on
		opts_a["auto_cast"] = auto_on
		opts_a["autocast_capable"] = true
	var entry_a := cat.ability_hud_entry(
		abil_id, ACTION_ABILITY_PREFIX + abil_id, opts_a
	)
	_place(card, entry_a)


static func _place_passive_aura(
	card: Array[Dictionary],
	cat: CommandButtonCatalog,
	abil_id: String,
	unit_id: String,
	state: Dictionary,
	hero_level: int = 1,
	ability_levels: Dictionary = {}
) -> void:
	var hl := maxi(int(state.get("hero_level", hero_level)), 1)
	var lv := AbilityCatalog.level_for_unit_type(unit_id, abil_id, hl, ability_levels)
	if lv <= 0:
		return
	var opts := {
		# 原作被动：彩色 PASBTN，不可点；灰显留给未解锁/条件不足
		"enabled": true,
		"passive": true,
		"executing": true,
		"disabled_reason": "被动光环",
		"ability_level": lv,
		"badge_level": lv,
	}
	var entry := cat.ability_hud_entry(
		abil_id, ACTION_PASSIVE_PREFIX + abil_id, opts
	)
	_place(card, entry)


static func _place_hero_skill_opener(
	card: Array[Dictionary], cat: CommandButtonCatalog, state: Dictionary
) -> void:
	if bool(state.get("hero_skill_menu_open", false)):
		return
	var points := maxi(int(state.get("hero_skill_points", 0)), 0)
	var tip := "英雄技能"
	if points > 0:
		tip += "\n|cffffcc00可用技能点：%d|r" % points
	tip += "\n|cff00ff00O|r 打开"
	var entry := {
		"id": ACTION_OPEN_HERO_SKILLS,
		"text": "",
		"tooltip": tip,
		"hotkey": KEY_O,
		"hotkey_label": "O",
		"icon": "ReplaceableTextures/CommandButtons/BTNSkillz.png",
		"icon_disabled": "ReplaceableTextures/CommandButtonsDisabled/DISBTNSkillz.png",
		"executing": false,
		"enabled": true,
		"slot": 7,
		# 原作：+ 按钮右下角数字 = 当前可分配技能点
		"badge_level": points,
	}
	_place(card, entry)


static func _place_build_opener(
	card: Array[Dictionary], cat: CommandButtonCatalog, race: String
) -> void:
	var abil := build_ability_id(race)
	var entry := cat.ability_hud_entry(abil, ACTION_OPEN_BUILD, {"enabled": true, "executing": false})
	if entry.is_empty():
		entry = {
			"id": ACTION_OPEN_BUILD,
			"text": "",
			"tooltip": "建造(|cffffcc00B|r)",
			"hotkey": KEY_B,
			"hotkey_label": "B",
			"icon": "ReplaceableTextures/CommandButtons/BTNHumanBuild.png",
			"icon_disabled": "ReplaceableTextures/CommandButtonsDisabled/DISBTNHumanBuild.png",
			"executing": false,
			"enabled": true,
			"slot": 8, ## AHbu Buttonpos 0,2
		}
	else:
		# Func 常缺 Tip/Hotkey（Strings 无 AHbu 段）
		if str(entry.get("tooltip", "")).strip_edges().is_empty():
			entry["tooltip"] = "建造(|cffffcc00B|r)"
		if int(entry.get("hotkey", 0)) == 0:
			entry["hotkey"] = KEY_B
			entry["hotkey_label"] = "B"
	_place(card, entry)


static func _place_build_cancel(card: Array[Dictionary], cat: CommandButtonCatalog) -> void:
	var entry := cat.command_hud_entry(
		CMD_CANCEL_BUILD,
		ACTION_CLOSE_BUILD,
		{"enabled": true, "executing": false}
	)
	if entry.is_empty():
		entry = {
			"id": ACTION_CLOSE_BUILD,
			"text": "",
			"tooltip": "取消(|cffffcc00ESC|r)",
			"hotkey": KEY_ESCAPE,
			"hotkey_label": "ESC",
			"icon": "ReplaceableTextures/CommandButtons/BTNCancel.png",
			"icon_disabled": "ReplaceableTextures/CommandButtonsDisabled/DISBTNCancel.png",
			"executing": false,
			"enabled": true,
			"slot": 11, ## ButtonPos 3,2
		}
	else:
		# Catalog Hotkey=512 不是 Godot KEY_ESCAPE；改由 Esc 键关闭
		entry["hotkey"] = KEY_ESCAPE
		entry["hotkey_label"] = "ESC"
		if str(entry.get("tooltip", "")).strip_edges().is_empty():
			entry["tooltip"] = "取消(|cffffcc00ESC|r)"
	_place(card, entry)


## —— 兼容旧调用（Director / 文档）；内部转 for_unit ——

static func town_hall(unit_id: String = "htow") -> Array[Dictionary]:
	return for_unit(unit_id, {"include_locomotion": false})


static func basic_locomotion(move_executing: bool = false) -> Array[Dictionary]:
	var card := _empty_card()
	_place_locomotion(card, _cat(), move_executing)
	return card


static func peasant(
	move_executing: bool = false,
	carrying: bool = false,
	harvest_executing: bool = false,
	return_executing: bool = false,
	unit_id: String = "hpea"
) -> Array[Dictionary]:
	return for_unit(
		unit_id,
		{
			"move_executing": move_executing,
			"carrying": carrying,
			"harvest_executing": harvest_executing,
			"return_executing": return_executing,
			"include_locomotion": true,
			"build_allowlist": PackedStringArray(), ## 无建造入口
		}
	)


static func peasant_with_build(
	move_executing: bool = false,
	carrying: bool = false,
	harvest_executing: bool = false,
	return_executing: bool = false,
	building_ids: PackedStringArray = PackedStringArray(),
	can_afford: PackedInt32Array = PackedInt32Array(),
	building_executing: PackedInt32Array = PackedInt32Array(),
	unit_id: String = "hpea",
	build_menu_open: bool = false
) -> Array[Dictionary]:
	## building_ids 为空：Builds ∩ 竖切可造表（顺序跟 UnitFunc Builds）
	var ids := building_ids
	if ids.is_empty():
		var allow := PackedStringArray()
		for bid in BuildingCatalog.VERTICAL_BUILDING_IDS:
			allow.append(str(bid))
		ids = _cat().filter_builds(unit_id, allow)
	return for_unit(
		unit_id,
		{
			"move_executing": move_executing,
			"carrying": carrying,
			"harvest_executing": harvest_executing,
			"return_executing": return_executing,
			"include_locomotion": true,
			"building_ids": ids,
			"can_afford": can_afford,
			"building_executing": building_executing,
			"build_menu_open": build_menu_open,
			"worker_race": "human",
		}
	)


static func _building_cost_line(building_id: String) -> String:
	var g := BuildingCatalog.get_gold_cost(building_id)
	var l := BuildingCatalog.get_lumber_cost(building_id)
	var cost := "造价 %d 金" % g
	if l > 0:
		cost += " · %d 木" % l
	return cost + "。"


static func _upgrade_cost_line(upgrade_id: String) -> String:
	var g := TechPresence.upgrade_gold(upgrade_id)
	var l := TechPresence.upgrade_lumber(upgrade_id)
	var t := TechPresence.upgrade_time(upgrade_id)
	var cost := "造价 %d 金" % g
	if l > 0:
		cost += " · %d 木" % l
	if t > 0.0:
		cost += " · %.0f秒" % t
	return cost + "。"


## Catalog 缺 UI 行时的极简兜底（不再写死中文名/图标表；显示 id）
static func _build_button_fallback(
	building_id: String,
	can_afford: bool,
	executing: bool,
	slot: int,
	disabled_reason: String = ""
) -> Dictionary:
	var tip := "建造 %s\n%s" % [building_id, _building_cost_line(building_id)]
	if not can_afford:
		var reason := disabled_reason.strip_edges()
		if reason.is_empty():
			reason = "资源不足"
		tip += "\n|cffff6060%s|r" % reason
	elif executing:
		tip += "\n|cff00ff00当前：执行中|r"
	var resolved_slot := slot
	if resolved_slot < 0:
		resolved_slot = 0
	return {
		"id": ACTION_BUILD_PREFIX + building_id,
		"text": "执行中" if executing else "",
		"tooltip": tip,
		"hotkey": 0,
		"hotkey_label": "",
		"icon": "ReplaceableTextures/CommandButtons/BTNBuild.png",
		"icon_disabled": "ReplaceableTextures/CommandButtonsDisabled/DISBTNBuild.png",
		"executing": executing,
		"enabled": can_afford,
		"slot": resolved_slot,
	}


## 显示名（Director 状态栏等）；优先 Catalog Name。
static func _building_display_name(building_id: String) -> String:
	var row := _cat().get_unit_ui(building_id)
	var n := str(row.get("name", "")).strip_edges()
	if not n.is_empty():
		return n
	return building_id


## 去掉 WC3 色码，供 Godot tooltip 纯文本显示。
static func plain_tooltip(raw: String) -> String:
	var re := RegEx.new()
	if re.compile("\\|c[0-9a-fA-F]{8}") != OK:
		return raw.replace("|r", "").replace("|n", "\n")
	var s := re.sub(raw, "", true)
	return s.replace("|r", "").replace("|n", "\n")
