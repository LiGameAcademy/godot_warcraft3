extends SceneTree
## 自测：Lost Temple 装饰物 GLB 解析 + 放置统计。


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog := Wc3IdCatalog.new()
	catalog.load_default()
	var cache := MapModelCache.new()
	var layer := MapDoodadLayer.new()
	layer.setup(catalog, cache)

	var path := "res://assets/map-parsed/losttemple/doodads.json"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("selftest: missing %s" % path)
		quit(1)
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("selftest: bad doodads JSON")
		quit(1)
		return

	var root := Node3D.new()
	root.add_child(layer)
	var ctx := MapBuildContext.new()
	ctx.doodads = data as Dictionary
	layer.build(ctx)
	print(
		"selftest Doodads: placed=%d placeholder=%d children=%d"
		% [layer.last_placed, layer.last_placeholder, layer.get_child_count()]
	)
	if layer.last_placed <= 0:
		push_error("selftest: expected doodads placed")
		quit(1)
		return
	if layer.last_placeholder > layer.last_placed / 2:
		push_warning("selftest: many placeholders (%d)" % layer.last_placeholder)

	# 蝙蝠 NObt：应有动画且不走 MultiMesh
	var bats_glb := catalog.converted_glb_path("NObt", 0)
	if bats_glb.is_empty() or not cache.glb_has_animation(bats_glb):
		push_error("selftest: NObt GLB missing Stand animation")
		quit(1)
		return
	if layer.get_node_or_null("MM_NObt_0") != null:
		push_error("selftest: NObt should not use MultiMesh")
		quit(1)
		return
	var bat_playing := 0
	for c in layer.get_children():
		if not str(c.name).begins_with("NObt_"):
			continue
		var ap := _find_ap(c)
		if ap and ap.is_playing():
			bat_playing += 1
	if bat_playing <= 0:
		push_error("selftest: expected NObt AnimationPlayer playing Stand")
		quit(1)
		return
	print("selftest NObt: animated playing=%d" % bat_playing)

	# 抽查雪树 MultiMesh 是否含 ≥2 个 Part（树干+树叶）
	var tree_mm := layer.get_node_or_null("MM_WTst_0") as Node3D
	if tree_mm == null:
		push_error("selftest: WTst should still use MultiMesh (static stand)")
		quit(1)
		return
	if tree_mm.get_child_count() < 1:
		push_error("selftest: WTst multimesh empty")
		quit(1)
		return
	print("selftest Doodads OK (WTst parts=%d)" % tree_mm.get_child_count())
	root.free()
	quit(0)


func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var found := _find_ap(c)
		if found:
			return found
	return null
