extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PATCH UNIT DATA: " + label)

func run() -> void:
	var store: Variant = root.get_node("Wc3DefStore")
	# 本地已验证补丁的回归锚点；更换经典基准版本时应重新对照来源。
	check(BuildingCatalog.get_hp("hrif") == 505, "补丁火枪手505生命")
	check(BuildingCatalog.get_hp("hkni") == 835, "补丁骑士835生命")
	check(BuildingCatalog.get_gold_cost("hlum") == 120, "补丁伐木场120金")
	var tables := ["UnitBalance", "UnitData", "UnitUI", "UnitWeapons", "UnitAbilities"]
	# UI 注册名来自定义类，避免文件名大小写造成误报。
	tables[2] = UnitUiDef.TABLE_NAME
	for id in ["Nfir", "Nalc", "Ntin", "nlv1"]:
		for table in tables:
			store.ensure_table(table)
			check(store.get_row(table, id) != null, "%s/%s补丁关联行" % [table, id])
	store.ensure_table("AbilityData")
	var missing: Array[String] = []
	for id in store.get_ids("UnitAbilities"):
		var row := store.get_row("UnitAbilities", id) as UnitAbilitiesDef
		for ability_id in row.all_ability_ids():
			if store.get_row("AbilityData", ability_id) == null:
				missing.append("%s:%s" % [id, ability_id])
	check(missing.is_empty(), "全部单位技能引用存在：%s" % str(missing))
	print("selftest_patch_unit_data: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)

