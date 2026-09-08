extends SceneTree
## 批量：asset-converted 下 *.gltf/.glb → 同目录 *.scn（含 PE2 / cameras / collision / animkeys）。
## .scn 与模型同属 gitignore 的 asset-converted；免主线程 GLTF 解析。
##
## 用法:
##   godot --headless --path . -s res://scripts/tool/export_model_scenes.gd
##   godot --headless --path . -s res://scripts/tool/export_model_scenes.gd -- --include Units/Human/ --force
##
## 通常由 tools/asset-convert（npm run convert）在转完模型后自动调用。
## 若环境变量 PIPELINE_LOG 已设，进度/警告/错误会追加到该 Markdown 文档。

# 五桶归位：Skeleton3D 只留骨头；Geoset 蒙皮网格进 SkinMeshes
const Wc3ScnRebucketScript := preload("res://scripts/tool/wc3_scn_rebucket.gd")
const Wc3ScnAnimkeysScript := preload("res://scripts/tool/wc3_scn_animkeys.gd")
const Wc3ScnPe2Script := preload("res://scripts/tool/wc3_scn_pe2.gd")
const Wc3ScnRibbonScript := preload("res://scripts/tool/wc3_scn_ribbon.gd")
const Wc3ModelSceneScript := preload("res://scripts/presentation/wc3_model/wc3_model_scene.gd")
const Wc3AnimPlayerScript := preload("res://scripts/presentation/wc3_model/wc3_anim_player.gd")


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
			var pe2_stat := _sidecar_mtime(logical_glb, ".pe2.json")
			var cam_stat := _sidecar_mtime(logical_glb, ".cameras.json")
			if sstat >= gstat and sstat >= pe2_stat and sstat >= cam_stat:
				skipped += 1
				if considered % 50 == 0:
					_progress_line(considered, exported, skipped, failed)
				continue
			# 过期 .scn 必须删掉，否则 instance 会吃旧包、重复拼装
			DirAccess.remove_absolute(disk_scn)
			cache.evict(glb_res)
		# 烤基座时跳过 visuals（避免套娃 / 基座已删时 ExtResource 失败）
		var root: Node3D = cache.instance_glb_preview(
			glb_res,
			false,
			MapModelCache.glb_path_uses_unit_soft_blend(logical_glb)
		)
		if root == null:
			_plog("WARN", "export_model_scenes: load failed %s" % logical_glb)
			print("  ⚠ load failed %s" % logical_glb)
			failed += 1
			continue
		# C-2: 拼装 attachments 到 _scene_cache 里的 proto（不是临时 inst）
		# 这样 cache.bake_model_scene 烤出 .scn 时已含 attachment 节点
		var att_data := _read_attachments(logical_glb)
		var proto := cache.get_proto(glb_res)
		if proto != null:
			_apply_bone_rest_from_sidecar(proto, logical_glb)
			if not att_data.is_empty():
				_assemble_attachments(proto, att_data)
			# Skeleton3D 只留骨头；glTF Geoset 蒙皮网格 → SkinMeshes；Attach_* → Attachments
			var rb: Dictionary = Wc3ScnRebucketScript.apply(proto)
			_plog(
				"INFO",
				"rebucket skins=%s ba=%s skeleton=%s (%s)"
				% [rb.get("skins", 0), rb.get("attachments", 0), rb.get("skeleton", ""), logical_glb]
			)
			# 网格换父后 :visible 轨路径失效，必须按 SkinMeshes/Geoset_N 重注
			if cache.has_method("reinject_geoset_vis_tracks"):
				cache.reinject_geoset_vis_tracks(glb_res)
			if not att_data.is_empty():
				# Stand_Work*：腰带斧 hide-scale 会把同骨施工锤一起缩没 → 对齐左手并取消 hide
				var work_fix := _fix_work_tool_anims(proto)
				if work_fix > 0:
					_plog("INFO", "fix_work_tool_anims: %d sequences (%s)" % [work_fix, logical_glb])
			# MDX Cameras → 场景内 Camera3D（肖像机位；无 sidecar 则跳过）
			var cam_n := _inject_mdx_cameras(proto, logical_glb)
			if cam_n > 0:
				_plog("INFO", "inject_mdx_cameras: %d (%s)" % [cam_n, logical_glb])
				var cam_tr := _inject_mdx_camera_tracks(proto, logical_glb)
				if cam_tr > 0:
					_plog("INFO", "inject_mdx_camera_tracks: %d (%s)" % [cam_tr, logical_glb])
			var col_n := _inject_mdx_collision(proto, logical_glb)
			if col_n > 0:
				_plog("INFO", "inject_mdx_collision: %d (%s)" % [col_n, logical_glb])
			# Pe2Root 先就位，再挪 Omni，最后写 :visible——避免 TownHall/Omni01 轨悬空
			var pe2: Dictionary = Wc3ScnPe2Script.apply(proto, glb_res)
			if bool(pe2.get("ok", false)) and int(pe2.get("emitters", 0)) > 0:
				var pe2_msg := (
					"inject_pe2 emitters=%s tracks=%s (%s)"
					% [pe2.get("emitters", 0), pe2.get("tracks", 0), logical_glb]
				)
				print("  %s" % pe2_msg)
				_plog("INFO", pe2_msg)
			var ribbon: Dictionary = Wc3ScnRibbonScript.apply(proto, glb_res)
			if bool(ribbon.get("ok", false)) and int(ribbon.get("ribbons", 0)) > 0:
				var rib_msg := (
					"inject_ribbon ribbons=%s tracks=%s (%s)"
					% [ribbon.get("ribbons", 0), ribbon.get("tracks", 0), logical_glb]
				)
				print("  %s" % rib_msg)
				_plog("INFO", rib_msg)
			var light_n := _reparent_lights_into_pe2(proto)
			if light_n > 0:
				_plog("INFO", "reparent_lights_into_pe2: %d (%s)" % [light_n, logical_glb])
			if not att_data.is_empty():
				var vis_n := _inject_attachment_visibility(proto, att_data, logical_glb)
				if vis_n > 0:
					_plog("INFO", "inject_attachment_visibility: %d tracks (%s)" % [vis_n, logical_glb])
			var ak: Dictionary = Wc3ScnAnimkeysScript.apply(proto, _read_animkeys(logical_glb))
			if bool(ak.get("ok", false)) and int(ak.get("sequences", 0)) > 0:
				_plog(
					"INFO",
					"inject_animkeys sequences=%s event_keys=%s (%s)"
					% [ak.get("sequences", 0), ak.get("event_keys", 0), logical_glb]
				)
			_apply_bone_rest_from_sidecar(proto, logical_glb)
			_ensure_wc3_anim_player(proto)
			proto.set_script(Wc3ModelSceneScript)
			var snap_n := Wc3MdxOmni.snap_all(proto as Node3D)
			if snap_n > 0:
				_plog("INFO", "snap_mdx_omni: %d (%s)" % [snap_n, logical_glb])
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
	return _read_json_sidecar(logical_glb, ".attachments.json")


