extends SceneTree

## Wc3FxPresenter 语义分类：FireBall 软球、Arrow 广告牌、Axe 保留实体。
## godot --headless --path . -s res://tests/unit/selftest_wc3_fx_presenter.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_fireball()
	_check_arrow()
	_check_axe()
	if failed == 0:
		print("selftest_wc3_fx_presenter: PASS")
		quit(0)
	else:
		push_error("selftest_wc3_fx_presenter: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _load_fx(logical_gltf: String) -> Node3D:
	var path := "res://assets/asset-converted/%s" % logical_gltf
	var cache := MapModelCache.new()
	# prefer gltf path through ensure; bake may exist
	var root := cache.instance_glb_preview(path, false, false)
	if root == null:
		root = cache.instance_glb(path, false)
	if root == null:
		_fail("load fail %s" % logical_gltf)
		return null
	cache.prepare_fx_model(root)
	return root


func _count_fx_billboards(root: Node) -> int:
	var n := 0
	for c in root.find_children("FxBillboard", "MeshInstance3D", true, false):
		n += 1
	for c in root.find_children("*FxBillboard*", "MeshInstance3D", true, false):
		if str(c.name) != "FxBillboard":
			n += 1
	return n


func _check_fireball() -> void:
	var root := _load_fx("Abilities/Weapons/FireBallMissile/FireBallMissile.gltf")
	if root == null:
		return
	var bbs := _count_fx_billboards(root)
	if bbs < 1:
		_fail("FireBallMissile: expected ≥1 FxBillboard, got %d" % bbs)
	else:
		print("FireBallMissile: billboards=%d OK" % bbs)
	root.free()


func _check_arrow() -> void:
	var root := _load_fx("Abilities/Weapons/Arrow/ArrowMissile.gltf")
	if root == null:
		return
	var bbs := _count_fx_billboards(root)
	if bbs < 1:
		_fail("ArrowMissile: expected textured FxBillboard, got %d" % bbs)
	else:
		print("ArrowMissile: billboards=%d OK" % bbs)
	root.free()


func _check_axe() -> void:
	var root := _load_fx("Abilities/Weapons/Axe/AxeMissile.gltf")
	if root == null:
		return
	var bbs := _count_fx_billboards(root)
	# 实体斧头应 KEEP，不应被改成软球
	if bbs > 0:
		_fail("AxeMissile: expected KEEP mesh (0 billboard), got %d" % bbs)
	else:
		print("AxeMissile: keep solid mesh OK")
	root.free()
