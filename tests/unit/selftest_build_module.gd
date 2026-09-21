extends Node

## BuildModule 契约：site_lookup_key + construction_key + shutdown 清 Callable。
## 不依赖 Director / MapRoot；只验证无依赖即可确认的契约。

var failures := 0
var checks := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("BUILD MODULE: " + label)


func _ready() -> void:
	var module := BuildModule.new()
	add_child(module)
	module.configure({})

	check(
		module.site_lookup_key("halt", Vector2(64.0, 96.0)) == "halt_64.000_96.000",
		"site_lookup_key 编码 (id, x, y)"
	)
	check(
		module.site_lookup_key("halt", Vector2.INF) == "halt_inf",
		"site_lookup_key 用 INF 占位"
	)
	check(module.construction_key(null) == "", "空 order → 空 key")
	check(module.find_site(Vector2.ZERO, "halt") == null, "未注册时返回 null")

	# BuildOrder (可选)：能不依赖 MapRoot 也可以构造最小测试订单。
	var order := BuildOrder.new()
	order.building_id = "halt"
	order.site_wc3 = Vector2(64.0, 96.0)
	var key := module.construction_key(order)
	check(key == module.site_lookup_key("halt", Vector2(64.0, 96.0)),
		"construction_key 与 site_lookup_key 一致")

	# 不依赖 heightfield 时的 placement 行为：begin 创建控制器，但 update/commit 时
	# 没有 pathing → placement 应仍可 cancel（信号放光 + 工地状态重置）。
	check(module.begin_placement("halt", Vector2.ZERO, true),
		"placement 控制器可被 begin 创建")
	check(module.is_build_targeting(), "begin 后在瞄准态")
	check(module.current_placement_building_id() == "halt", "begin 后 building id 命中")
	check(not module.is_placement_valid(), "缺 heightfield → placement 无效")
	module.cancel_placement()
	check(not module.is_build_targeting(), "cancel 后不在瞄准态")
	check(module._placement != null, "cancel 复用 placement 控制器（不释放）")
	check(module.current_placement_building_id() == "", "cancel 后 building id 清空")

	module.shutdown()
	check(not module._alloc_creation_number.is_valid(), "shutdown 清空注入 Callable")
	check(not module._ground_at_screen.is_valid(), "shutdown 清空 ground_at_screen")

	print("selftest_build_module: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)