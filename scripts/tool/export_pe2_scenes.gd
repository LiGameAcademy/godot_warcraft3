extends SceneTree
## 已弃用：PE2 由 bake:scn（wc3_scn_pe2.gd）打进 .scn。
## 保留此脚本仅供调试单独导出 GPUParticles 预制；默认管线不再调用。
##
##   godot --headless --path . -s res://scripts/tool/export_pe2_scenes.gd -- --include Buildings/Human/ --force

const _Pe2 := preload("res://scripts/map/presentation/effects/wc3_pe2_particles.gd")


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
		push_error("export_pe2: missing %s" % root_abs)
		quit(1)
		return

	var prefab_root_abs := RuntimeAssets.project_abs(RuntimeAssets.PE2_PREFABS_RES_ROOT)
	DirAccess.make_dir_recursive_absolute(prefab_root_abs)

	var json_files: PackedStringArray = []
	_collect_pe2_json(root_abs, json_files)
	var exported := 0
	var skipped := 0
	var failed := 0
	for disk_json in json_files:
		var rel := str(disk_json).replace("\\", "/")
		var marker := "/asset-converted/"
		var idx := rel.find(marker)
		if idx < 0:
			continue
		var logical_json := rel.substr(idx + marker.length())
		if not includes.is_empty() and not _matches_any_include(logical_json, includes):
			continue
		var logical_glb := logical_json
		if logical_glb.ends_with(".pe2.json"):
			logical_glb = logical_glb.substr(0, logical_glb.length() - ".pe2.json".length()) + ".glb"
		var res_tscn := RuntimeAssets.pe2_prefab_path(logical_glb)
		var disk_tscn := RuntimeAssets.project_abs(res_tscn)
		if not force and FileAccess.file_exists(disk_tscn):
			var jstat := FileAccess.get_modified_time(disk_json)
			var tstat := FileAccess.get_modified_time(disk_tscn)
			if tstat >= jstat:
				skipped += 1
				continue
		var glb_res := RuntimeAssets.converted_path(logical_glb)
		var root: Node3D = _Pe2.build_root_from_glb(glb_res)
		if root == null:
			skipped += 1
			continue
		var packed := PackedScene.new()
		var pack_err := packed.pack(root)
		if pack_err != OK:
			push_warning("export_pe2: pack failed %s (%s)" % [logical_json, error_string(pack_err)])
			root.free()
			failed += 1
			continue
		DirAccess.make_dir_recursive_absolute(disk_tscn.get_base_dir())
		var save_err := ResourceSaver.save(packed, res_tscn)
		root.free()
		if save_err != OK:
			push_warning("export_pe2: save failed %s (%s)" % [res_tscn, error_string(save_err)])
			failed += 1
			continue
		exported += 1

	print(
		"export_pe2: exported=%d skipped=%d failed=%d include='%s' out=%s"
		% [exported, skipped, failed, ",".join(includes), RuntimeAssets.PE2_PREFABS_RES_ROOT]
	)
	quit(0 if failed == 0 or exported > 0 else 1)


func _matches_any_include(logical: String, includes: PackedStringArray) -> bool:
	for inc in includes:
		if logical.findn(inc) >= 0:
			return true
	return false


func _collect_pe2_json(dir_abs: String, out: PackedStringArray) -> void:
	var d := DirAccess.open(dir_abs)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name != "." and name != "..":
			var full := dir_abs.path_join(name)
			if d.current_is_dir():
				_collect_pe2_json(full, out)
			elif name.ends_with(".pe2.json"):
				var f := FileAccess.open(full, FileAccess.READ)
				if f != null:
					var text := f.get_as_text()
					f.close()
					if text.contains("\"emitters\"") and not (
						text.contains("\"emitters\": []") or text.contains('"emitters":[]')
					):
						out.append(full)
		name = d.get_next()
	d.list_dir_end()
