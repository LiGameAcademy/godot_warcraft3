class_name UnitPortraitView
extends Control

## HUD 3D 肖像框：队色 ColorRect 底 + SubViewport。
## 机位：优先源 Camera 与动画轨，其次旧烘焙相机，最后 sidecar / AABB。
## 动画：普通单位 Portrait* 随机；主城 htow/hkee/hcas 按科技档位固定播。
## 加载：预载 + 轻量 instance + 小池复用；取消选中隐藏 Viewport 清残帧。

const PORTRAIT_SIZE: Vector2i = Vector2i(96, 96)
const _EMPTY_BG: Color = Color(0.12, 0.12, 0.14, 1.0)
## 中立（owner≥12）肖像底：黑灰，不用队色条。
const _NEUTRAL_BG: Color = Color(0.1, 0.1, 0.11, 1.0)
const _NEUTRAL_OWNER_MIN: int = 12
const _POOL_MAX: int = 10
const _META_TEAM: StringName = &"portrait_team_color"

@onready var _bg: ColorRect = $TeamColorBg
@onready var _vp_host: SubViewportContainer = $PortraitViewportHost
@onready var _world: Node3D = $PortraitViewportHost/PortraitViewport/PortraitWorld
@onready var _vp: SubViewport = $PortraitViewportHost/PortraitViewport

var _camera: PortraitCamera = PortraitCamera.new()
var _animation: PortraitAnimation = PortraitAnimation.new()
var _model_root: Node3D
var _cache: MapModelCache = null
var _catalog: Wc3IdCatalog = null
var _type_id: String = ""
var _model_path: String = ""
## 异步换肖像：世代号防竞态；pending 期间只显示队色底。
var _load_gen: int = 0
var _pending_path: String = ""
var _pending_owner: int = 0
## path → Node3D（挂在本节点下离屏复用，避免反复 instantiate）
var _pool: Dictionary = {}
var _pool_host: Node = null
var _warming: bool = false
var _settled_gen: int = -1


