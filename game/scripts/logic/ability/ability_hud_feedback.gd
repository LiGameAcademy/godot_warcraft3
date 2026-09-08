class_name AbilityHudFeedback
extends RefCounted

## 技能 HUD 反馈（Present/Orchestration）：状态栏文案 + 命令卡 UI 状态。

var _set_status: Callable = Callable()


func configure(set_status: Callable) -> void:
	_set_status = set_status


func set_status(text: String) -> void:
	if _set_status.is_valid():
		_set_status.call(text)


func on_targeting_begin(abil_id: String, source: int, aim_hint: String) -> void:
	var src := "面板" if source == UnitOrder.Source.PANEL else "热键"
	var row := CommandButtonCatalog.get_shared().get_ability(abil_id)
	var tip := str(row.get("name", abil_id)).strip_edges()
	if tip.is_empty():
		tip = abil_id
	set_status("技能瞄准（%s）· %s · %s · Esc 取消" % [src, tip, aim_hint])


func on_cast_start(abil_id: String, caster: Node3D, start: Dictionary) -> void:
	if not bool(start.get("ok", false)):
		set_status(str(start.get("reason", "施法失败")))
		return
	if bool(start.get("approaching", false)):
		set_status("接近施法点…")
		return
	if AbilityCastCatalog.is_channel_ability(abil_id) and caster != null:
		var lv := AbilityCatalog.level_for(caster, abil_id)
		var dur := AbilityCastCatalog.channel_duration_sec(abil_id, lv)
		set_status("引导暴风雪 · %.1fs（移动/停止可打断）" % dur)
		return
	var ab := AbilityCatalog.data(abil_id)
	if ab != null and caster != null:
		var cast_sec := AbilityCastCatalog.cast_time_sec(
			abil_id, AbilityCatalog.level_for(caster, abil_id)
		)
		if cast_sec > 0.05:
			set_status("施法中 · %.1fs（移动/停止可打断）" % cast_sec)
			return
	set_status("施法中…")


func on_cast_resolved(result: Dictionary, abil_id: String) -> void:
	if bool(result.get("ok", false)):
		var spawned := result.get("unit") as Node3D
		var tp_count := int(result.get("teleported_count", 0))
		var hit_count := int(result.get("hit_count", 0))
		var heal_amt := float(result.get("heal_amount", 0.0))
		if tp_count > 0:
			set_status("群体传送 · %d 单位" % tp_count)
		elif heal_amt > 0.0:
			set_status("治疗 · +%.0f" % heal_amt)
		elif hit_count > 0:
			var row_h := CommandButtonCatalog.get_shared().get_ability(abil_id)
			var name_h := str(row_h.get("name", abil_id)).strip_edges()
			set_status("%s · %d 目标" % [name_h, hit_count])
		elif spawned != null:
			var name_s := TechPresence.display_name(
				str(spawned.get_meta("unit_data", {}).get("typeId", abil_id))
			)
			set_status("召唤 · %s" % name_s)
		else:
			var row := CommandButtonCatalog.get_shared().get_ability(abil_id)
			var name_s2 := str(row.get("name", abil_id)).strip_edges()
			set_status("施法 · %s" % name_s2)
	else:
		set_status(str(result.get("reason", "施法失败")))


func build_command_card_state(primary: Node3D, ensure_runtime: Callable) -> Dictionary:
	var out := {
		"ability_cd": {},
		"ability_cd_total": {},
		"ability_mana_ok": true,
		"ability_mana_ok_map": {},
		"hero_level": 1,
	}
	if primary == null or not is_instance_valid(primary):
		return out
	var tid := str(primary.get_meta("unit_data", {}).get("typeId", "")).strip_edges()
	if tid.is_empty():
		return out
	if ensure_runtime.is_valid():
		ensure_runtime.call(primary)
	var hl := AbilityCatalog.hero_level_of(primary)
	out["hero_level"] = hl
	out["ability_levels"] = HeroSkill.ability_levels(primary)
	var ab_levels: Dictionary = out["ability_levels"]
	out["hero_skill_points"] = HeroSkill.points_available(primary)
	for abil in CommandButtonCatalog.get_shared().get_all_abil_list(tid):
		var abil_id := str(abil).strip_edges()
		if abil_id.is_empty() or not AbilityCatalog.is_supported(abil_id):
			continue
		var cd := AbilityCooldowns.remaining(primary, abil_id)
		if cd > 0.0:
			out["ability_cd"][abil_id] = cd
		var lv := AbilityCatalog.level_for_unit_type(tid, abil_id, hl, ab_levels)
		var mana_ok := true
		if lv > 0:
			var ab := AbilityCatalog.data(abil_id)
			if ab != null:
				out["ability_cd_total"][abil_id] = maxf(ab.cool_at(lv), 0.0)
				if UnitMana.has_mana(primary):
					mana_ok = UnitMana.can_spend(primary, ab.cost_at(lv))
		out["ability_mana_ok_map"][abil_id] = mana_ok
		if not mana_ok:
			out["ability_mana_ok"] = false
	var av := AvatarController.of(primary)
	if av != null and av.is_active():
		out["avatar_active"] = true
	var auto_out: Dictionary = {}
	for abil_id2 in AbilityAutoCast.map_of(primary).keys():
		auto_out[str(abil_id2)] = AbilityAutoCast.is_enabled(primary, str(abil_id2))
	if not auto_out.is_empty():
		out["ability_autocast"] = auto_out
	return out


static func should_refresh_world(result: Dictionary) -> bool:
	if not bool(result.get("ok", false)):
		return false
	return (
		result.get("unit") is Node3D
		or int(result.get("teleported_count", 0)) > 0
		or int(result.get("hit_count", 0)) > 0
		or float(result.get("heal_amount", 0.0)) > 0.0
		or result.get("buff_target") is Node3D
	)
