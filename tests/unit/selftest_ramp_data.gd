extends SceneTree
## 斜坡 Data / Collect 自测。
## godot --headless --path . -s res://tests/unit/selftest_ramp_data.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_placement()
	_test_collect_empty()
	_test_collect_lost_temple()
	if failed == 0:
		print("selftest_ramp_data: PASS")
		quit(0)
	else:
		push_error("selftest_ramp_data: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _test_placement() -> void:
	var p := Wc3RampPlacement.make(3, 4, "AAHL", 2, 0, "CliffTrans", Wc3RampPlacement.AXIS_V)
	if p.ix != 3 or p.tag != "AAHL" or p.model_dir != "CliffTrans":
		_fail("placement fields")
		return
	print("  placement OK")


func _test_collect_empty() -> void:
	var r := Wc3RampCollectResult.empty_for_size(5, 4)
	if r.romp.size() != 20 or r.romp[0] != Wc3RampCollectResult.ROMP_NONE:
		_fail("empty romp size")
		return
	var stub: Wc3RampCollectResult = Wc3RampLogic.collect_placements({})
	if stub == null:
		_fail("collect empty dict null")
		return
	print("  collect_empty OK")


func _test_collect_lost_temple() -> void:
	var path := "res://assets/map-parsed/losttemple/terrain-heightfield.json"
	if not FileAccess.file_exists(path):
		print("  collect_lt SKIP (no map)")
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var hf: Variant = JSON.parse_string(f.get_as_text())
	var cat := Wc3CliffCatalog.new()
	cat.load_default()
	var r: Wc3RampCollectResult = Wc3RampLogic.collect_placements(hf as Dictionary, {}, cat)
	print(
		"  collect_lt OK placements=%d romp_nonzero=%d"
		% [r.placements.size(), _count_romp(r.romp)]
	)


func _count_romp(romp: PackedByteArray) -> int:
	var n := 0
	for i in range(romp.size()):
		if romp[i] != 0:
			n += 1
	return n