func _ready() -> void:
	_camera.configure(_world)
	custom_minimum_size = Vector2(PORTRAIT_SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_pool_host()
	if _bg != null:
		_bg.color = _EMPTY_BG
	if _vp != null:
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _vp_host != null:
		_vp_host.visible = false
	set_process(false)


func configure(cache: MapModelCache, catalog: Wc3IdCatalog) -> void:
	if _cache != cache or _catalog != catalog:
		clear_portrait()
		_warming = false
		for model: Node3D in _pool.values():
			if is_instance_valid(model):
				model.queue_free()
		_pool.clear()
	_cache = cache
	_animation.configure(cache)
	_catalog = catalog


## Prepare actual portrait surfaces while the match is loading. An empty viewport
## cannot precompile the model's pipelines. Hidden UI still renders offscreen.
## The caller holds gameplay paused; no selection signals or commands are issued.
func prepare_types(type_ids: PackedStringArray, owner_id: int, progress: Callable = Callable()) -> void:
	if _warming or DisplayServer.get_name() == "headless" or _cache == null or _catalog == null or _is_closing():
		return
	_warming = true
	var prepared: int = 0
	var total: int = mini(type_ids.size(), _POOL_MAX)
	if progress.is_valid():
		progress.call(0, total)
	for type_id: String in type_ids:
		if prepared >= _POOL_MAX or _is_closing():
			break
		show_type(type_id, owner_id)
		var generation: int = _load_gen
		var deadline: int = Time.get_ticks_msec() + 15000
		while generation == _load_gen and _settled_gen != generation and Time.get_ticks_msec() < deadline:
			# Also works when the caller temporarily disables the game subtree.
			if not _pending_path.is_empty():
				_process(0.0)
			await get_tree().process_frame
			if _is_closing():
				return
		if generation != _load_gen:
			_warming = false
			_set_viewport_active(_model_root != null)
			return
		if _settled_gen != generation:
			push_warning("Portrait preparation timed out: " + type_id)
		else:
			# Surface preparation happens after script callbacks, on the render side.
			await RenderingServer.frame_post_draw
			if _is_closing():
				return
		if generation != _load_gen:
			_warming = false
			_set_viewport_active(_model_root != null)
			return
		prepared += 1
		if progress.is_valid():
			progress.call(prepared, total)
	clear_portrait()
	_warming = false


func clear_portrait() -> void:
	_load_gen += 1
	_pending_path = ""
	_type_id = ""
	_animation._disconnect_anim()
	_retire_model()
	if _camera.fallback_camera != null and is_instance_valid(_camera.fallback_camera):
		_camera.fallback_camera.current = false
	_set_viewport_active(false)
	if _bg != null:
		_bg.color = _EMPTY_BG
	set_process(false)


func show_type(type_id: String, owner_id: int = 0) -> void:
	var tid: String = type_id.strip_edges()
	if tid.is_empty():
		clear_portrait()
		return
	if (
		tid == _type_id
		and _model_root != null
		and is_instance_valid(_model_root)
		and _pending_path.is_empty()
	):
		_apply_team_bg(tid, owner_id)
		_apply_team_color_if_needed(_model_root, tid, owner_id)
		return
	_load_gen += 1
	var gen: int = _load_gen
	_type_id = tid
	_pending_owner = owner_id
	_pending_path = ""
	_animation._disconnect_anim()
	_retire_model()
	_apply_team_bg(tid, owner_id)
	_set_viewport_active(false)
	if _cache == null or _catalog == null or _world == null:
		return
	var path: String = _catalog.portrait_glb_path(tid)
	if path.is_empty():
		path = _catalog.converted_glb_path(tid)
	if path.is_empty():
		_settled_gen = gen
		return
	_pending_path = path
	if _pool.has(path) or _cache.has_cached(path):
		call_deferred("_try_attach_pending", gen)
		return
	_cache.request_preload(path)
	set_process(true)


func _process(_delta: float) -> void:
	if _pending_path.is_empty():
		_camera.update_source_animation(_animation.player)
		return
	if _cache == null:
		set_process(false)
		return
	var started: int = MatchHotpathMetrics.begin()
	_cache.poll_preloads(2)
	MatchHotpathMetrics.finish(&"portrait_preload_poll", started)
	if _cache.has_cached(_pending_path):
		var gen: int = _load_gen
		set_process(false)
		_try_attach_pending(gen)
		return
	if not _cache.is_preload_pending(_pending_path):
		var gen2: int = _load_gen
		set_process(false)
		_try_attach_pending(gen2)


func _try_attach_pending(gen: int) -> void:
	var started: int = MatchHotpathMetrics.begin()
	_measured_try_attach_pending(gen)
	MatchHotpathMetrics.finish(&"portrait_attach", started)


func _measured_try_attach_pending(gen: int) -> void:
	if gen != _load_gen or _is_closing():
		return
	if _pending_path.is_empty() or _cache == null or _world == null:
		return
	var path: String = _pending_path
	var tid: String = _type_id
	var owner_id: int = _pending_owner
	_pending_path = ""
	var inst: Node3D = _acquire_model(path)
	if inst == null:
		_settled_gen = gen
		_apply_team_bg(tid, owner_id)
		return
	if gen != _load_gen:
		_store_in_pool(path, inst)
		return
	_model_path = path
	_model_root = inst
	if inst.get_parent() != _world:
		if inst.get_parent() != null:
			inst.get_parent().remove_child(inst)
		_world.add_child(inst)
	inst.visible = true
	# 延迟队色、相机和动画设置；deferred 不保证跨帧，耗时单独计量。
	call_deferred("_finish_portrait_setup", gen, tid, owner_id, path)


func _finish_portrait_setup(gen: int, tid: String, owner_id: int, path: String) -> void:
	var started: int = MatchHotpathMetrics.begin()
	_measured_finish_portrait_setup(gen, tid, owner_id, path)
	MatchHotpathMetrics.finish(&"portrait_setup", started)


func _measured_finish_portrait_setup(gen: int, tid: String, owner_id: int, path: String) -> void:
	if gen != _load_gen or _is_closing():
		return
	if _model_root == null or not is_instance_valid(_model_root):
		return
	_camera._normalize_portrait_materials(_model_root)
	_camera._normalize_portrait_model_scale(_model_root)
	_model_root.position = Vector3.ZERO
	_model_root.rotation = Vector3.ZERO
	_apply_team_color_if_needed(_model_root, tid, owner_id)
	_apply_team_bg(tid, owner_id)
	_animation._start_portrait_anims(_model_root, tid)
	_snap_portrait_geoset()
	_ensure_portrait_meshes_visible()
	_camera._fit_camera(_model_root, path)
	_camera.update_source_animation(_animation.player)
	_set_viewport_active(true)
	_settled_gen = gen


## 延迟头像任务不能在宿主已请求卸载后继续创建渲染资源。
## queue_free父场景不会立即把子节点标为queued，因此必须检查祖先。
func _is_closing() -> bool:
	if not is_inside_tree():
		return true
	var node: Node = self
	while node != null:
		if node.is_queued_for_deletion():
			return true
		node = node.get_parent()
	return false


func _exit_tree() -> void:
	_warming = false
	_load_gen += 1
	_pending_path = ""
	set_process(false)
	_animation._disconnect_anim()


## 光晕PrimitiveMesh使用表面覆盖且基础材质为空时，卸载可触发空RID查询。
## 将同一个有效材质放入实例独有网格，保持外观并避免修改缓存/其他头像。
func _snap_portrait_geoset() -> void:
	if _cache == null or _model_root == null:
		return
	var anim: String = ""
	if _animation.player != null and is_instance_valid(_animation.player):
		anim = str(_animation.player.current_animation)
	if anim.is_empty() and _animation.player != null:
		# 尚未起播时：优先 Portrait*，再 Stand
		for logical: String in ["Portrait", "Portrait - 1", "Stand"]:
			var resolved: String = AnimPlayback.resolve(_model_root, logical, _animation.player)
			if not resolved.is_empty():
				anim = resolved
				break
	if not anim.is_empty():
		# 肖像靠 Geoset_* scale 轨显隐；勿走 rest scale=0 兜底（会把身体藏掉）
		_cache.snap_geoset_visibility_for(_model_root, anim, 0.0, false)


## 肖像身体网格：Geoset_* / Mesh*（Militia 肖像未 split 时全叫 Mesh）。
func _ensure_portrait_meshes_visible() -> void:
	if _model_root == null or not is_instance_valid(_model_root) or CompiledModelPresentation.is_compiled(_model_root):
		return
	var body_vis: bool = false
	for c: Node in _model_root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c as MeshInstance3D
		if mi == null or mi.mesh == null or not _camera._is_portrait_body_mesh(mi):
			continue
		if mi.visible and mi.scale.length_squared() > 1e-8:
			body_vis = true
			break
	if body_vis:
		return
	if _cache != null and _cache.has_method("reveal_hidden_geosets_public"):
		_cache.call("reveal_hidden_geosets_public", _model_root)
	for c2: Node in _model_root.find_children("*", "MeshInstance3D", true, false):
		var mi2: MeshInstance3D = c2 as MeshInstance3D
		if mi2 == null or not _camera._is_portrait_body_mesh(mi2):
			continue
		mi2.visible = true
		if mi2.scale.length_squared() < 1e-8:
			mi2.scale = Vector3.ONE


func _apply_team_color_if_needed(root: Node3D, type_id: String, owner_id: int) -> void:
	if _cache == null or root == null:
		return
	# 肖像 GLB 无 _rep1 队色层；染色会误伤 Team Glow 且与底板糊在一起
	if not CompiledModelPresentation.is_compiled(root) and (
		_model_path.findn("_Portrait") >= 0
		or _model_path.findn("_portrait") >= 0
	):
		return
	var color_i: int = MapUnitLayer.resolve_team_color_index(type_id, owner_id)
	var prev: int = int(root.get_meta(_META_TEAM, -999))
	if prev == color_i:
		return
	CompiledModelPresentation.apply_team(root, color_i, _cache)
	root.set_meta(_META_TEAM, color_i)


func _ensure_pool_host() -> void:
	if _pool_host != null and is_instance_valid(_pool_host):
		return
	# 池必须挂在 SubViewport 世界内：肖像 .scn 含 current=true 的 Camera3D，
	# 若挂到 HUD Control（主场景树）会抢走 RTS 主相机 → 左键取消选中后「场景消失」。
	_pool_host = Node3D.new()
	_pool_host.name = "PortraitPool"
	_pool_host.visible = false
	if _world != null:
		_world.add_child(_pool_host)
	else:
		add_child(_pool_host)


func _acquire_model(path: String) -> Node3D:
	if _pool.has(path):
		var pooled: Variant = _pool[path]
		_pool.erase(path)
		if pooled is Node3D and is_instance_valid(pooled):
			return pooled as Node3D
	if _cache == null:
		return null
	if path.findn("_Portrait") >= 0 or path.findn("_portrait") >= 0:
		return CompiledModelPresentation.instantiate(path, _cache, false, true)
	return CompiledModelPresentation.instantiate(path, _cache)


func _retire_model() -> void:
	if _model_root == null or not is_instance_valid(_model_root):
		_model_root = null
		_model_path = ""
		return
	var path: String = _model_path
	var node: Node3D = _model_root
	_model_root = null
	_model_path = ""
	_animation._disconnect_anim_only()
	_camera._set_model_cameras_current(node, false)
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	_store_in_pool(path, node)


func _store_in_pool(path: String, node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	_ensure_pool_host()
	_camera._set_model_cameras_current(node, false)
	if path.is_empty() or _pool.size() >= _POOL_MAX or _pool.has(path):
		node.queue_free()
		return
	if node.get_parent() != _pool_host:
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		_pool_host.add_child(node)
	node.visible = false
	_pool[path] = node


## 肖像 bake 相机会带 current=true；离开 Viewport 前必须关掉。
func _set_viewport_active(active: bool) -> void:
	set_process(active or not _pending_path.is_empty())
	if _vp_host != null:
		_vp_host.visible = active and not _warming
	if _vp == null:
		return
	_vp.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	)


func _is_neutral_owner(owner_id: int) -> bool:
	return owner_id >= _NEUTRAL_OWNER_MIN or owner_id < 0


func _apply_team_bg(type_id: String, owner_id: int) -> void:
	if _bg == null:
		return
	if _is_neutral_owner(owner_id):
		_bg.color = _NEUTRAL_BG
		return
	var color_i: int = MapUnitLayer.resolve_team_color_index(type_id, owner_id)
	var base: Color
	if color_i >= 0 and color_i < MapPlaceholders.PLAYER_COLORS.size():
		base = MapPlaceholders.PLAYER_COLORS[color_i]
	else:
		base = MapPlaceholders.color_for(type_id, owner_id, true)
	# 比模型队色更深，避免与肖像上的 TeamColor 糊成一块
	_bg.color = _darken_portrait_bg(base)


## 肖像底板：保留色相，明显压暗（相对模型队色）。
func _darken_portrait_bg(c: Color) -> Color:
	return Color(c.r * 0.38, c.g * 0.38, c.b * 0.38, 1.0)


func _clear_model() -> void:
	_retire_model()
	_animation._disconnect_anim()
	if _camera.fallback_camera != null and is_instance_valid(_camera.fallback_camera):
		_camera.fallback_camera.current = false
