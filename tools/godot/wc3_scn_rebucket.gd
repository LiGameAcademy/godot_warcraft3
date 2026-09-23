extends RefCounted
## bake:scn 五桶归位：Skeleton3D 只留骨头。
##
## 挂在 Armature 的同一父节点下（通常是带 0.01 scale 的模型根）：
##   Armature/Skeleton3D  ← 只骨头
##   SkinMeshes           ← glTF 蒙皮 Geoset_*（不按 VertexGroup 拆）
##   Attachments          ← Attach_* 骨骼挂点（BoneAttachment3D）
##
## Camera3D / Origin / OverHead / SpriteRefs / MdxCollision 坐标已 × MODEL_SCALE，挂在 proto 根（不进此桶）。
## Pe2Root 由 wc3_scn_pe2 注入到 0.01 模型根（不进此桶；不建空壳）。

const BUCKET_SKIN := "SkinMeshes"
const BUCKET_BA := "Attachments"


static func apply(root: Node) -> Dictionary:
	var result := {
		"ok": false,
		"skins": 0,
		"attachments": 0,
		"skeleton": "",
	}
	if root == null:
		return result
	var skeleton := _find_skeleton(root)
	var bucket_parent: Node = root
	if skeleton != null:
		result["skeleton"] = str(root.get_path_to(skeleton))
		var armature := skeleton.get_parent()
		if armature != null and armature.get_parent() != null:
			bucket_parent = armature.get_parent()
	var skin_bucket := _ensure_bucket(bucket_parent, BUCKET_SKIN)
	var ba_bucket := _ensure_bucket(bucket_parent, BUCKET_BA)
	_retire_legacy_bucket(bucket_parent, "BoneAttachments", ba_bucket)
	result["skins"] = _move_skinned_meshes(root, skin_bucket, skeleton)
	result["attachments"] = _move_bone_attachments(root, ba_bucket, skeleton)
	_set_owner_recursive(root, root)
	result["ok"] = true
	return result


static func _find_skeleton(root: Node) -> Skeleton3D:
	for n in root.find_children("*", "Skeleton3D", true, false):
		if n is Skeleton3D:
			return n as Skeleton3D
	return null


static func _ensure_bucket(parent: Node, bucket_name: String) -> Node3D:
	var existing := parent.get_node_or_null(bucket_name)
	if existing is Node3D:
		return existing as Node3D
	if bucket_name == BUCKET_BA:
		var legacy := parent.get_node_or_null("BoneAttachments")
		if legacy is Node3D:
			legacy.name = BUCKET_BA
			return legacy as Node3D
	var bucket := Node3D.new()
	bucket.name = bucket_name
	parent.add_child(bucket)
	return bucket


static func _retire_legacy_bucket(parent: Node, legacy_name: String, keep: Node) -> void:
	var legacy := parent.get_node_or_null(legacy_name)
	if legacy == null or legacy == keep:
		return
	while legacy.get_child_count() > 0:
		_reparent_keep_local(legacy.get_child(0), keep)
	legacy.free()


static func _move_skinned_meshes(root: Node, skin_bucket: Node, skeleton: Skeleton3D) -> int:
	var moved := 0
	var meshes: Array[Node] = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		meshes.append(n)
	for n in meshes:
		if n.get_parent() == skin_bucket or _is_under(n, skin_bucket):
			continue
		if _has_ancestor_type(n, "BoneAttachment3D"):
			continue
		if _has_ancestor_type(n, "Light3D"):
			continue
		_reparent_keep_local(n, skin_bucket)
		if n is MeshInstance3D and skeleton != null:
			(n as MeshInstance3D).skeleton = n.get_path_to(skeleton)
		moved += 1
	return moved


static func _move_bone_attachments(root: Node, ba_bucket: Node, skeleton: Skeleton3D) -> int:
	var moved := 0
	var attachments: Array[BoneAttachment3D] = []
	for n in root.find_children("*", "BoneAttachment3D", true, false):
		if n is BoneAttachment3D:
			attachments.append(n as BoneAttachment3D)
	for ba in attachments:
		if ba.get_parent() != ba_bucket:
			_reparent_keep_local(ba, ba_bucket)
			moved += 1
		_rename_ba(ba)
		if skeleton != null:
			_bind_external_skeleton(ba, skeleton)
	return moved


static func _rename_ba(ba: BoneAttachment3D) -> void:
	var nm := str(ba.name)
	if bool(ba.get_meta("wc3_mdx_attachment", false)):
		if not nm.begins_with("Attach_"):
			ba.name = "Attach_" + nm
		return
	if nm.begins_with("BA_"):
		return
	if nm.begins_with("Geoset_") and nm.contains("_Group_"):
		ba.name = "BA_" + nm


static func _bind_external_skeleton(ba: BoneAttachment3D, skeleton: Skeleton3D) -> void:
	ba.use_external_skeleton = true
	ba.external_skeleton = ba.get_path_to(skeleton)


static func _reparent_keep_local(node: Node, new_parent: Node) -> void:
	var old := node.get_parent()
	if old == new_parent:
		return
	_clear_owner_recursive(node)
	if old != null:
		old.remove_child(node)
	new_parent.add_child(node)


static func _clear_owner_recursive(node: Node) -> void:
	node.owner = null
	for c in node.get_children():
		_clear_owner_recursive(c)


static func _is_under(node: Node, ancestor: Node) -> bool:
	var p := node.get_parent()
	while p != null:
		if p == ancestor:
			return true
		p = p.get_parent()
	return false


static func _has_ancestor_type(node: Node, class_nm: String) -> bool:
	var p := node.get_parent()
	while p != null:
		if p.is_class(class_nm):
			return true
		p = p.get_parent()
	return false


static func _set_owner_recursive(node: Node, scene_owner: Node) -> void:
	if node != scene_owner:
		node.owner = scene_owner
	for c in node.get_children():
		_set_owner_recursive(c, scene_owner)