func _read_cameras(logical_glb: String) -> Dictionary:
	return _read_json_sidecar(logical_glb, ".cameras.json")


func _sidecar_mtime(logical_glb: String, suffix: String) -> int:
	var side := logical_glb
	if side.to_lower().ends_with(".gltf"):
		side = side.substr(0, side.length() - 5) + suffix
	elif side.to_lower().ends_with(".glb"):
		side = side.substr(0, side.length() - 4) + suffix
	else:
		return 0
	var disk := RuntimeAssets.project_abs("res://assets/asset-converted/" + side)
	if not FileAccess.file_exists(disk):
		return 0
	return int(FileAccess.get_modified_time(disk))


## Godot GLTFDocument 解析 skinned mesh 时丢弃 joint node TRS → Skeleton3D 全 identity rest。
func _apply_bone_rest_from_sidecar(proto: Node, logical_glb: String) -> void:
	MapModelCache.apply_bone_rest_sidecar(proto, logical_glb)


func _read_json_sidecar(logical_glb: String, suffix: String) -> Dictionary:
	var side := logical_glb
	if side.to_lower().ends_with(".gltf"):
		side = side.substr(0, side.length() - 5) + suffix
	elif side.to_lower().ends_with(".glb"):
		side = side.substr(0, side.length() - 4) + suffix
	else:
		return {}
	var disk := RuntimeAssets.project_abs("res://assets/asset-converted/" + side)
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


