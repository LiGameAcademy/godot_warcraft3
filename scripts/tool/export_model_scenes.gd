extends SceneTree
## 批量：asset-converted 下 *.gltf/.glb → 同目录 *.scn（最终运行时优先格式）。
## .scn 与模型同属 gitignore 的 asset-converted；免主线程 GLTF 解析。
##
## 用法:
##   godot --headless --path . -s res://scripts/tool/export_model_scenes.gd
##   godot --headless --path . -s res://scripts/tool/export_model_scenes.gd -- --include Units/Human/ --force
##
## 通常由 tools/asset-convert（npm run convert）在转完模型后自动调用。
## 若环境变量 PIPELINE_LOG 已设，进度/警告/错误会追加到该 Markdown 文档。

# SplitMeshesByGroup 是 class_name，全局可用
const SplitMeshesByGroupScript := preload("res://scripts/tool/split_meshes_by_group.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var includes: PackedStringArray = PackedStringArray()
	var force := false
	var limit := 0
	var shard := 1
	var shard_id := 0
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
			shard = maxi(int(args[i]), 1)
		elif s.begins_with("--shard="):
			shard = maxi(int(s.substr("--shard=".length())), 1)
		elif s == "--shard-id" and i + 1 < args.size():
			i += 1
			shard_id = int(args[i])
		elif s.begins_with("--shard-id="):
			shard_id = int(s.substr("--shard-id=".length()))
		i += 1

	var root_abs := RuntimeAssets.project_abs(RuntimeAssets.CONVERTED_RES_ROOT)
	if not DirAccess.dir_exists_absolute(root_abs):
		_plog("FATAL", "export_model_scenes: missing %s" % root_abs)
		push_error("export_model_scenes: missing %s" % root_abs)
		quit(1)
		return

	var glb_files: PackedStringArray = []
	_collect_glb(root_abs, glb_files)
	glb_files.sort()
	if shard > 1:
		var filtered: PackedStringArray = []
		var root_norm := root_abs.replace("\\", "/")
		for p in glb_files:
			var logical := str(p).replace("\\", "/").replace(root_norm + "/", "")
			if logical.hash() % shard == shard_id:
				filtered.append(p)
		glb_files = filtered
	var found_msg := (
		"export_model_scenes: found %d model files under asset-converted (shard %d/%d)"
		% [glb_files.size(), shard_id, shard]
	)
	print(found_msg)
	_plog("INFO", found_msg)
	var cache := MapModelCache.new()
	var exported := 0
	var skipped := 0
	var failed := 0
	var done := 0
	var considered := 0
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
		# 已标 .no-scn 的 GLB 跳过（粒子/装饰/水相关/Portrait 等不需要 scn）
		if _is_no_scn(logical_glb):
			skipped += 1
			considered += 1
			if considered % 50 == 0:
				_progress_line(considered, exported, skipped, failed)
			continue
		done += 1
		considered += 1
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
				if considered % 50 == 0:
					_progress_line(considered, exported, skipped, failed)
				continue
		# 烤基座时跳过 visuals（避免套娃 / 基座已删时 ExtResource 失败）
		var root: Node3D = cache.instance_glb_preview(glb_res, false)
		if root == null:
			_plog("WARN", "export_model_scenes: load failed %s" % logical_glb)
			print("  ⚠ load failed %s" % logical_glb)
			failed += 1
			continue
		# C-2: 拼装 attachments 到 _scene_cache 里的 proto（不是临时 inst）
		# 这样 cache.bake_model_scene 烤出 .scn 时已含 attachment 节点
		var att_data := _read_attachments(logical_glb)
		var proto := cache.get_proto(glb_res)
		if proto != null and not att_data.is_empty():
			# C-3: 先按 VertexGroup 拆 mesh（修"小配件位置错乱"），再拼 attachment 节点
			_split_meshes_by_group(proto, att_data)
			_assemble_attachments(proto, att_data)
			# 拆组后原 Geoset_N 节点已删；必须重注 :visible → Geoset_N_Group_*
			if cache.has_method("reinject_geoset_vis_tracks"):
				cache.reinject_geoset_vis_tracks(glb_res)
			# Stand_Work*：腰带斧 hide-scale 会把 AxHandle 上的施工锤一起缩没 → 对齐左手并取消 hide
			var work_fix := _fix_work_tool_anims(proto)
			if work_fix > 0:
				_plog("INFO", "fix_work_tool_anims: %d sequences (%s)" % [work_fix, logical_glb])
		root.free()
		if not cache.bake_model_scene(glb_res, force):
			_plog("WARN", "export_model_scenes: bake failed %s" % logical_glb)
			print("  ⚠ bake failed %s" % logical_glb)
			failed += 1
			continue
		# 释放原型，避免 headless 退出泄漏（下一文件再 ensure）
		if cache.has_cached(glb_res):
			cache.evict(glb_res)
		exported += 1
		if considered % 25 == 0:
			_progress_line(considered, exported, skipped, failed)

	var include_desc := ",".join(includes) if not includes.is_empty() else ""
	var done_msg := (
		"export_model_scenes: exported=%d skipped=%d failed=%d include='%s' out=同目录 .scn"
		% [exported, skipped, failed, include_desc]
	)
	print(done_msg)
	_plog("INFO", done_msg)
	# 部分模型（DNC/UI 等）headless 加载失败属可预期；有成功导出则视为通过
	quit(0 if failed == 0 or exported > 0 or skipped > 0 else 1)


func _progress_line(considered: int, exported: int, skipped: int, failed: int) -> void:
	var msg := (
		"export_model_scenes: progress considered=%d exported=%d skipped=%d failed=%d ..."
		% [considered, exported, skipped, failed]
	)
	print(msg)
	_plog("PROGRESS", msg)


## 追加到 PIPELINE_LOG（gitignore 的进度文档）；未设置则静默。
func _plog(level: String, message: String, detail: String = "") -> void:
	var log_path := OS.get_environment("PIPELINE_LOG")
	if log_path.is_empty():
		return
	var f := FileAccess.open(log_path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(log_path, FileAccess.WRITE_READ)
	if f == null:
		return
	f.seek_end()
	var t := Time.get_time_string_from_system()
	f.store_string("- **%s** `%s` %s\n" % [t, level, message])
	if not detail.is_empty():
		f.store_string("  ```\n%s\n  ```\n" % detail)
	f.store_string("\n")
	f.close()


func _matches_any_include(logical_glb: String, includes: PackedStringArray) -> bool:
	for inc in includes:
		if logical_glb.findn(str(inc)) >= 0:
			return true
	return false


## C-2: 读 .attachments.json sidecar（路径同 .gltf）。
## 读失败或文件不存在 → 返回空 Dictionary。
func _read_attachments(logical_glb: String) -> Dictionary:
	# logical_glb = "Buildings/Human/TownHall/TownHall.gltf"
	# -> 替换 .gltf 为 .attachments.json
	var att_path := logical_glb
	if att_path.to_lower().ends_with(".gltf"):
		att_path = att_path.substr(0, att_path.length() - 5) + ".attachments.json"
	elif att_path.to_lower().ends_with(".glb"):
		att_path = att_path.substr(0, att_path.length() - 4) + ".attachments.json"
	else:
		return {}
	# 关键：必须含 res:// 前缀 + assets/asset-converted/，project_abs 才正确解析
	var disk := RuntimeAssets.project_abs("res://assets/asset-converted/" + att_path)
	if not FileAccess.file_exists(disk):
		return {}
	var f := FileAccess.open(disk, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return data


## C-3: 按 VertexGroup 拆 geoset mesh（实现抽到 scripts/tool/split_meshes_by_group.gd）
func _split_meshes_by_group(proto: Node, att_data: Dictionary) -> int:
	var n: int = SplitMeshesByGroupScript.split(proto, att_data)
	if n > 0:
		_plog("INFO", "split_meshes_by_group: groups=%d" % n)
	return n


## Stand_Work*：MDX 用 AxHandle01.scale≈0 藏腰带斧，但施工锤同骨 → Godot 里锤消失。
## 若存在绑在 AxHandle01 上的 Geoset BA：把 Work 动画里 AxHandle 的位姿对齐 Bone_Hand_L，scale 置 1。
func _fix_work_tool_anims(proto: Node) -> int:
	if proto == null or not _has_axhandle_tool_ba(proto):
		return 0
	var ap := _find_animation_player(proto)
	if ap == null:
		return 0
	var fixed := 0
	for anim_name in ap.get_animation_list():
		if not _is_stand_work_anim(str(anim_name)):
			continue
		var anim: Animation = ap.get_animation(anim_name)
		if anim == null:
			continue
		if _patch_stand_work_anim(anim):
			fixed += 1
	return fixed


func _has_axhandle_tool_ba(proto: Node) -> bool:
	for c in proto.find_children("*", "BoneAttachment3D", true, false):
		var ba := c as BoneAttachment3D
		if ba == null:
			continue
		if ba.bone_name != "AxHandle01":
			continue
		var nm := str(ba.name)
		if nm.begins_with("Geoset_") or nm.contains("Weapon"):
			return true
	return false


func _is_stand_work_anim(anim_name: String) -> bool:
	var leaf := _anim_leaf_name(anim_name).replace(" ", "_").to_lower()
	return (
		leaf == "stand_work"
		or leaf == "stand_work_gold"
		or leaf == "stand_work_lumber"
	)


func _anim_leaf_name(anim_path: String) -> String:
	var i := anim_path.rfind("/")
	return anim_path.substr(i + 1) if i >= 0 else anim_path


func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	var found: Array[Node] = n.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		return null
	return found[0] as AnimationPlayer


## 从轨路径解析骨名（`Skeleton3D:AxHandle01` / `...:AxHandle01:scale`）。
func _bone_name_from_track_path(path: NodePath) -> String:
	var parts := str(path).split(":")
	if parts.is_empty():
		return ""
	var last := str(parts[parts.size() - 1])
	if last in ["position", "rotation", "scale", "visible", "transform"]:
		if parts.size() >= 2:
			return str(parts[parts.size() - 2])
		return ""
	return last


func _patch_stand_work_anim(anim: Animation) -> bool:
	var ax_pos := -1
	var ax_rot := -1
	var ax_scale := -1
	var hand_pos := -1
	var hand_rot := -1
	for i in range(anim.get_track_count()):
		var bone := _bone_name_from_track_path(anim.track_get_path(i))
		var ttype := anim.track_get_type(i)
		var is_pos := (
			ttype == Animation.TYPE_POSITION_3D
			or str(anim.track_get_path(i)).ends_with(":position")
		)
		var is_rot := (
			ttype == Animation.TYPE_ROTATION_3D
			or str(anim.track_get_path(i)).ends_with(":rotation")
		)
		var is_scale := (
			ttype == Animation.TYPE_SCALE_3D
			or str(anim.track_get_path(i)).ends_with(":scale")
		)
		if bone == "AxHandle01":
			if is_pos:
				ax_pos = i
			elif is_rot:
				ax_rot = i
			elif is_scale:
				ax_scale = i
		elif bone == "Bone_Hand_L":
			if is_pos:
				hand_pos = i
			elif is_rot:
				hand_rot = i
	var changed := false
	if ax_scale >= 0:
		for ki in range(anim.track_get_key_count(ax_scale)):
			anim.track_set_key_value(ax_scale, ki, Vector3.ONE)
		changed = true
	if ax_pos >= 0 and hand_pos >= 0 and _copy_track_key_values(anim, hand_pos, ax_pos):
		changed = true
	if ax_rot >= 0 and hand_rot >= 0 and _copy_track_key_values(anim, hand_rot, ax_rot):
		changed = true
	return changed


## 将 src 轨关键帧值拷到 dst（按时间对齐；dst 关键数不足则插入）。
func _copy_track_key_values(anim: Animation, src_track: int, dst_track: int) -> bool:
	var src_n := anim.track_get_key_count(src_track)
	var dst_n := anim.track_get_key_count(dst_track)
	if src_n <= 0 or dst_n <= 0:
		return false
	if src_n == dst_n:
		for ki in range(src_n):
			anim.track_set_key_value(dst_track, ki, anim.track_get_key_value(src_track, ki))
		return true
	# 时间轴不一致：按 src 时间重写 dst
	while anim.track_get_key_count(dst_track) > 0:
		anim.track_remove_key(dst_track, 0)
	for ki in range(src_n):
		var t := anim.track_get_key_time(src_track, ki)
		var v: Variant = anim.track_get_key_value(src_track, ki)
		anim.track_insert_key(dst_track, t, v)
	return true


## C-2: 拼装 attachments 到 proto（_scene_cache 里的 Node3D）。
## - attachments[]：4 类辅助（Attachment / ParticleEmitter2 / Light / RibbonEmitter）
##   → BoneAttachment3D（绑骨）+ 子节点（MeshInstance3D 占位 / GPUParticles3D / OmniLight3D）
## - geoset_expansions[]：C-3 在 _split_meshes_by_group 处理（先拆再拼 attachment 节点）
##
## 副作用：给 _plog 写拼装统计。owner 设为 proto（不是临时 inst）才能保存到 .scn。
func _assemble_attachments(proto: Node, att_data: Dictionary) -> void:
	if proto == null or att_data.is_empty():
		return
	# 找 Skeleton3D
	var skeleton: Skeleton3D = null
	for c in proto.find_children("*", "Skeleton3D", true, false):
		if c is Skeleton3D:
			skeleton = c
			break
	if skeleton == null:
		_plog("WARN", "no Skeleton3D for attachments, skip")
		return
	var att_list: Array = att_data.get("attachments", [])
	if att_list.is_empty():
		return
	var placed := 0
	var skipped := 0
	for item in att_list:
		var name: String = str(item.get("name", ""))
		var type: String = str(item.get("type", ""))
		var bone: String = str(item.get("bone", ""))
		if bone.is_empty():
			skipped += 1
			continue
		# 找 bone index
		var bone_idx := skeleton.find_bone(bone)
		if bone_idx == -1:
			# 静默 skip：很多 attachment 的 bone 是 model.Nodes 里的 Helper（Bone_Root/Pelvis/Foot_L 等），
			# m2g 写 .gltf 时只用 model.Bones 的 mesh-bone，所以 skeleton 里找不到。
			# 这种 attachment 用 placeholder marker 替代即可（runtime 不影响功能）。
			# 统计仍在 assemble_attachments placed/skipped 末尾汇总。
			skipped += 1
			continue
		# BoneAttachment3D
		var ba := BoneAttachment3D.new()
		ba.name = name
		ba.bone_name = bone
		skeleton.add_child(ba)
		ba.owner = proto  # 关键：owner = proto（不是临时 inst）才能保存到 .scn
		# 子节点（按 type）
		match type:
			"attachment":
				# WC3 attachment point：仅占位（后续运行时挂 UI / 血条 / 寻路点）
				var marker := Node3D.new()
				marker.name = name + "_marker"
				ba.add_child(marker)
				marker.owner = proto
			"particle":
				var particles := GPUParticles3D.new()
				particles.name = name + "_particles"
				particles.amount = 16
				ba.add_child(particles)
				particles.owner = proto
			"light":
				var light := OmniLight3D.new()
				light.name = name + "_light"
				light.light_color = Color(1.0, 0.8, 0.3)
				light.light_energy = 1.5
				ba.add_child(light)
				light.owner = proto
			"ribbon":
				var ribbon := Node3D.new()
				ribbon.name = name + "_ribbon"
				ba.add_child(ribbon)
				ribbon.owner = proto
		placed += 1
	_plog("INFO", "assemble_attachments placed=%d skipped=%d skeleton=%s" % [placed, skipped, skeleton.name])


## 读 assets/asset-converted/.no-scn 标记；命中 → true（跳过 bake）。
## 文件不存在或读失败 → false（不抛错）。
## 性能：728 行的 Set lookup，O(1)。
var _no_scn_set: Dictionary = {}

func _load_no_scn() -> void:
	if not _no_scn_set.is_empty():
		return
	var path := RuntimeAssets.project_abs("res://assets/asset-converted/.no-scn")
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if not line.is_empty() and not line.begins_with("#"):
			_no_scn_set[line] = true
	f.close()


func _is_no_scn(logical_glb: String) -> bool:
	_load_no_scn()
	return _no_scn_set.has(logical_glb)


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
			elif name.to_lower().ends_with(".gltf") or name.to_lower().ends_with(".glb"):
				out.append(full)
		name = d.get_next()
	d.list_dir_end()
