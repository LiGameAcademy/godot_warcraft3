extends SceneTree

## Phase A：AbilityBehaviorCatalog 注册表一致性。


func _initialize() -> void:
	var failed := false
	failed = _test_supported() or failed
	failed = _test_target_kinds() or failed
	failed = _test_behaviors() or failed
	failed = _test_passive() or failed
	failed = _test_channel() or failed
	if failed:
		push_error("selftest_ability_behavior_catalog: FAIL")
		quit(1)
	else:
		print("selftest_ability_behavior_catalog: PASS")
		quit(0)


func _fail(msg: String) -> bool:
	push_error(msg)
	return true


func _test_supported() -> bool:
	var failed := false
	for id in ["AHwe", "AHbz", "AHmt", "AHtb", "AHtc", "AHav", "Ahea", "Ainf", "Aslo"]:
		if not AbilityCatalog.is_supported(id):
			failed = _fail("%s 应 is_supported" % id) or failed
	if AbilityCatalog.is_supported("AHab"):
		failed = _fail("AHab 被动不应 is_supported") or failed
	if AbilityCatalog.is_supported("AHbh"):
		failed = _fail("AHbh 被动不应 is_supported") or failed
	return failed


func _test_target_kinds() -> bool:
	var failed := false
	var cases := {
		"AHwe": AbilityCatalog.TARGET_SELF,
		"AHtb": AbilityCatalog.TARGET_UNIT,
		"AHtc": AbilityCatalog.TARGET_SELF,
		"Ahea": AbilityCatalog.TARGET_ALLY,
		"Aslo": AbilityCatalog.TARGET_UNIT,
	}
	for id in cases:
		if AbilityCatalog.target_kind(id) != cases[id]:
			failed = _fail("%s target_kind 错误" % id) or failed
	return failed


func _test_behaviors() -> bool:
	var failed := false
	var cases := {
		"AHwe": AbilityBehaviorCatalog.BEHAVIOR_SUMMON_INSTANT,
		"AHbz": AbilityBehaviorCatalog.BEHAVIOR_CHANNEL_AOE,
		"AHmt": AbilityBehaviorCatalog.BEHAVIOR_MASS_TELEPORT,
		"AHtb": AbilityBehaviorCatalog.BEHAVIOR_STORM_BOLT,
		"Ahea": AbilityBehaviorCatalog.BEHAVIOR_HEAL,
		"Aslo": AbilityBehaviorCatalog.BEHAVIOR_SLOW,
	}
	for id in cases:
		if AbilityBehaviorCatalog.behavior_for(id) != cases[id]:
			failed = _fail("%s behavior 错误" % id) or failed
	return failed


func _test_passive() -> bool:
	var failed := false
	if not AbilityCatalog.is_passive_ability("AHab"):
		failed = _fail("AHab 应为被动") or failed
	if AbilityBehaviorCatalog.passive_behavior("AHab") != AbilityBehaviorCatalog.BEHAVIOR_AURA_REGEN_MANA:
		failed = _fail("AHab passive behavior") or failed
	if not AbilityCatalog.is_passive_ability("AHbh"):
		failed = _fail("AHbh 应为被动") or failed
	return failed


func _test_channel() -> bool:
	if not AbilityBehaviorCatalog.is_channel("AHbz"):
		return _fail("AHbz 应为 channel")
	if AbilityBehaviorCatalog.is_channel("AHwe"):
		return _fail("AHwe 不应 channel")
	return false