## 把 *.cameras.json 写成场景根上的 Camera3D（current=false）。
## 必须挂在 proto（scale=1），不能进 0.01 模型根，否则 sidecar 坐标再缩 100×。
## 休息姿态用 Portrait 位移（bind 是全身远景）；HUD 启用这台相机，AP 播 Portrait*。
## fov = sidecar fov_y_deg = MDX FieldOfView（弧度）× 180/π，写入 Godot 垂直 FOV。
func _inject_mdx_cameras(proto: Node, logical_glb: String) -> int:
	if proto == null:
		return 0
	var data := _read_cameras(logical_glb)
	var cams_v: Variant = data.get("cameras", [])
	if typeof(cams_v) != TYPE_ARRAY:
		return 0
	var cams: Array = cams_v
	if cams.is_empty():
		return 0
	for c in proto.find_children("*", "Camera3D", true, false):
		var cam0 := c as Camera3D
		if cam0 != null and bool(cam0.get_meta("wc3_mdx_camera", false)):
			cam0.queue_free()
	var old_host := proto.get_node_or_null("MdxCameras")
	if old_host != null:
		old_host.queue_free()
	var n := 0
	for item in cams:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var pos_v: Variant = d.get("position", null)
		var tgt_v: Variant = d.get("target", null)
		if typeof(pos_v) != TYPE_ARRAY or typeof(tgt_v) != TYPE_ARRAY:
			continue
		var pos_a: Array = pos_v
		var tgt_a: Array = tgt_v
		if pos_a.size() < 3 or tgt_a.size() < 3:
			continue
		var cam := Camera3D.new()
		var cname := str(d.get("name", "Camera%02d" % (n + 1)))
		cam.name = cname if not cname.is_empty() else ("Camera%02d" % (n + 1))
		cam.current = false
		cam.set_meta("wc3_mdx_camera", true)
		cam.fov = clampf(float(d.get("fov_y_deg", 30.0)), 5.0, 120.0)
		var near_v := float(d.get("near", 0.01))
		var far_v := float(d.get("far", 100.0))
		if near_v > 0.0:
			cam.near = near_v
		if far_v > near_v:
			cam.far = far_v
		var pos := Vector3(float(pos_a[0]), float(pos_a[1]), float(pos_a[2]))
		var tgt := Vector3(float(tgt_a[0]), float(tgt_a[1]), float(tgt_a[2]))
		proto.add_child(cam)
		cam.owner = proto
		cam.position = pos
		if pos.distance_squared_to(tgt) > 1e-8:
			cam.look_at_from_position(pos, tgt, Vector3.UP)
		n += 1
	_apply_portrait_camera_rest(proto, data, logical_glb)
	return n


## 游戏肖像框播 Portrait*：把 Camera Translation/Rotation 写进主 AP。
## 编辑器 Camera01 预览用 Portrait 机位（bind 是全身远景，和原作框差很多）。
func _inject_mdx_camera_tracks(proto: Node, logical_glb: String) -> int:
	var ap := _find_animation_player(proto)
	if ap == null:
		return 0
	var anim_root: Node = ap.get_node_or_null(ap.root_node)
	if anim_root == null:
		anim_root = ap.get_parent()
	if anim_root == null:
		return 0
	var data := _read_cameras(logical_glb)
	var cams_v: Variant = data.get("cameras", [])
	if typeof(cams_v) != TYPE_ARRAY:
		return 0
	var sequences: Array = _read_animkeys(logical_glb).get("sequences", [])
	if sequences.is_empty():
		return 0
	var n := 0
	for item in cams_v as Array:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var cname := str(d.get("name", "")).strip_edges()
		var cam: Camera3D = proto.find_child(cname, true, false) as Camera3D
		if cam == null:
			continue
		var rel := anim_root.get_path_to(cam)
		if str(rel).is_empty() or str(rel) == ".":
			continue
		for seq_v in sequences:
			if typeof(seq_v) != TYPE_DICTIONARY:
				continue
			var seq: Dictionary = seq_v
			var resolved := _resolve_ap_anim(ap, str(seq.get("name", "")).strip_edges())
			if resolved.is_empty():
				continue
			var anim := ap.get_animation(resolved)
			if anim == null:
				continue
			var interval: Variant = seq.get("interval", [])
			if typeof(interval) != TYPE_ARRAY or (interval as Array).size() < 2:
				continue
			var start_ms := float((interval as Array)[0])
			var end_ms := float((interval as Array)[1])
			if end_ms <= start_ms:
				continue
			n += _write_camera_clip_tracks(anim, rel, d, start_ms, end_ms, anim.length)
	return n


func _write_camera_clip_tracks(
	anim: Animation, cam_rel: NodePath, d: Dictionary, start_ms: float, end_ms: float, anim_len: float
) -> int:
	var frames: Dictionary = {start_ms: true}
	for track_name in ["translation", "rotation", "target_translation"]:
		var keys := _cam_track_keys(d.get(track_name, null))
		for k in keys:
			var fr := float(k.get("frame", 0.0))
			if fr >= start_ms and fr <= end_ms:
				frames[fr] = true
	var ordered: Array = frames.keys()
	ordered.sort()
	_remove_tracks_of_type(anim, cam_rel, Animation.TYPE_POSITION_3D)
	_remove_tracks_of_type(anim, cam_rel, Animation.TYPE_ROTATION_3D)
	var pi := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(pi, cam_rel)
	var ri := anim.add_track(Animation.TYPE_ROTATION_3D)
	anim.track_set_path(ri, cam_rel)
	for fr_v in ordered:
		var fr := float(fr_v)
		var pose := _camera_pose_at(d, fr, start_ms, end_ms)
		var t := (fr - start_ms) / 1000.0
		if anim_len > 0.0:
			t = clampf(t, 0.0, anim_len)
		anim.track_insert_key(pi, t, pose["pos"])
		anim.track_insert_key(ri, t, pose["rot"])
	return 2


