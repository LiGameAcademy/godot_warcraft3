extends Node

var failures := 0
var checks := 0
const MODEL := "res://assets/asset-converted/Units/Human/HeroArchMage/HeroArchMage_portrait.gltf"

var root: Window

func _ready() -> void:
	root = get_tree().root
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PORTRAIT SHUTDOWN: " + label)

func portrait(parent: Node, cache: MapModelCache) -> UnitPortraitView:
	var view := load("res://game/hud/unit_portrait_view.tscn").instantiate() as UnitPortraitView
	parent.add_child(view)
	view.configure(cache, null)
	view._type_id = "Hamg"
	view._pending_path = MODEL
	return view

func run() -> void:
	var cache := MapModelCache.new()
	var host := Control.new()
	root.add_child(host)
	var view := portrait(host, cache)
	view._try_attach_pending(view._load_gen)
	check(view._model_root != null, "正常头像加载真实模型")
	var glow := view._model_root.find_child("TeamGlowBillboard", true, false) as MeshInstance3D
	var original_mesh: Mesh = glow.mesh if glow != null else null
	await get_tree().process_frame
	await get_tree().process_frame
	check(view._vp.render_target_update_mode != SubViewport.UPDATE_DISABLED, "正常延迟设置后头像可见")
	check(glow != null and glow.get_active_material(0) != null and glow.get_surface_override_material(0) == null, "光晕保留有效基础材质且不重复覆盖")
	check(glow != null and glow.mesh != original_mesh and original_mesh.surface_get_material(0) == null, "实例网格修复不修改缓存网格")
	if "--diagnose-material" in OS.get_cmdline_user_args():
		for node in view._model_root.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			for surface in mesh_instance.mesh.get_surface_count():
				print("portrait material: ", node.name, " global=", mesh_instance.material_override, " surface=", mesh_instance.get_surface_override_material(surface), " base=", mesh_instance.mesh.surface_get_material(surface))
	host.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var closing := Control.new()
	root.add_child(closing)
	var pending := portrait(closing, cache)
	closing.queue_free()
	pending._try_attach_pending(pending._load_gen)
	check(pending._model_root == null, "父场景已排队卸载时不创建头像模型")
	await get_tree().process_frame
	await get_tree().process_frame
	var detached_host := Control.new()
	root.add_child(detached_host)
	var detached := portrait(detached_host, cache)
	var generation := detached._load_gen
	root.remove_child(detached_host)
	detached._try_attach_pending(generation)
	check(detached._model_root == null and detached._pending_path.is_empty(), "离树后取消待执行头像任务")
	detached_host.free()
	cache = null
	await get_tree().process_frame
	print("selftest_portrait_shutdown: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)

