extends SceneTree

## WC3 技能描述占位符解析（AHwe 水元素为例）。
## godot --headless --path . -s res://tests/unit/selftest_wc3_tooltip_text.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_pick_level()
	_test_pick_level_unquoted_tip()
	_test_resolve_ahwe()
	_test_ahab_passive_tooltip()
	if failed == 0:
		print("selftest_wc3_tooltip_text: PASS")
		quit(0)
	else:
		push_error("selftest_wc3_tooltip_text: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _ahwe_ubertip_l1() -> String:
	return (
		"召唤出一个具有<hwat,realHP>生命值的水元素来帮大魔法师进行战斗。"
		+ "攻击力为<hwat,mindmg1> - <hwat,maxdmg1>点。|n持续<AHwe,Dur1>秒。"
	)


func _test_pick_level() -> void:
	var raw := '"一级","二级","三级"'
	if Wc3TooltipText.pick_level_string(raw, 2) != "二级":
		_fail("pick_level 2 应得 二级")
		return
	print("  pick_level OK")


func _test_pick_level_unquoted_tip() -> void:
	var raw := (
		"辉煌光环 - [|cffffcc00等级 1|r],"
		+ "辉煌光环 - [|cffffcc00等级 2|r],"
		+ "辉煌光环 - [|cffffcc00等级 3|r]"
	)
	var got := Wc3TooltipText.pick_level_string(raw, 1)
	if not got.contains("等级 1") or got.contains("等级 2"):
		_fail("未加引号 Tip 应按 |r], 取等级 1，实际：%s" % got)
		return
	print("  pick_level_unquoted_tip OK")


func _test_resolve_ahwe() -> void:
	var store := root.get_node_or_null("Wc3DefStore")
	if store == null:
		print("  resolve_ahwe SKIP (no Wc3DefStore)")
		return
	var text := Wc3TooltipText.format(_ahwe_ubertip_l1(), 1, false)
	if text.contains("<"):
		_fail("解析后不应残留占位符：%s" % text)
		return
	if not text.contains("450"):
		_fail("应含 hwat 生命值 450，实际：%s" % text)
		return
	if not text.contains("21") or not text.contains("29"):
		_fail("应含攻击力 21-29，实际：%s" % text)
		return
	if not text.contains("60"):
		_fail("应含持续 60 秒，实际：%s" % text)
		return
	print("  resolve_ahwe OK")


func _test_ahab_passive_tooltip() -> void:
	CommandButtonCatalog._shared = null
	var cat := CommandButtonCatalog.get_shared()
	var e := cat.ability_hud_entry(
		"AHab",
		"passive:AHab",
		{
			"enabled": true,
			"passive": true,
			"executing": true,
			"ability_level": 1,
			"badge_level": 1,
			"disabled_reason": "被动光环",
		}
	)
	var tip := str(e.get("tooltip", ""))
	if tip.strip_edges().is_empty():
		_fail("AHab 被动 tooltip 不应为空")
		return
	if not tip.contains("辉煌") or not tip.contains("魔法"):
		_fail("AHab tooltip 应含标题与 Ubertip，实际：%s" % tip)
		return
	if tip.contains("执行中"):
		_fail("被动光环 tooltip 不应含「执行中」")
		return
	print("  ahab_passive_tooltip OK")