func _remove_tracks_of_type(anim: Animation, track_path: NodePath, ttype: int) -> void:
	var want := str(track_path)
	for i in range(anim.get_track_count() - 1, -1, -1):
		if anim.track_get_type(i) != ttype:
			continue
		if str(anim.track_get_path(i)) == want:
			anim.remove_track(i)


func _cam_track_keys(raw: Variant) -> Array:
	if typeof(raw) != TYPE_DICTIONARY:
		return []
	var keys_v: Variant = (raw as Dictionary).get("keys", [])
	if typeof(keys_v) != TYPE_ARRAY:
		return []
	var out: Array = []
	for k in keys_v as Array:
		if typeof(k) == TYPE_DICTIONARY:
			out.append(k)
	out.sort_custom(func(a, b): return float((a as Dictionary).get("frame", 0.0)) < float((b as Dictionary).get("frame", 0.0)))
	return out


func _camera_pose_at(d: Dictionary, frame_ms: float, start_ms: float, end_ms: float) -> Dictionary:
	var pos := _vec3_from_json(d.get("position", []))
	var tgt := _vec3_from_json(d.get("target", []))
	pos += _sample_cam_vec3(d.get("translation", null), frame_ms, start_ms, end_ms, Vector3.ZERO)
	tgt += _sample_cam_vec3(d.get("target_translation", null), frame_ms, start_ms, end_ms, Vector3.ZERO)
	var roll := _sample_cam_float(d.get("rotation", null), frame_ms, start_ms, end_ms, 0.0)
	var xf := Transform3D(Basis.IDENTITY, pos)
	if pos.distance_squared_to(tgt) > 1e-8:
		xf = xf.looking_at(tgt, Vector3.UP)
	if absf(roll) > 1e-6:
		xf.basis = xf.basis.rotated(xf.basis.z, roll)
	return {"pos": xf.origin, "rot": xf.basis.get_rotation_quaternion()}


func _sample_cam_vec3(raw: Variant, frame_ms: float, start_ms: float, end_ms: float, fallback: Vector3) -> Vector3:
	var keys := _cam_track_keys(raw)
	if keys.is_empty():
		return fallback
	var best: Variant = null
	for k in keys:
		var fr := float((k as Dictionary).get("frame", 0.0))
		if fr < start_ms:
			best = k
			continue
		if fr > end_ms:
			break
		if fr <= frame_ms:
			best = k
		else:
			break
	if best == null:
		return fallback
	return _vec3_from_json((best as Dictionary).get("vector", []))


func _sample_cam_float(raw: Variant, frame_ms: float, start_ms: float, end_ms: float, fallback: float) -> float:
	var keys := _cam_track_keys(raw)
	if keys.is_empty():
		return fallback
	var best: Variant = null
	for k in keys:
		var fr := float((k as Dictionary).get("frame", 0.0))
		if fr < start_ms:
			best = k
			continue
		if fr > end_ms:
			break
		if fr <= frame_ms:
			best = k
		else:
			break
	if best == null:
		return fallback
	var vec_v: Variant = (best as Dictionary).get("vector", [])
	if typeof(vec_v) == TYPE_ARRAY and (vec_v as Array).size() > 0:
		return float((vec_v as Array)[0])
	return fallback


func _apply_portrait_camera_rest(proto: Node, data: Dictionary, logical_glb: String = "") -> void:
	var cams_v: Variant = data.get("cameras", [])
	if typeof(cams_v) != TYPE_ARRAY:
		return
	var iv := _portrait_interval(_read_animkeys(logical_glb).get("sequences", []))
	for item in cams_v as Array:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var cname := str(d.get("name", "")).strip_edges()
		var cam: Camera3D = proto.find_child(cname, true, false) as Camera3D
		if cam == null:
			continue
		var start_ms := iv.x
		var end_ms := iv.y
		if end_ms <= start_ms:
			var trans_keys := _cam_track_keys(d.get("translation", null))
			for k in trans_keys:
				var fr := float((k as Dictionary).get("frame", 0.0))
				if fr > 1000.0:
					start_ms = fr
					end_ms = fr + 1.0
					break
		if end_ms <= start_ms:
			continue
		var pose := _camera_pose_at(d, start_ms, start_ms, end_ms)
		cam.position = pose["pos"] as Vector3
		cam.quaternion = pose["rot"] as Quaternion


