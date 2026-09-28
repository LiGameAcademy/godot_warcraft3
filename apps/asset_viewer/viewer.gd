extends Control
## Application root owns UI wiring; shared content handles paths and scene loading.

@onready var search: LineEdit = %Search
@onready var baked_only: CheckButton = %BakedOnly
@onready var severity: OptionButton = %Severity
@onready var models: ItemList = %Models
@onready var model_tree: Tree = %ModelTree
@onready var browser_mode: OptionButton = %BrowserMode
@onready var expand_tree: Button = %ExpandTree
@onready var collapse_tree: Button = %CollapseTree
@onready var count_label: Label = %Count
@onready var status: Label = %Status
@onready var details: RichTextLabel = %Details
@onready var animations: OptionButton = %Animations
@onready var pause_button: Button = %Pause
@onready var team: OptionButton = %Team
@onready var viewport_container: SubViewportContainer = %ViewportContainer
@onready var viewport: SubViewport = %Viewport
@onready var models_root: Node3D = %ModelsRoot
@onready var camera: Camera3D = %Camera
@onready var ground: MeshInstance3D = %Ground
@onready var environment: WorldEnvironment = %Environment
@onready var report_dialog: FileDialog = %ReportDialog

var catalog: AssetAuditCatalog = AssetAuditCatalog.new()
var selected_record: Dictionary = {}
var current_model: Node3D
var player: AnimationPlayer
var report_path: String = ""
var _team_cache: MapModelCache = MapModelCache.new()
var _filtered: Array[Dictionary] = []
var _target: Vector3 = Vector3.ZERO
var _distance: float = 6.0
var _yaw: float = 0.65
var _pitch: float = 0.4
var _dragging: bool = false
var _tree_items: Dictionary = {}
var _folder_items: Dictionary = {}
var _expanded_folders: Dictionary = {}
var _building_tree: bool = false
var _syncing_selection: bool = false
var _inspected_nodes: Array[Node] = []


#region Lifecycle
func _ready() -> void:
	(%ResetCamera as Button).pressed.connect(reset_camera)
	(%ShowNodes as CheckButton).toggled.connect(func(_value: bool) -> void: _inspection_visibility())
	(%ShowAnimation as CheckButton).toggled.connect(func(_value: bool) -> void: _inspection_visibility())
	(%SceneNodes as Tree).item_selected.connect(_inspect_node)
	for label: String in ["自由视角", "前视 +Z", "后视 −Z", "右视 +X", "左视 −X", "顶视 +Y", "底视 −Y"]:
		(%Views as OptionButton).add_item(label)
	(%Views as OptionButton).item_selected.connect(func(index: int) -> void:
		if index == 0:
			reset_camera()
		else:
			set_camera_view([Vector3.BACK, Vector3.FORWARD, Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN][index - 1]))
	(%Axes as Control).connect("view_selected", set_camera_view)
	browser_mode.add_item("树状目录")
	browser_mode.add_item("列表")
	browser_mode.item_selected.connect(set_browser_mode)
	model_tree.item_selected.connect(_select_tree_item)
	model_tree.item_collapsed.connect(_remember_folder_state)
	expand_tree.pressed.connect(func() -> void: _set_tree_expanded(true))
	collapse_tree.pressed.connect(func() -> void: _set_tree_expanded(false))
	for label: String in ["所有等级", "P0", "P1", "P2", "P3", "none", "unknown"]:
		severity.add_item(label)
	team.add_item("原烘焙队色")
	for index: int in range(16):
		team.add_item("玩家 %d" % (index + 1))
	search.text_changed.connect(func(_text: String) -> void: _filter())
	baked_only.toggled.connect(func(_pressed: bool) -> void: _filter())
	severity.item_selected.connect(func(_index: int) -> void: _filter())
	models.item_selected.connect(_select_index)
	animations.item_selected.connect(_play_animation)
	pause_button.toggled.connect(set_paused)
	team.item_selected.connect(func(_index: int) -> void: _restart())
	(%Reload as Button).pressed.connect(func() -> void: load_catalog(report_path))
	(%OpenReport as Button).pressed.connect(func() -> void: report_dialog.popup_centered())
	(%Scan as Button).pressed.connect(_scan_baked)
	(%Restart as Button).pressed.connect(_restart)
	(%Fit as Button).pressed.connect(fit_model)
	(%GroundToggle as CheckButton).toggled.connect(func(enabled: bool) -> void: ground.visible = enabled)
	(%LightBackground as CheckButton).toggled.connect(func(enabled: bool) -> void: environment.environment.background_color = Color(0.55, 0.57, 0.6) if enabled else Color(0.055, 0.07, 0.09))
	report_dialog.file_selected.connect(load_catalog)
	viewport_container.gui_input.connect(_preview_input)
	var asset_root: String = RuntimeAssets.project_abs("res://assets/")
	report_path = str(ProjectSettings.get_setting("warcraft3/audit_report", asset_root.trim_suffix("/").get_base_dir().path_join(".cache/asset-audit/latest/report.json")))
	load_catalog(report_path)
	_update_camera()
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var preview_index: int = arguments.find("--preview-scene")
	if preview_index >= 0 and preview_index + 1 < arguments.size():
		preview_scene(arguments[preview_index + 1])
	print("AssetViewer: ready (%d models)" % catalog.records.size())
	if "--smoke-test" in OS.get_cmdline_user_args():
		_smoke_test.call_deferred()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not (event as InputEventMouseButton).pressed:
		_dragging = false
