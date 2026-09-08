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
	_check_brilliance_ground_ring()
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
	if bool(root.get_meta(FireballMissileModern.META_APPLIED, false)):
		var core := root.find_child("Core", true, false)
		var trail := root.find_child("FlameTrail", true, false)
		if core == null or trail == null:
			_fail("FireBallMissile modern: missing Core/FlameTrail")
		else:
			print("FireBallMissile: modern Core+FlameTrail OK")
	else:
		var bbs := _count_fx_billboards(root)
		if bbs < 1:
			_fail("FireBallMissile: expected ≥1 FxBillboard or modern, got %d" % bbs)
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


func _check_brilliance_ground_ring() -> void:
	# 脚底水平环：勿被当成飞弹广告牌竖在身前
	var root := _load_fx("Abilities/Spells/Human/Brilliance/Brilliance.gltf")
	if root == null:
		return
	var bbs := _count_fx_billboards(root)
	if bbs > 0:
		_fail("Brilliance: expected KEEP ground ring (0 billboard), got %d" % bbs)
	else:
		print("Brilliance: keep horizontal ground ring OK")
	root.free()
	var aura := _load_fx("Abilities/Spells/Other/GeneralAuraTarget/GeneralAuraTarget.gltf")
	if aura == null:
		return
	bbs = _count_fx_billboards(aura)
	if bbs > 0:
		_fail("GeneralAuraTarget: expected KEEP ground disk, got %d" % bbs)
	else:
		print("GeneralAuraTarget: keep ground disk OK")
	aura.free()