func _portrait_interval(sequences: Array) -> Vector2:
	var fallback := Vector2(-1.0, -1.0)
	for seq_v in sequences:
		if typeof(seq_v) != TYPE_DICTIONARY:
			continue
		var seq: Dictionary = seq_v
		var nm := str(seq.get("mdx_name", seq.get("name", ""))).strip_edges().to_lower()
		if not nm.begins_with("portrait"):
			continue
		var interval: Variant = seq.get("interval", [])
		if typeof(interval) != TYPE_ARRAY or (interval as Array).size() < 2:
			continue
		var start_ms := float((interval as Array)[0])
		var end_ms := float((interval as Array)[1])
		if end_ms <= start_ms:
			continue
		if not nm.contains("upgrade"):
			return Vector2(start_ms, end_ms)
		if fallback.x < 0.0:
			fallback = Vector2(start_ms, end_ms)
	return fallback


func _read_collision(logical_glb: String) -> Dictionary:
	return _read_json_sidecar(logical_glb, ".collision.json")


func _read_animkeys(logical_glb: String) -> Dictionary:
	return _read_json_sidecar(logical_glb, ".animkeys.json")


func _vec3_from_json(v: Variant) -> Vector3:
	if typeof(v) != TYPE_ARRAY:
		return Vector3.ZERO
	var a: Array = v
	if a.size() < 3:
		return Vector3.ZERO
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## attachments.pivot 已 ×0.01（米）。IBM=I 时蒙皮是 bone_global * v_model，
## Tip 局部必须等于 Pivot 厘米，才能跟网格杖尖一起转；勿用 inv(bind)*P。
func _bone_local_from_model_pivot(_skeleton: Skeleton3D, _bone_idx: int, pivot_m: Vector3) -> Vector3:
	return pivot_m / 0.01


## *.collision.json → Area3D + CollisionShape3D（layer/mask=0，不参与玩法碰撞）。
## 坐标与 cameras.json 相同：已 Y-up × MODEL_SCALE，挂在 proto 根下。
func _inject_mdx_collision(proto: Node, logical_glb: String) -> int:
	if proto == null:
		return 0
	var data := _read_collision(logical_glb)
	var shapes_v: Variant = data.get("shapes", [])
	if typeof(shapes_v) != TYPE_ARRAY:
		return 0
	var shapes: Array = shapes_v
	for c in proto.find_children("*", "CollisionObject3D", true, false):
		var obj := c as CollisionObject3D
		if obj != null and bool(obj.get_meta("wc3_mdx_collision", false)):
			obj.queue_free()
	var old_host := proto.get_node_or_null("MdxCollision")
	if old_host != null:
		old_host.queue_free()
	if shapes.is_empty():
		return 0
	var host := Node3D.new()
	host.name = "MdxCollision"
	proto.add_child(host)
	host.owner = proto
	var n := 0
	for item in shapes:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var area := Area3D.new()
		var cname := str(d.get("name", "Collision%02d" % (n + 1))).strip_edges()
		area.name = cname if not cname.is_empty() else ("Collision%02d" % (n + 1))
		area.monitoring = false
		area.monitorable = false
		area.collision_layer = 0
		area.collision_mask = 0
		area.set_meta("wc3_mdx_collision", true)
		var shape_id := int(d.get("shape", -1))
		var cs := CollisionShape3D.new()
		cs.name = "Shape"
		if shape_id == 2:
			var sphere := SphereShape3D.new()
			sphere.radius = maxf(0.001, float(d.get("radius", 0.0)))
			cs.shape = sphere
			var center_v: Variant = d.get("center", null)
			if typeof(center_v) == TYPE_ARRAY:
				area.position = _vec3_from_json(center_v)
			else:
				var verts_v: Variant = d.get("vertices", [])
				if typeof(verts_v) == TYPE_ARRAY and (verts_v as Array).size() > 0:
					area.position = _vec3_from_json((verts_v as Array)[0])
		elif shape_id == 0:
			var mn := _vec3_from_json(d.get("min", []))
			var mx := _vec3_from_json(d.get("max", []))
			var box := BoxShape3D.new()
			box.size = (mx - mn).abs()
			cs.shape = box
			area.position = (mn + mx) * 0.5
		else:
			continue
		host.add_child(area)
		area.owner = proto
		area.add_child(cs)
		cs.owner = proto
		n += 1
	if n == 0:
		host.queue_free()
	return n


func _apply_attachment_pivot(node: Node3D, item: Dictionary) -> void:
	var pivot := _vec3_from_json(item.get("pivot", []))
	if pivot != Vector3.ZERO:
		node.position = pivot


func _make_mdx_omni(item: Dictionary) -> OmniLight3D:
	var light := OmniLight3D.new()
	var node_name := str(item.get("name", "Omni")).strip_edges()
	light.name = node_name if not node_name.is_empty() else "Omni"
	light.set_meta("wc3_mdx_attachment", true)
	light.shadow_enabled = false
	light.visible = bool(item.get("visibility_default", false))
	var col := _vec3_from_json(item.get("color", [1, 1, 1]))
	light.light_color = Color(col.x, col.y, col.z)
	var intensity := maxf(0.0, float(item.get("intensity", 1.0)))
	light.light_energy = maxf(0.5, intensity * 0.25)
	var att_end := maxf(0.25, float(item.get("attenuation_end", 2.0)))
	light.omni_range = att_end
	return light


