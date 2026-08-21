extends SceneTree
## 批量：为 bake .scn 写薄继承场景 → assets/visuals/**/*.tscn。
## 不 pack 网格；只写 instance 基座 .scn + ModelVisualSync。
## PE2 已打进基座 .scn，不再 ExtResource pe2.tscn。
##
## 用法:
##   godot --headless --path . -s res://scripts/tool/export_visual_scenes.gd
##   godot --headless --path . -s res://scripts/tool/export_visual_scenes.gd -- --include Buildings/Human/TownHall --force
##
## 运行时 MapModelCache 优先 visuals；ExtResource 基座若因 .gdignore 加载失败则运行时拼装。

const _SYNC_SCRIPT_PATH := "res://scripts/presentation/wc3_model/wc3_model_scene.gd"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var includes: PackedStringArray = PackedStringArray()
	var force := false
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var s := str(args[i])
		if s == "--force":
			force = true
		elif s == "--include" and i + 1 < args.size():
			i += 1
			includes.append(str(args[i]).replace("\\", "/"))
		elif s.begins_with("--include="):
			includes.append(s.substr("--include=".length()).replace("\\", "/"))
		i += 1

	var root_abs := RuntimeAssets.project_abs(RuntimeAssets.CONVERTED_RES_ROOT)
	if not DirAccess.dir_exists_absolute(root_abs):
		push_error("export_visuals: missing %s" % root_abs)
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(
		RuntimeAssets.project_abs(RuntimeAssets.VISUALS_RES_ROOT)
	)

	var scn_files: PackedStringArray = []
	_collect_scn(root_abs, scn_files)
	var exported := 0
	var skipped := 0
	var failed := 0

	for disk_scn in scn_files:
		var rel := str(disk_scn).replace("\\", "/")
		var marker := "/asset-converted/"
		var idx := rel.find(marker)
		if idx < 0:
			continue
		var logical_scn := rel.substr(idx + marker.length())
		if not includes.is_empty() and not _matches_any_include(logical_scn, includes):
			continue
		var logical_glb := logical_scn
		if logical_glb.to_lower().ends_with(".scn"):
			logical_glb = logical_glb.substr(0, logical_glb.length() - 4) + ".glb"

		var scn_res := RuntimeAssets.model_scene_path(logical_glb)
		var vis_res := RuntimeAssets.visual_scene_path(logical_glb)
		var disk_vis := RuntimeAssets.project_abs(vis_res)
		if not force and FileAccess.file_exists(disk_vis):
			var vstat := FileAccess.get_modified_time(disk_vis)
			var sstat := FileAccess.get_modified_time(disk_scn)
			if vstat >= sstat:
				skipped += 1
				continue

		var base_packed := RuntimeAssets.load_packed_scene(scn_res)
		if base_packed == null:
			push_warning("export_visuals: missing base scn %s" % scn_res)
			failed += 1
			continue
		var probe: Node = base_packed.instantiate()
		if probe == null or not (probe is Node3D):
			push_warning("export_visuals: instantiate failed %s" % scn_res)
			if probe:
				probe.free()
			failed += 1
			continue

		var root_name := str(probe.name)
		probe.free()

		var text := _build_inherited_tscn(root_name, scn_res)
		DirAccess.make_dir_recursive_absolute(disk_vis.get_base_dir())
		var f := FileAccess.open(disk_vis, FileAccess.WRITE)
		if f == null:
			push_warning("export_visuals: write failed %s" % disk_vis)
			failed += 1
			continue
		f.store_string(text)
		f.close()
		exported += 1

	var include_desc := ",".join(includes) if not includes.is_empty() else ""
	print(
		"export_visuals: exported=%d skipped=%d failed=%d include='%s' out=%s"
		% [exported, skipped, failed, include_desc, RuntimeAssets.VISUALS_RES_ROOT]
	)
	quit(0 if failed == 0 else 1)


func _build_inherited_tscn(root_name: String, scn_res: String) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[gd_scene load_steps=2 format=3]\n")
	lines.append("\n")
	lines.append('[ext_resource type="PackedScene" path="%s" id="1_base"]\n' % scn_res)
	lines.append('[ext_resource type="Script" path="%s" id="2_sync"]\n' % _SYNC_SCRIPT_PATH)
	lines.append("\n")
	lines.append('[node name="%s" instance=ExtResource("1_base")]\n' % root_name)
	lines.append('script = ExtResource("2_sync")\n')
	return "".join(lines)


func _matches_any_include(logical: String, includes: PackedStringArray) -> bool:
	for inc in includes:
		if logical.findn(str(inc)) >= 0:
			return true
	return false


func _collect_scn(dir_abs: String, out: PackedStringArray) -> void:
	var d := DirAccess.open(dir_abs)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name != "." and name != "..":
			var full := dir_abs.path_join(name)
			if d.current_is_dir():
				_collect_scn(full, out)
			elif name.to_lower().ends_with(".scn"):
				out.append(full)
		name = d.get_next()
	d.list_dir_end()
