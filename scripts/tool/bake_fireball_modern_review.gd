extends SceneTree

## 烤现代火球手测 scn → tmp/model-review/Abilities/Weapons/FireBallMissile/
## godot --headless --path . -s res://scripts/tool/bake_fireball_modern_review.gd

const SRC := "res://assets/asset-converted/Abilities/Weapons/FireBallMissile/FireBallMissile.gltf"
const OUT_DIR := "res://tmp/model-review/Abilities/Weapons/FireBallMissile"
const OUT_SCN := OUT_DIR + "/FireBallMissile_Modern.scn"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var cache := MapModelCache.new()
	var root := cache.instance_glb_preview(SRC, false, false)
	if root == null:
		root = cache.instance_glb(SRC, false)
	if root == null:
		push_error("bake_fireball_modern_review: load fail")
		quit(1)
		return
	cache.prepare_fx_model(root, SRC)
	if not bool(root.get_meta(FireballMissileModern.META_APPLIED, false)):
		FireballMissileModern.apply(root)
	if not bool(root.get_meta(FireballMissileModern.META_APPLIED, false)):
		push_error("bake_fireball_modern_review: modern apply failed")
		quit(1)
		return
	# 确保控制器进树后切到飞行态
	var ctrl := root.find_child(FireballMissileModern.NODE_CONTROLLER, true, false)
	if ctrl != null and ctrl.has_method("set_flight_mode"):
		ctrl.call("set_flight_mode")
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var err := RuntimeAssets.save_packed_scene(root, OUT_SCN)
	root.free()
	if err != OK:
		push_error("bake_fireball_modern_review: save failed %s" % err)
		quit(1)
		return
	print("bake_fireball_modern_review: OK → %s" % OUT_SCN)
	quit(0)