#endregion


#region Public interface
func preview_scene(file_path: String) -> bool:
	if not file_path.is_absolute_path() or file_path.get_extension().to_lower() != "scn":
		status.text = "预览需要 .scn 文件的绝对路径。"
		return false
	selected_record = {"logical_path": file_path.get_file(), "scn_path": file_path.get_file(), "preview_absolute_path": file_path, "severity": "unknown", "issues": []}
	_reload_model()
	fit_model()
	print("AssetViewer: external preview %s loaded=%s" % [file_path, current_model != null])
	return current_model != null


func load_catalog(file_path: String) -> void:
	report_path = file_path
	_clear_model()
	selected_record.clear()
	if catalog.load_report(file_path):
		status.text = "审计报告：" + file_path
	else:
		var reason: String = catalog.error
		catalog.scan_baked()
		status.text = reason + " 当前仅列出已烘焙资源，无审计结论。"
	details.text = "选择模型查看。所有视觉状态仍需原作游戏内验收。"
	_filter()


func select_model(logical_id: String) -> bool:
	for row: Dictionary in catalog.records:
		if str(row.get("id", "")) == logical_id.to_lower():
			selected_record = row
			_reload_model()
			fit_model()
			_sync_browser_selection()
			return current_model != null
	return false


func set_browser_mode(index: int) -> void:
	browser_mode.select(index)
	model_tree.visible = index == 0
	models.visible = index == 1
	expand_tree.visible = index == 0
	collapse_tree.visible = index == 0
	_sync_browser_selection()


func set_paused(paused: bool) -> void:
	pause_button.set_pressed_no_signal(paused)
	pause_button.text = "继续" if paused else "暂停"
	if current_model == null:
		return
	current_model.process_mode = Node.PROCESS_MODE_DISABLED if paused else Node.PROCESS_MODE_INHERIT
	# GPU simulation is renderer-driven; disabling scene processing alone is insufficient.
	for node: Node in _nodes(current_model):
		if node is GPUParticles3D:
			(node as GPUParticles3D).speed_scale = 0.0 if paused else float(node.get_meta("viewer_speed_scale", 1.0))
		elif node is CPUParticles3D:
			(node as CPUParticles3D).speed_scale = 0.0 if paused else float(node.get_meta("viewer_speed_scale", 1.0))


func fit_model() -> void:
	var bounds: AABB = AABB()
	var found: bool = false
	if current_model != null:
		# Large glow cards should not make the visible body tiny. Pure FX still fit
		# their cards on the second pass; hidden decay/alternate meshes are excluded.
		for include_glow: bool in [false, true]:
			for node: Node in _nodes(current_model):
				if not node is MeshInstance3D:
					continue
				var mesh_node: MeshInstance3D = node as MeshInstance3D
				if mesh_node.mesh == null or not mesh_node.is_visible_in_tree():
					continue
				if not include_glow and _is_glow_card(mesh_node):
					continue
				var box: AABB = mesh_node.global_transform * mesh_node.get_aabb()
				bounds = bounds.merge(box) if found else box
				found = true
			if found:
				break
	_target = bounds.get_center() if found else Vector3.ZERO
	_distance = clampf(bounds.size.length() * 0.55 / sin(deg_to_rad(camera.fov * 0.5)), 0.3, 3000.0) if found else 6.0
	ground.scale = Vector3.ONE * maxf(_distance / 10.0, 0.5)
	_update_camera()
#endregion


#region Internal operations
func _scan_baked() -> void:
	_clear_model()
	selected_record.clear()
	catalog.scan_baked()
	status.text = "已扫描烘焙场景；此模式没有源审计信息。"
	details.text = "选择模型查看。"
	_filter()


