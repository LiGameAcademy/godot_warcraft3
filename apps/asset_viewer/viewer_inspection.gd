extends RefCounted
## Read-only inspection presentation, with explicit UI and model inputs.
var tree: Tree
var node_info: RichTextLabel
var animation_details: RichTextLabel
var current_model: Node3D
var _inspected_nodes: Array[Node] = []

func _init(p_tree: Tree, p_node_info: RichTextLabel, p_animation_details: RichTextLabel) -> void:
	tree = p_tree
	node_info = p_node_info
	animation_details = p_animation_details

func clear() -> void:
	tree.clear()
	_inspected_nodes.clear()
	current_model = null

static func collect_nodes(model: Node) -> Array[Node]:
	var nodes: Array[Node] = [model]
	var index: int = 0
	while index < nodes.size():
		nodes.append_array(nodes[index].get_children())
		index += 1
	return nodes

func rebuild(model: Node3D) -> void:
	current_model = model
	tree.clear()
	_inspected_nodes = collect_nodes(current_model)
	var items: Dictionary = {}
	for index: int in range(_inspected_nodes.size()):
		var node: Node = _inspected_nodes[index]
		var item: TreeItem = tree.create_item(items.get(node.get_parent()))
		item.set_text(0, "%s · %s" % [node.name, node.get_class()])
		item.set_tooltip_text(0, "%s · %s" % [current_model.get_path_to(node), node.get_class()])
		item.set_metadata(0, index)
		items[node] = item


func inspect_node() -> void:
	var selected: TreeItem = tree.get_selected()
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
	node_info.text = "\n".join(lines)


func animation_info(player: AnimationPlayer, animations: OptionButton) -> void:
	if player == null or animations.selected < 0:
		animation_details.text = "无动画。"
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
	animation_details.text = "\n".join(lines)

static func is_glow_card(mesh_node: MeshInstance3D) -> bool:
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