## WC3 网格 unshaded，OmniLight 照不亮模型。
## Flash = 朝相机 soft-orb 光晕（替代硬边 Sphere），跟 Light :visible 轨一起开关。
func _attach_omni_flash(light: OmniLight3D, item: Dictionary, owner: Node) -> void:
	if light == null:
		return
	var att_end := maxf(0.25, float(item.get("attenuation_end", 2.0)))
	var intensity := maxf(0.0, float(item.get("intensity", 1.0)))
	var col := light.light_color
	var flash := Wc3MdxOmni.make_soft_flash(col, intensity, att_end)
	light.add_child(flash)
	if owner != null:
		flash.owner = owner


func _attachment_key(name: String) -> String:
	return name.strip_edges().replace(" ", "").replace("-", "").replace("_", "").to_lower()


func _is_origin_or_overhead(name: String) -> bool:
	var k := _attachment_key(name)
	return k.begins_with("origin") or k.begins_with("overhead")


func _is_sprite_socket(name: String) -> bool:
	return _attachment_key(name).begins_with("sprite")


func _ensure_named_child(parent: Node, child_name: String) -> Node3D:
	var existing := parent.get_node_or_null(child_name)
	if existing is Node3D:
		return existing as Node3D
	var n := Node3D.new()
	n.name = child_name
	parent.add_child(n)
	n.owner = parent if parent.owner == null else parent.owner
	if n.owner == null:
		n.owner = parent
	return n


## 非 MDX 的 Omni（极少）才收进 Pe2Root。MDX Light 挂 proto（scale=1），勿再缩 100×。
func _reparent_lights_into_pe2(proto: Node) -> int:
	if proto == null:
		return 0
	var lights: Array[OmniLight3D] = []
	for n in proto.find_children("*", "OmniLight3D", true, false):
		if n is OmniLight3D and not bool(n.get_meta("wc3_mdx_attachment", false)):
			lights.append(n as OmniLight3D)
	if lights.is_empty():
		return 0
	var host: Node = proto.find_child(Wc3Pe2Particles.PE2_ROOT_NAME, true, false)
	if host == null:
		var model_root: Node3D = proto as Node3D
		if model_root != null:
			model_root = Wc3Pe2Particles.resolve_model_root(model_root)
		if model_root == null:
			return 0
		host = Node3D.new()
		host.name = Wc3Pe2Particles.PE2_ROOT_NAME
		model_root.add_child(host)
		host.owner = proto
	var anim_root := _anim_root_of(proto)
	var moved := 0
	for light in lights:
		if light.get_parent() == host:
			continue
		var old_rel := NodePath()
		if anim_root != null:
			old_rel = anim_root.get_path_to(light)
		var old := light.get_parent()
		if old != null:
			old.remove_child(light)
		light.owner = null
		host.add_child(light)
		light.owner = proto
		if anim_root != null and not str(old_rel).is_empty() and str(old_rel) != ".":
			_rewrite_anim_node_path(proto, old_rel, anim_root.get_path_to(light))
		moved += 1
	return moved


func _anim_root_of(proto: Node) -> Node:
	var ap := _find_animation_player(proto)
	if ap == null:
		return null
	var anim_root: Node = ap.get_node_or_null(ap.root_node)
	if anim_root == null:
		anim_root = ap.get_parent()
	return anim_root


## 节点换父后，把 Animation 里旧 NodePath 改成新路径（含 :visible 等属性）。
func _rewrite_anim_node_path(proto: Node, old_rel: NodePath, new_rel: NodePath) -> void:
	var ap := _find_animation_player(proto)
	if ap == null or str(old_rel).is_empty() or str(new_rel).is_empty():
		return
	if str(old_rel) == str(new_rel):
		return
	var old_s := str(old_rel)
	var new_s := str(new_rel)
	for anim_name in ap.get_animation_list():
		var anim := ap.get_animation(anim_name)
		if anim == null:
			continue
		for i in range(anim.get_track_count()):
			var pstr := str(anim.track_get_path(i))
			if pstr == old_s:
				anim.track_set_path(i, new_rel)
			elif pstr.begins_with(old_s + ":"):
				anim.track_set_path(i, NodePath(new_s + pstr.substr(old_s.length())))


