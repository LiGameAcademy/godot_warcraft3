extends SceneTree
## Team Glow：脚底贴地 + 杖尖 billboard（无平行面片）。


func _init() -> void:
	var glb := "res://assets/asset-converted/Units/Human/HeroArchMage/HeroArchMage.gltf"
	var cache := MapModelCache.new()
	# 强制走 glTF 原型再染色（.scn 可能是旧 bake）
	cache.evict(glb)
	var root: Node3D = cache.instance_glb(glb)
	if root == null:
		push_error("FAIL instance")
		quit(1)
		return
	cache.apply_team_color(root, 0, false)
	var foot_ok := false
	var bb_ok := false
	var parallel_tip := false
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if bool(mi.get_meta("wc3_team_glow_billboard", false)):
			bb_ok = true
			var mat: Material = mi.get_active_material(0)
			var bill := -1
			if mat is StandardMaterial3D:
				bill = (mat as StandardMaterial3D).billboard_mode
			print("BILLBOARD name=", mi.name, " parent=", mi.get_parent().name, " billboard=", bill)
		if str(mi.name).contains("Geoset_2") and not bool(mi.get_meta("wc3_team_glow_billboard", false)):
			foot_ok = mi.visible and mi.mesh != null
			# 脚底应几乎只有 Y 法线
			var arr: Array = mi.mesh.surface_get_arrays(0)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var non_y := 0
			var tris := int(idx.size() / 3)
			for t in range(tris):
				var i0 := idx[t * 3]
				var i1 := idx[t * 3 + 1]
				var i2 := idx[t * 3 + 2]
				var nrm: Vector3 = (v[i1] - v[i0]).cross(v[i2] - v[i0]).normalized()
				if absf(nrm.y) < 0.65:
					non_y += 1
			parallel_tip = non_y > 0
			print("FOOT Geoset_2 tris=", tris, " non_y_tris=", non_y, " presented=", mi.get_meta("wc3_team_glow_presented", false))
	if not foot_ok:
		push_error("FAIL no foot Geoset_2")
		quit(1)
		return
	if not bb_ok:
		push_error("FAIL no tip billboard")
		quit(1)
		return
	if parallel_tip:
		push_error("FAIL foot mesh still has tip parallel planes")
		quit(1)
		return
	# 杖尖应离开骨原点（握柄）；ArchMage Weapon/Plane tip ≈ 0.6~0.75 模型空间单位
	var tip_pos_ok := false
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi2 := n as MeshInstance3D
		if mi2 == null or not bool(mi2.get_meta("wc3_team_glow_billboard", false)):
			continue
		var plen := mi2.position.length()
		print("TIP pos=", mi2.position, " len=", plen, " parent=", mi2.get_parent().name)
		if plen >= 0.4 and plen <= 2.0:
			tip_pos_ok = true
	if not tip_pos_ok:
		push_error("FAIL tip billboard position out of expected range (want 0.4~2.0)")
		quit(1)
		return
	print("OK")
	root.free()
	quit(0)
