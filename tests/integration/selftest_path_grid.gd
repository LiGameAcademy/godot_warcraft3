extends SceneTree
## 直崖拓扑与斜坡 Collect 分离烟雾测试。
## godot --headless -s res://tests/integration/selftest_path_grid.gd


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var path := "res://assets/map-parsed/losttemple/terrain-heightfield.json"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("missing heightfield")
		quit(1)
		return
	var raw: Variant = JSON.parse_string(f.get_as_text())
	var hf := Wc3Heightfield.from_dict(raw as Dictionary, false)
	var cat := Wc3CliffCatalog.new()
	cat.load_default()
	var topo: Wc3CliffTopologyResult = Wc3CliffLogic.build_topology(hf, cat)
	var ramp: Wc3RampCollectResult = Wc3RampLogic.collect_placements(hf, {}, cat)
	print(
		"selftest_path_grid: cliff=%d ramp_models=%d cliff_gap=%d entrance_sample=%s"
		% [
			topo.placements.size(),
			ramp.non_phantom_count() if ramp else 0,
			_count_ones(topo.gap_mask),
			str(_sample_entrance(hf)),
		]
	)
	quit(0)


func _count_ones(mask: PackedByteArray) -> int:
	var n := 0
	for i in range(mask.size()):
		if mask[i] != 0:
			n += 1
	return n


func _sample_entrance(hf: Wc3Heightfield) -> bool:
	var w: int = hf.width
	var h: int = hf.height
	for y in range(mini(h - 1, 40)):
		for x in range(mini(w - 1, 40)):
			if Wc3RampCollect.is_entrance(hf.flags_packed, hf.layer_heights, w, h, x, y):
				return true
	return false
