extends Node
## 方案 B dry-run v5 — 直接调用 export_model_scenes 的核心逻辑
## (绕开 .gdignore 走 disk path)

const PROJECT_PATH := "D:/GodotProject/laoli_gamedev_godot4_course/godot_warcraft3"
const SCN_PATH := "res://tools/dryrun/scenes/FireBallMissile.scn"
const GLB_RES := "res://assets/asset-converted/Abilities/Weapons/FireBallMissile/FireBallMissile.gltf"
const POST_BAKE_SCN := "res://tools/dryrun/scenes/FireBallMissile_post_bake.scn"
const REPORT_PATH := "res://tools/dryrun/plan_b_report.txt"

var _buf: PackedStringArray = PackedStringArray()
var _done := false

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	if _done:
		return
	_done = true
	_report("FireBallMissile dry-run v5 (compare BEFORE / AFTER plan-B)")
	_report("==========================================")

	# 1) 加载旧 scn，列出 BEFORE 状态
	_report("\n=== BEFORE 现有 scn ===")
	var packed: PackedScene = ResourceLoader.load(SCN_PATH)
	if packed == null:
		_report("❌ load 失败: " + SCN_PATH)
		_finish(1)
		return
	var before_root: Node = packed.instantiate()
	before_root.name = "FireBallMissile_BEFORE"
	add_child(before_root)
	await get_tree().process_frame
	_walk_verbose(before_root, 0)

	# 2) 用 export_model_scenes 跑一次 force 重烤
	# 绕开 res:// — 直接 import gltf 路径
	_report("\n\n=== 执行 export_model_scenes (--include FireBallMissile --force) ===")
	var ExportScript := preload("res://scripts/tool/export_model_scenes.gd")
	var export_tree := ExportScript.new()
	export_tree._initialize()
	_report("切换方案：手动模拟 export_model_scenes 跑 FireBallMissile force")

	# 用 res:// 路径加载 glb
	_report("加载 glb res: " + GLB_RES)
	_report("ResourceLoader.exists: " + str(ResourceLoader.exists(GLB_RES)))
	# 直接 GLTFDocument parse disk path
	var doc := GLTFDocument.new()
	var glb_disk := PROJECT_PATH + "/assets/asset-converted/Abilities/Weapons/FireBallMissile/FireBallMissile.gltf"
	_report("GLTFDocument.parse disk: " + glb_disk)
	var states := GLTFState.new()
	var err := doc.append_from_file(glb_disk, states)
	_report("parse err: " + str(err))
	if err != OK:
		_report("❌ gltf parse 失败")
		_finish(1)
		return
	var glb_root: Node3D = doc.generate_scene(states)
	_report("gltf root: " + str(glb_root) + " kids=" + str(glb_root.get_child_count() if glb_root else -1))
	if glb_root == null:
		_finish(1)
		return
	# bake_model_scene 要 disk path; 直接看 cache 内部
	var cache := MapModelCache.new()
	# 强制走 disk path（绕开 res://）
	var baked: bool = cache.bake_model_scene(glb_disk, true)
	_report("bake_model_scene(force=true) → " + str(baked))

	await get_tree().process_frame

	# 3) 加载新 scn 列出 AFTER
	_report("\n\n=== AFTER 重新 bake ===")
	var scn_res := "res://assets/asset-converted/Abilities/Weapons/FireBallMissile/FireBallMissile.scn"
	_report("scn res: " + scn_res + " exists=" + str(ResourceLoader.exists(scn_res)))
	if ResourceLoader.exists(scn_res):
		var packed2: PackedScene = ResourceLoader.load(scn_res)
		if packed2 != null:
			var after_root: Node = packed2.instantiate()
			after_root.name = "FireBallMissile_AFTER"
			add_child(after_root)
			await get_tree().process_frame
			_walk_verbose(after_root, 0)
			_report("plan_b_promoted: " + str(after_root.get_meta("wc3_fx_plan_b_promoted", -1)))
		else:
			_report("❌ AFTER scn load 失败")

	await get_tree().process_frame
	_finish(0)

func _walk_verbose(n: Node, depth: int) -> void:
	var kind := _kind_of(n)
	var aabb_str := "-"
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			var aabb := mi.get_aabb()
			aabb_str = "size=(%.1f,%.1f,%.1f) tri=%d" % [aabb.size.x, aabb.size.y, aabb.size.z, mi.mesh.get_faces().size()/3]
		else:
			aabb_str = "mesh=<null>"
	var meta_str := ""
	for k in ["wc3_fx_mesh_kind", "wc3_fx_presented", "wc3_fx_replaced_source", "wc3_fx_plan_b"]:
		if n.has_meta(k):
			meta_str += " " + k + "=" + str(n.get_meta(k))
	var indent := "  ".repeat(depth)
	_report("%s- %s [%s] %s%s owner=%s kids=%d" % [indent, n.name, kind, aabb_str, meta_str, "<set>" if n.owner != null else "<null>", n.get_child_count()])
	for c in n.get_children():
		_walk_verbose(c, depth + 1)

func _kind_of(n: Node) -> String:
	if n is MeshInstance3D:
		return "MeshInstance3D"
	if n is GPUParticles3D:
		return "GPUParticles3D"
	if n is AnimationPlayer:
		return "AnimationPlayer"
	if n is Skeleton3D:
		return "Skeleton3D"
	if n is BoneAttachment3D:
		return "BoneAttachment3D"
	if n is Node3D:
		return "Node3D"
	return n.get_class()

func _report(s: String) -> void:
	print(s)
	_buf.append(s)

func _flush() -> void:
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f == null:
		print("❌ 无法写报告: " + REPORT_PATH)
		return
	f.store_string("\n".join(_buf))
	f.close()

func _finish(code: int) -> void:
	_flush()
	get_tree().quit(code)