func _filter() -> void:
	models.clear()
	_filtered.clear()
	var query: String = search.text.strip_edges().to_lower()
	var grade: String = severity.get_item_text(severity.selected)
	for row: Dictionary in catalog.records:
		if baked_only.button_pressed and str(row.get("scn_path", "")).is_empty():
			continue
		if severity.selected > 0 and str(row.get("severity", "unknown")) != grade:
			continue
		var searchable: String = str(row.get("logical_path", "")) + str(row.get("categories", [])) + str(row.get("issues", []))
		if not query.is_empty() and not searchable.to_lower().contains(query):
			continue
		_filtered.append(row)
		var label: String = "[%s] %s" % [row.get("severity", "?"), row.get("logical_path", "")]
		var index: int = models.add_item(label)
		models.set_item_tooltip(index, label + ("\n可预览 .scn" if not str(row.get("scn_path", "")).is_empty() else "\n未烘焙；可查看审计信息"))
		if row.get("id") == selected_record.get("id", ""):
			models.select(index)
	count_label.text = "%d / %d 个模型" % [_filtered.size(), catalog.records.size()]
	_rebuild_tree()
	_sync_browser_selection()


func _rebuild_tree() -> void:
	_building_tree = true
	model_tree.clear()
	_tree_items.clear()
	_folder_items.clear()
	var root_item: TreeItem = model_tree.create_item()
	var searching: bool = not search.text.strip_edges().is_empty()
	for index: int in range(_filtered.size()):
		var row: Dictionary = _filtered[index]
		var logical: String = str(row.get("logical_path", "")).replace("\\", "/")
		var parts: PackedStringArray = logical.split("/")
		var parent: TreeItem = root_item
		var folder_path: String = ""
		for depth: int in range(parts.size() - 1):
			folder_path = folder_path.path_join(parts[depth])
			if not _folder_items.has(folder_path):
				var folder: TreeItem = model_tree.create_item(parent)
				folder.set_text(0, parts[depth])
				folder.set_tooltip_text(0, folder_path)
				folder.set_selectable(0, false)
				folder.set_metadata(0, folder_path)
				folder.collapsed = not searching and not _expanded_folders.has(folder_path)
				_folder_items[folder_path] = folder
			parent = _folder_items[folder_path] as TreeItem
		var leaf: TreeItem = model_tree.create_item(parent)
		leaf.set_text(0, "[%s] %s" % [row.get("severity", "?"), parts[parts.size() - 1]])
		leaf.set_tooltip_text(0, logical + ("\n可预览 .scn" if not str(row.get("scn_path", "")).is_empty() else "\n未烘焙；可查看审计信息"))
		leaf.set_metadata(0, index)
		_tree_items[str(row.get("id", ""))] = leaf
	_building_tree = false


func _remember_folder_state(item: TreeItem) -> void:
	if _building_tree or not search.text.strip_edges().is_empty():
		return
	var folder_path: Variant = item.get_metadata(0)
	if not folder_path is String:
		return
	if item.collapsed:
		_expanded_folders.erase(folder_path)
	else:
		_expanded_folders[folder_path] = true


func _set_tree_expanded(expanded: bool) -> void:
	for value: Variant in _folder_items.values():
		(value as TreeItem).collapsed = not expanded


func _select_tree_item() -> void:
	if _building_tree or _syncing_selection:
		return
	var item: TreeItem = model_tree.get_selected()
	if item != null and item.get_metadata(0) is int:
		_select_index(int(item.get_metadata(0)))


func _sync_browser_selection() -> void:
	_syncing_selection = true
	var selected_id: String = str(selected_record.get("id", ""))
	for index: int in range(_filtered.size()):
		if str(_filtered[index].get("id", "")) == selected_id:
			models.select(index)
			if models.visible:
				models.ensure_current_is_visible()
			break
	var leaf: TreeItem = _tree_items.get(selected_id) as TreeItem
	if leaf != null:
		leaf.select(0)
		if model_tree.visible:
			var parent: TreeItem = leaf.get_parent()
			while parent != null:
				parent.collapsed = false
				parent = parent.get_parent()
			model_tree.scroll_to_item(leaf)
	_syncing_selection = false


func _select_index(index: int) -> void:
	if _syncing_selection:
		return
	selected_record = _filtered[index]
	_reload_model()
	fit_model()
	_sync_browser_selection()


func _clear_model() -> void:
	(%SceneNodes as Tree).clear()
	_inspected_nodes.clear()
	(%NodeInfo as RichTextLabel).text = "选择节点查看只读属性。"
	(%AnimationInfo as RichTextLabel).text = "无动画。"
	player = null
	if is_instance_valid(current_model):
		models_root.remove_child(current_model)
		current_model.free()
	current_model = null
	animations.clear()
	pause_button.set_pressed_no_signal(false)
	pause_button.text = "暂停"


