extends SceneTree

## 内容包 Edition：fileVerFlags → *_V1；roc 回退基模。
## godot --headless --path . -s res://tests/unit/selftest_content_pack_rules.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_candidates_helpers()
	_test_catalog_hmpr_tft()
	_test_catalog_hmpr_roc()
	_test_catalog_hfoo_unchanged()
	if failed == 0:
		print("selftest_content_pack_rules: PASS")
		quit(0)
	else:
		push_error("selftest_content_pack_rules: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _test_candidates_helpers() -> void:
	var base := "units/human/Priest/Priest"
	ProjectSettings.set_setting(ContentPackRules.SETTING_ACTIVE_EDITION, ContentPackRules.EDITION_TFT)
	var tft := ContentPackRules.expansion_model_candidates(base, 2)
	if tft.size() < 2 or not str(tft[0]).ends_with("Priest_V1") or str(tft[1]) != base:
		_fail("tft candidates expected […/Priest_V1, base], got %s" % str(tft))
	else:
		print("candidates tft OK")
	ProjectSettings.set_setting(ContentPackRules.SETTING_ACTIVE_EDITION, ContentPackRules.EDITION_ROC)
	var roc := ContentPackRules.expansion_model_candidates(base, 2)
	if roc.size() != 1 or str(roc[0]) != base:
		_fail("roc candidates expected [base] only, got %s" % str(roc))
	else:
		print("candidates roc OK")
	# 还原默认
	ProjectSettings.set_setting(ContentPackRules.SETTING_ACTIVE_EDITION, ContentPackRules.EDITION_TFT)


func _test_catalog_hmpr_tft() -> void:
	ProjectSettings.set_setting(ContentPackRules.SETTING_ACTIVE_EDITION, ContentPackRules.EDITION_TFT)
	var cat := Wc3IdCatalog.new()
	cat.load_default()
	var flags := cat.model_file_ver_flags("hmpr")
	if flags == 0:
		_fail("hmpr file_ver_flags should be non-zero")
		return
	var stem := cat.resolve_model_stem("hmpr")
	if not stem.ends_with("Priest_V1"):
		_fail("hmpr tft stem expected …/Priest_V1, got %s" % stem)
		return
	var glb := cat.converted_glb_path("hmpr")
	if glb.is_empty() or not glb.contains("Priest_V1"):
		_fail("hmpr tft glb expected Priest_V1, got %s" % glb)
		return
	var portrait := cat.portrait_glb_path("hmpr")
	if portrait.is_empty() or not portrait.to_lower().contains("priest_v1"):
		_fail("hmpr tft portrait expected Priest_V1_portrait, got %s" % portrait)
		return
	print("hmpr tft → %s" % glb)


func _test_catalog_hmpr_roc() -> void:
	ProjectSettings.set_setting(ContentPackRules.SETTING_ACTIVE_EDITION, ContentPackRules.EDITION_ROC)
	var cat := Wc3IdCatalog.new()
	cat.load_default()
	var stem := cat.resolve_model_stem("hmpr")
	if stem.ends_with("_V1") or stem.to_lower().ends_with("priest_v1"):
		_fail("hmpr roc stem must not be _V1, got %s" % stem)
		return
	if not stem.get_file().begins_with("Priest"):
		_fail("hmpr roc stem expected Priest*, got %s" % stem)
		return
	var glb := cat.converted_glb_path("hmpr")
	if glb.is_empty() or glb.contains("Priest_V1"):
		_fail("hmpr roc glb must be base Priest, got %s" % glb)
		return
	print("hmpr roc → %s" % glb)
	ProjectSettings.set_setting(ContentPackRules.SETTING_ACTIVE_EDITION, ContentPackRules.EDITION_TFT)


func _test_catalog_hfoo_unchanged() -> void:
	ProjectSettings.set_setting(ContentPackRules.SETTING_ACTIVE_EDITION, ContentPackRules.EDITION_TFT)
	var cat := Wc3IdCatalog.new()
	cat.load_default()
	if cat.model_file_ver_flags("hfoo") != 0:
		_fail("hfoo should have file_ver_flags=0")
		return
	var stem := cat.resolve_model_stem("hfoo")
	if stem.contains("_V1"):
		_fail("hfoo must not resolve _V1, got %s" % stem)
		return
	var glb := cat.converted_glb_path("hfoo")
	if glb.is_empty() or not glb.contains("Footman"):
		_fail("hfoo glb expected Footman, got %s" % glb)
		return
	print("hfoo tft → %s" % glb)