## Attachment Visibility Keys（全局毫秒）→ 各 Sequence 的 `:visible` 轨。
func _inject_attachment_visibility(proto: Node, att_data: Dictionary, logical_glb: String) -> int:
	if proto == null or att_data.is_empty():
		return 0
	var att_list: Array = att_data.get("attachments", [])
	if att_list.is_empty():
		return 0
	var ap := _find_animation_player(proto)
	if ap == null:
		return 0
	var anim_root: Node = ap.get_node_or_null(ap.root_node)
	if anim_root == null:
		anim_root = ap.get_parent()
	if anim_root == null:
		return 0
	var sequences: Array = _read_animkeys(logical_glb).get("sequences", [])
	if sequences.is_empty():
		return 0
	var nodes_by_name: Dictionary = {}
	for c in proto.find_children("*", "Node3D", true, false):
		if not (c is Node3D) or not bool(c.get_meta("wc3_mdx_attachment", false)):
			continue
		var nm := str(c.name)
		nodes_by_name[nm] = c
		if nm.begins_with("Attach_"):
			nodes_by_name[nm.substr("Attach_".length())] = c
	if nodes_by_name.is_empty():
		return 0
	var injected := 0
	for item in att_list:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var node_name := str(d.get("name", "")).strip_edges()
		if node_name.is_empty() or not nodes_by_name.has(node_name):
			continue
		var target: Node3D = nodes_by_name[node_name]
		var default_on := bool(d.get("visibility_default", true))
		var keys := _attachment_vis_keys(d.get("visibility", null))
		# 无 KATV：不要写 :visible=false（旧 sidecar 把 Flags 0x4 误当成隐藏，攻击会藏掉杖尖）
		if keys.is_empty():
			continue
		var rel := anim_root.get_path_to(target)
		if str(rel).is_empty() or str(rel) == ".":
			continue
		var track_path := NodePath("%s:visible" % str(rel))
		for seq_v in sequences:
			if typeof(seq_v) != TYPE_DICTIONARY:
				continue
			var seq: Dictionary = seq_v
			var anim_name := str(seq.get("name", "")).strip_edges()
			if anim_name.is_empty():
				continue
			var resolved := _resolve_ap_anim(ap, anim_name)
			if resolved.is_empty():
				continue
			var anim := ap.get_animation(resolved)
			if anim == null:
				continue
			var interval: Variant = seq.get("interval", [])
			if typeof(interval) != TYPE_ARRAY or (interval as Array).size() < 2:
				continue
			var start_f := float((interval as Array)[0])
			var end_f := float((interval as Array)[1])
			if end_f <= start_f:
				continue
			var sampled := _sample_vis_in_sequence(keys, start_f, end_f, default_on)
			if sampled.is_empty():
				continue
			_remove_track_with_path(anim, track_path)
			var ti := anim.add_track(Animation.TYPE_VALUE)
			anim.track_set_path(ti, track_path)
			anim.value_track_set_update_mode(ti, Animation.UPDATE_DISCRETE)
			anim.track_set_interpolation_type(ti, Animation.INTERPOLATION_NEAREST)
			for kv in sampled:
				anim.track_insert_key(ti, float(kv.t), bool(kv.v))
			injected += 1
	return injected


func _resolve_ap_anim(ap: AnimationPlayer, anim_name: String) -> String:
	if ap == null or anim_name.is_empty():
		return ""
	if ap.has_animation(anim_name):
		return anim_name
	var want := _anim_leaf_name(anim_name).to_lower()
	var want_c := AnimPlayback.compact_seq_name(anim_name)
	for n in ap.get_animation_list():
		var full := str(n)
		var leaf := _anim_leaf_name(full)
		if leaf.to_lower() == want:
			return full
		if AnimPlayback.compact_seq_name(full) == want_c:
			return full
	return ""


func _remove_track_with_path(anim: Animation, track_path: NodePath) -> void:
	var want := str(track_path)
	for i in range(anim.get_track_count() - 1, -1, -1):
		if str(anim.track_get_path(i)) == want:
			anim.remove_track(i)


func _attachment_vis_keys(vis_v: Variant) -> Array:
	var out: Array = []
	if typeof(vis_v) != TYPE_DICTIONARY:
		return out
	var vis: Dictionary = vis_v
	if vis.has("static"):
		var sv: Variant = vis.get("static")
		var val := 1.0
		if typeof(sv) == TYPE_ARRAY and (sv as Array).size() > 0:
			val = float((sv as Array)[0])
		elif typeof(sv) == TYPE_FLOAT or typeof(sv) == TYPE_INT:
			val = float(sv)
		out.append({"frame": -1e12, "value": val >= 0.5})
		return out
	var keys_v: Variant = vis.get("keys", [])
	if typeof(keys_v) != TYPE_ARRAY:
		return out
	for k in keys_v as Array:
		if typeof(k) != TYPE_DICTIONARY:
			continue
		var kd: Dictionary = k
		var vec_v: Variant = kd.get("vector", [])
		var val := 1.0
		if typeof(vec_v) == TYPE_ARRAY and (vec_v as Array).size() > 0:
			val = float((vec_v as Array)[0])
		out.append({"frame": float(kd.get("frame", 0.0)), "value": val >= 0.5})
	out.sort_custom(func(a, b): return float(a.frame) < float(b.frame))
	return out


