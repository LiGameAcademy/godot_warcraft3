extends RefCounted

## Godot renames joints that collide with scene-node names. Use its exact node
## mapping rather than guessing suffixes, and leave the source IR unchanged.
static func from_state(state: GLTFState) -> Dictionary[String, String]:
	var names: Dictionary[String, String] = {}
	for node: GLTFNode in state.get_nodes():
		if node.skeleton < 0 or node.original_name.is_empty():
			continue
		var path: NodePath = node.get_scene_node_path(state)
		if path.get_subname_count() == 1:
			names[node.original_name] = str(path.get_subname(0))
	return names

static func remap(ir: Dictionary, names: Dictionary[String, String]) -> Dictionary:
	var result: Dictionary = ir.duplicate()
	result["skeleton"] = ir.get("skeleton", {}).duplicate(true)
	result["attachments"] = ir.get("attachments", {}).duplicate(true)
	for entries: Array in [result.skeleton.get("rest_payload", {}).get("bones", []), result.skeleton.get("billboards", [])]:
		for entry: Dictionary in entries:
			var source_name: String = str(entry.name)
			entry["name"] = names.get(source_name, source_name)
	for entry: Dictionary in result.attachments.get("payload", {}).get("attachments", []):
		if entry.get("bone") is String:
			entry["bone"] = names.get(entry.bone, entry.bone)
	return result
