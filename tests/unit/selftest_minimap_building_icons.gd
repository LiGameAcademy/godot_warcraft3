extends SceneTree
## godot --headless --path . -s res://tests/unit/selftest_minimap_building_icons.gd
## 小地图分类：金矿球 / 中立小屋(nbmmIcon) / 非 Art 命令按钮。


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var cat := Wc3IdCatalog.new()
	cat.load_default()

	var expect_nbmm := {
		"nmer": true,
		"ntav": true,
		"ngme": true,
		"nmrk": true,
		"ngad": true,
		"nfoh": true,
		"nmh0": false,
	}
	var bad := 0
	for id in expect_nbmm.keys():
		var info: Dictionary = cat.lookup(str(id))
		var got := bool(info.get("nbmm_icon", false))
		var want: bool = expect_nbmm[id]
		var ok := got == want
		print("%s nbmm_icon=%s expect=%s %s" % [id, got, want, "OK" if ok else "FAIL"])
		if not ok:
			bad += 1

	var gold_info: Dictionary = cat.lookup("ngol")
	print("ngol is_building=%s nbmm=%s (金矿走 minimap-gold，不依赖 nbmm)" % [
		bool(gold_info.get("is_building", false)),
		bool(gold_info.get("nbmm_icon", false)),
	])

	for logical in [
		"UI/MiniMap/minimap-gold.png",
		"UI/MiniMap/minimap-neutralbuilding.png",
	]:
		var t := RuntimeAssets.load_converted_texture(logical)
		print("icon %s → %s" % [logical, t != null])
		if t == null:
			bad += 1

	print("RESULT bad=%d" % bad)
	quit(0 if bad == 0 else 1)