func _sample_vis_in_sequence(keys: Array, start_f: float, end_f: float, default_on: bool) -> Array:
	var start_v := default_on
	for k in keys:
		if float(k.frame) <= start_f:
			start_v = bool(k.value)
		else:
			break
	var sampled: Array = [{"t": 0.0, "v": start_v}]
	var last := start_v
	for k in keys:
		var fr := float(k.frame)
		if fr <= start_f or fr > end_f:
			continue
		var v := bool(k.value)
		if v == last:
			continue
		var t := (fr - start_f) / 1000.0
		sampled.append({"t": t, "v": v})
		last = v
	return sampled


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
	for c in proto.find_children("*", "Skeleton3D", true, false):
		var sk := c as Skeleton3D
		if sk != null and sk.find_bone("AxHandle01") >= 0:
			return true
	return false


func _is_stand_work_anim(anim_name: String) -> bool:
	var leaf := _anim_leaf_name(anim_name).replace("_", "").replace(" ", "").to_lower()
	return leaf == "standwork" or leaf.begins_with("standwork")


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


## bake 前给 AnimationPlayer 挂 Wc3AnimPlayer（播放/meta 职责）。
func _ensure_wc3_anim_player(proto: Node) -> void:
	var ap := _find_animation_player(proto)
	if ap == null:
		return
	if ap.get_script() == Wc3AnimPlayerScript:
		return
	ap.set_script(Wc3AnimPlayerScript)


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


## C-2: 拼装 attachments 到 proto。
## particle 不建空壳（Pe2Root 才是真发射器）。
## sidecar pivot 已 × MODEL_SCALE：Origin / OverHead / SpriteRefs / MDX Light 挂场景根（scale=1）。
## 骨骼挂点：BoneAttachment 跟骨原点（p-R*p）；Tip = inv(骨全局)×Pivot厘米。
## Light → OmniLight3D + 加性 Flash（网格 unshaded，纯 Omni 看不见）。
func _assemble_attachments(proto: Node, att_data: Dictionary) -> void:
	if proto == null or att_data.is_empty():
		return
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
	var model_root: Node3D = proto as Node3D
	if model_root != null:
		model_root = Wc3Pe2Particles.resolve_model_root(model_root)
	if model_root == null:
		model_root = proto as Node3D
	var sprite_host: Node3D = null
	var placed := 0
	var skipped := 0
	for item in att_list:
		if typeof(item) != TYPE_DICTIONARY:
			skipped += 1
			continue
		var d: Dictionary = item
		var node_name := str(d.get("name", "")).strip_edges()
		var type: String = str(d.get("type", ""))
		var bone: String = str(d.get("bone", "")).strip_edges()
		if node_name.is_empty():
			skipped += 1
			continue
		if type == "particle" or type == "ribbon":
			skipped += 1
			continue
		if type == "light":
			var light := _make_mdx_omni(d)
			# sidecar pivot 已 × MODEL_SCALE：挂 proto（scale=1），与 Camera / Origin 相同。
			proto.add_child(light)
			light.owner = proto
			_apply_attachment_pivot(light, d)
			_attach_omni_flash(light, d, proto)
			if proto is Node3D:
				Wc3MdxOmni.snap_if_outlier(proto as Node3D, light)
			placed += 1
			continue
		var bone_idx := skeleton.find_bone(bone) if not bone.is_empty() else -1
		if bone_idx >= 0:
			var ba := BoneAttachment3D.new()
			ba.name = node_name
			ba.bone_name = bone
			ba.set_meta("wc3_mdx_attachment", true)
			skeleton.add_child(ba)
			ba.owner = proto
			# BA 被骨 pose 覆盖；Pivot 在模型空间厘米，Tip 必须是 inv(骨全局)*P
			var pivot_m := _vec3_from_json(d.get("pivot", []))
			var local := _bone_local_from_model_pivot(skeleton, bone_idx, pivot_m)
			if local != Vector3.ZERO:
				ba.set_meta("wc3_pivot_delta", local)
				var tip := Marker3D.new()
				tip.name = "Tip"
				tip.position = local
				ba.add_child(tip)
				tip.owner = proto
			placed += 1
			continue
		var socket := Marker3D.new()
		socket.name = node_name
		socket.set_meta("wc3_mdx_attachment", true)
		if _is_origin_or_overhead(node_name):
			proto.add_child(socket)
		else:
			if sprite_host == null:
				sprite_host = _ensure_named_child(proto, "SpriteRefs")
				sprite_host.owner = proto
			sprite_host.add_child(socket)
		socket.owner = proto
		_apply_attachment_pivot(socket, d)
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