func _reload_model() -> void:
	_clear_model()
	_show_details()
	var relative: String = str(selected_record.get("scn_path", ""))
	if relative.is_empty():
		status.text = "该模型尚无 .scn，显示审计信息。查看器不会自动转换或烘焙。"
		return
	var scene_path: String = str(selected_record.get("preview_absolute_path", RuntimeAssets.converted_path(relative)))
	var packed: PackedScene = RuntimeAssets.load_packed_scene(scene_path)
	if packed == null:
		status.text = "场景无法加载或引用不兼容：" + relative
		return
	var instance: Node = packed.instantiate()
	if not instance is Node3D:
		instance.free()
		status.text = "场景根节点不是 Node3D：" + relative
		return
	current_model = instance as Node3D
	models_root.add_child(current_model)
	for node: Node in _nodes(current_model):
		if node is GPUParticles3D:
			var particle: GPUParticles3D = node as GPUParticles3D
			particle.use_fixed_seed = true
			particle.seed = 42
			particle.set_meta("viewer_speed_scale", particle.speed_scale)
		elif node is CPUParticles3D:
			node.set_meta("viewer_speed_scale", (node as CPUParticles3D).speed_scale)
	if team.selected > 0:
		_team_cache.apply_team_color(current_model, team.selected - 1)
	player = AnimPlayback.find_animation_player(current_model)
	if player != null:
		for animation: StringName in player.get_animation_list():
			animations.add_item(str(animation))
		for index: int in range(animations.item_count):
			if animations.get_item_text(index).to_lower().begins_with("stand"):
				animations.select(index)
				break
		if animations.item_count > 0:
			_play_animation(animations.selected)
	status.text = "已加载：" + RuntimeAssets.project_abs(scene_path) + " · 当前烘焙结果，保真未验收"
	_rebuild_scene_nodes()


func _restart() -> void:
	var animation: String = animations.get_item_text(animations.selected) if animations.item_count > 0 else ""
	_reload_model()
	for index: int in range(animations.item_count):
		if animations.get_item_text(index) == animation:
			animations.select(index)
			_play_animation(index)


func _play_animation(index: int) -> void:
	if player == null or index < 0:
		return
	set_paused(false)
	player.play(animations.get_item_text(index))
	player.advance(0.0)
	_animation_info()


func _show_details() -> void:
	var lines: PackedStringArray = PackedStringArray()
	lines.append(str(selected_record.get("logical_path", "")))
	lines.append("等级：%s  |  视觉：未验证  |  当前烘焙结果（保真／增强未分离）" % selected_record.get("severity", "unknown"))
	var provenance: Variant = selected_record.get("provenance")
	var source_name: String = str(provenance.get("sourceMpq", "未知")) if provenance is Dictionary else "无来源清单"
	lines.append("来源：%s  |  源解析：%s  |  内容签名：%s" % [source_name, selected_record.get("parse_status", "未审计"), str(selected_record.get("source_sha256", "")).left(12)])
	var features: Dictionary = selected_record.get("features", {})
	var feature_text: PackedStringArray = PackedStringArray()
	for key: Variant in features:
		if int(features[key]) > 0:
			feature_text.append("%s=%s" % [key, features[key]])
	lines.append("特征：" + ", ".join(feature_text))
	for issue: Dictionary in selected_record.get("issues", []):
		lines.append("%s · %s：%s" % [issue.get("severity", "?"), issue.get("stage", ""), issue.get("message", "")])
	if selected_record.get("issues", []).is_empty():
		lines.append("未列出静态问题不等于保真验收通过。")
	details.text = "\n".join(lines)


func _is_glow_card(mesh_node: MeshInstance3D) -> bool:
	if str(mesh_node.name).begins_with("TeamGlow"):
		return true
	for surface: int in range(mesh_node.mesh.get_surface_count()):
		var material: Material = mesh_node.get_active_material(surface)
		if material == null:
			return false
		var glow: bool = material.resource_name.contains("_rep2")
		if material is ShaderMaterial and (material as ShaderMaterial).shader != null:
			glow = glow or (material as ShaderMaterial).shader.resource_path.contains("team_glow")
		if not glow:
			return false
	return true


func _nodes(root: Node) -> Array[Node]:
	var result: Array[Node] = [root]
	var index: int = 0
	while index < result.size():
		result.append_array(result[index].get_children())
		index += 1
	return result


