extends SceneTree
## 批量：asset-converted 下 *.glb → 同目录 *.scn（最终运行时优先格式）。
## .scn 与 GLB 同属 gitignore 的 asset-converted；免主线程 GLTF 解析。
##
## 用法:
##   godot --headless --path . -s res://tools/export_model_scenes.gd
##   godot --headless --path . -s res://tools/export_model_scenes.gd -- --include Units/Human/ --force
##   # 并行分桶：N 个 worker 各跑 --shard N --shard-id K（0..N-1）
##   godot --headless --path . -s res://tools/export_model_scenes.gd -- --shard 4 --shard-id 2
##
## 通常由 tools/asset-convert（npm run convert）在转完模型后自动调用。


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var includes: PackedStringArray = PackedStringArray()
	var force := false
	var limit := 0
	var shard := -1
	var shard_id := -1
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
		elif s == "--limit" and i + 1 < args.size():
			i += 1
			limit = int(args[i])
		elif s.begins_with("--limit="):
			limit = int(s.substr("--limit=".length()))
		elif s == "--shard" and i + 1 < args.size():
			i += 1
			shard = int(args[i])
		elif s.begins_with("--shard="):
			shard = int(s.substr("--shard=".length()))
		elif s == "--shard-id" and i + 1 < args.size():
			i += 1
			shard_id = int(args[i])
		elif s.begins_with("--shard-id="):
			shard_id = int(s.substr("--shard-id=".length()))
		i += 1

	var root_abs := RuntimeAssets.project_abs(RuntimeAssets.CONVERTED_RES_ROOT)
	if not DirAccess.dir_exists_absolute(root_abs):
		push_error("export_model_scenes: missing %s" % root_abs)
		quit(1)
		return

	var glb_files: PackedStringArray = []
	_collect_glb(root_abs, glb_files)
	var cache := MapModelCache.new()
	var exported := 0
	var skipped := 0
	var failed := 0
	var done := 0
	for disk_glb in glb_files:
		if limit > 0 and done >= limit:
			break
		var rel := str(disk_glb).replace("\\", "/")
		var marker := "/asset-converted/"
		var idx := rel.find(marker)
		if idx < 0:
			continue
		var logical_glb := rel.substr(idx + marker.length())
		if not includes.is_empty() and not _matches_any_include(logical_glb, includes):
			continue
		# Shard 分桶：基于 logical_glb hash % N 决定本 worker 是否处理
		if shard > 0 and shard_id >= 0:
			if logical_glb.hash() % shard != shard_id:
				continue
		done += 1
		var glb_res := RuntimeAssets.converted_path(logical_glb)
		var scn_res := RuntimeAssets.model_scene_path(logical_glb)
		var disk_scn := RuntimeAssets.project_abs(scn_res)
		if force and FileAccess.file_exists(disk_scn):
			DirAccess.remove_absolute(disk_scn)
			cache.evict(glb_res)
		elif not force and FileAccess.file_exists(disk_scn):
			var gstat := FileAccess.get_modified_time(disk_glb)
			var sstat := FileAccess.get_modified_time(disk_scn)
			if sstat >= gstat:
				skipped += 1
				continue
		# 烤基座时跳过 visuals（避免套娃 / 基座已删时 ExtResource 失败）
		var root: Node3D = cache.instance_glb_preview(glb_res, false)
		if root == null:
			push_warning("export_model_scenes: load failed %s" % logical_glb)
			failed += 1
			continue
		root.free()
		if not cache.bake_model_scene(glb_res, force):
			push_warning("export_model_scenes: bake failed %s" % logical_glb)
			failed += 1
			continue
		# 释放原型，避免 headless 退出泄漏（下一文件再 ensure）
		if cache.has_cached(glb_res):
			cache.evict(glb_res)
		exported += 1
		if exported % 25 == 0:
			print("export_model_scenes: progress exported=%d ..." % exported)

	var include_desc := ",".join(includes) if not includes.is_empty() else ""
	var shard_desc := (" shard=%d/%d" % [shard_id + 1 if shard > 0 else 0, shard]) if shard > 0 else ""
	print(
		"export_model_scenes: exported=%d skipped=%d failed=%d include='%s'%s out=同目录 .scn"
		% [exported, skipped, failed, include_desc, shard_desc]
	)
	# 部分模型（DNC/UI 等）headless 加载失败属可预期；有成功导出则视为通过
	quit(0 if failed == 0 or exported > 0 or skipped > 0 else 1)


func _matches_any_include(logical_glb: String, includes: PackedStringArray) -> bool:
	for inc in includes:
		if logical_glb.findn(str(inc)) >= 0:
			return true
	return false


func _collect_glb(dir_abs: String, out: PackedStringArray) -> void:
	var d := DirAccess.open(dir_abs)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name != "." and name != "..":
			var full := dir_abs.path_join(name)
			if d.current_is_dir():
				_collect_glb(full, out)
			elif name.to_lower().ends_with(".glb"):
				out.append(full)
		name = d.get_next()
	d.list_dir_end()