func _preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
		if button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_distance = clampf(_distance * (0.88 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.14), 0.1, 5000.0)
			_update_camera()
	elif event is InputEventMouseMotion and _dragging:
		(%Views as OptionButton).select(0)
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		_yaw -= motion.relative.x * 0.008
		_pitch = clampf(_pitch + motion.relative.y * 0.008, -1.4, 1.4)
		_update_camera()


func _update_camera() -> void:
	camera.position = _target + Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _distance
	camera.look_at(_target, Vector3.BACK if absf(cos(_pitch)) < 0.001 else Vector3.UP)
	camera.size = _distance
	(%Axes as Control).set("camera_basis", camera.global_basis)
	(%Axes as Control).queue_redraw()


func reset_camera() -> void:
	_yaw = 0.65
	_pitch = 0.4
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	(%Views as OptionButton).select(0)
	fit_model()


func set_camera_view(direction: Vector3) -> void:
	_yaw = atan2(direction.x, direction.z)
	_pitch = asin(direction.y)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var directions: Array[Vector3] = [Vector3.BACK, Vector3.FORWARD, Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN]
	(%Views as OptionButton).select(directions.find(direction) + 1)
	_update_camera()


func _inspection_visibility() -> void:
	var nodes_on: bool = (%ShowNodes as CheckButton).button_pressed
	var animation_on: bool = (%ShowAnimation as CheckButton).button_pressed
	(%Inspection as Control).visible = nodes_on or animation_on
	(%SceneNodes as Control).visible = nodes_on
	(%NodeInfo as Control).visible = nodes_on
	(%AnimationInfo as Control).visible = animation_on
	_animation_info()


func _rebuild_scene_nodes() -> void:
	var tree: Tree = %SceneNodes
	tree.clear()
	_inspected_nodes = _nodes(current_model)
	var items: Dictionary = {}
	for index: int in range(_inspected_nodes.size()):
		var node: Node = _inspected_nodes[index]
		var item: TreeItem = tree.create_item(items.get(node.get_parent()))
		item.set_text(0, "%s · %s" % [node.name, node.get_class()])
		item.set_tooltip_text(0, "%s · %s" % [current_model.get_path_to(node), node.get_class()])
		item.set_metadata(0, index)
		items[node] = item


func _inspect_node() -> void:
	var selected: TreeItem = (%SceneNodes as Tree).get_selected()
	if selected == null:
		return
	var node: Node = _inspected_nodes[int(selected.get_metadata(0))]
	if not is_instance_valid(node):
		return
	var lines: PackedStringArray = [str(node.name), "类型：" + node.get_class(), "路径：" + str(current_model.get_path_to(node))]
	if node is Node3D:
		lines.append("可见：%s\n位置：%s" % [node.is_visible_in_tree(), node.position])
	if node is MeshInstance3D and node.mesh != null:
		lines.append("表面数：%d" % node.mesh.get_surface_count())
		for surface: int in range(node.mesh.get_surface_count()):
			var material: Material = node.get_active_material(surface)
			lines.append("材质 %d：%s" % [surface, material.resource_name if material != null else "无"])
	if node is BoneAttachment3D:
		lines.append("骨骼：%s" % node.bone_name)
	if node.get_script() != null:
		lines.append("脚本：" + str(node.get_script().resource_path))
	for key: StringName in node.get_meta_list():
		lines.append("%s = %s" % [key, node.get_meta(key)])
	(%NodeInfo as RichTextLabel).text = "\n".join(lines)


func _animation_info() -> void:
	if player == null or animations.selected < 0:
		(%AnimationInfo as RichTextLabel).text = "无动画。"
		return
	var name: String = animations.get_item_text(animations.selected)
	var animation: Animation = player.get_animation(name)
	var lines: PackedStringArray = [name, "时长：%.3f 秒" % animation.length, "循环：%s" % ["无", "循环", "往返"][animation.loop_mode], "轨道数：%d" % animation.get_track_count()]
	for key: StringName in animation.get_meta_list():
		lines.append("%s = %s" % [key, animation.get_meta(key)])
	for index: int in range(animation.get_track_count()):
		var types: Array[String] = ["属性", "位移", "旋转", "缩放", "混合形状", "方法", "曲线", "音频", "动画"]
		var track_type: int = animation.track_get_type(index)
		lines.append("%s · %s · %d 关键帧" % [animation.track_get_path(index), types[track_type] if track_type < types.size() else str(track_type), animation.track_get_key_count(index)])
	(%AnimationInfo as RichTextLabel).text = "\n".join(lines)


func _smoke_test() -> void:
	await get_tree().process_frame
	print("APP startup PASS: asset_viewer UI and shared catalog initialized")
	get_tree().quit(0)
#endregion
