extends SceneTree
## C-1 attachments sidecar selftest。
## 验证 m2g extractAttachments 写出的 .attachments.json 完整（4 类 + geoset 展开）。
## 不测 .scn 烘焙拼装（留 C-2）。
## godot --headless --path . -s res://tests/unit/selftest_attachments.gd

var passed: int = 0
var total: int = 5


func _init() -> void:
	_test_townhall_attachment_count()
	_test_townhall_flag_groups()
	_test_townhall_light()
	_test_townhall_particle_count()
	_test_footman_attachments()

	if passed == total:
		print("selftest_attachments: PASS")
		quit(0)
	else:
		push_error("selftest_attachments: FAIL %d/%d" % [passed, total])
		quit(1)


# Test 1: TownHall 应该有 >= 30 attachment（8 Ref + 21 particle + 1 light = 30）
func _test_townhall_attachment_count() -> void:
	var path := "res://assets/asset-converted/Buildings/Human/TownHall/TownHall.attachments.json"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("test_1 FAIL: cannot open %s" % path)
		return
	var text := f.get_as_text()
	f.close()
	var j = JSON.parse_string(text)
	if j == null:
		push_error("test_1 FAIL: parse null")
		return
	if j.version != 1:
		push_error("test_1 FAIL: version != 1 (got %s)" % j.version)
		return
	if not "attachments" in j or not "geoset_expansions" in j:
		push_error("test_1 FAIL: missing attachments or geoset_expansions")
		return
	if j.attachments.size() < 30:
		push_error("test_1 FAIL: expected >= 30 attachments got %d" % j.attachments.size())
		return
	var type_count := {}
	for a in j.attachments:
		type_count[a.type] = type_count.get(a.type, 0) + 1
	if not type_count.has("attachment") or type_count["attachment"] < 8:
		push_error("test_1 FAIL: attachment count %s" % str(type_count))
		return
	if not type_count.has("particle") or type_count["particle"] < 21:
		push_error("test_1 FAIL: particle count %s" % str(type_count))
		return
	if not type_count.has("light"):
		push_error("test_1 FAIL: missing light type %s" % str(type_count))
		return
	print("  TownHall attachments: %d (4 类齐全 attachment/particle/light)" % j.attachments.size())
	passed += 1


# Test 2: TownHall Geoset_0 (旗子 mesh) 应该有 >= 15 个 flag bone group
func _test_townhall_flag_groups() -> void:
	var j = _load_json("res://assets/asset-converted/Buildings/Human/TownHall/TownHall.attachments.json")
	if j == null:
		return
	var flag_groups := []
	for g in j.geoset_expansions:
		if g.geoset_name == "Geoset_0":
			for grp in g.groups:
				for b in grp.bones:
					if str(b).begins_with("Flag"):
						flag_groups.append(grp)
						break
			break
	if flag_groups.size() < 15:
		push_error("test_2 FAIL: expected >= 15 flag groups got %d" % flag_groups.size())
		return
	var flag_bones := {}
	for grp in flag_groups:
		for b in grp.bones:
			if str(b).begins_with("Flag"):
				flag_bones[b] = true
	if flag_bones.size() < 15:
		push_error("test_2 FAIL: expected >= 15 unique flag bones got %d" % flag_bones.size())
		return
	print("  TownHall Geoset_0: %d flag groups, %d unique flag bones" % [flag_groups.size(), flag_bones.size()])
	passed += 1


# Test 3: TownHall 应该有 1 个 light attachment（铃铛光晕）
func _test_townhall_light() -> void:
	var j = _load_json("res://assets/asset-converted/Buildings/Human/TownHall/TownHall.attachments.json")
	if j == null:
		return
	var light_count := 0
	for a in j.attachments:
		if a.type == "light":
			light_count += 1
	if light_count != 1:
		push_error("test_3 FAIL: expected 1 light got %d" % light_count)
		return
	print("  TownHall light attachment: 1 (铃铛光晕)")
	passed += 1


# Test 4: TownHall 应该有 21 个 particle attachment
func _test_townhall_particle_count() -> void:
	var j = _load_json("res://assets/asset-converted/Buildings/Human/TownHall/TownHall.attachments.json")
	if j == null:
		return
	var particle_count := 0
	for a in j.attachments:
		if a.type == "particle":
			particle_count += 1
	if particle_count != 21:
		push_error("test_4 FAIL: expected 21 particles got %d" % particle_count)
		return
	print("  TownHall particle attachment: 21")
	passed += 1


# Test 5: Footman attachments + geoset_expansions 写出 + parse 一致
func _test_footman_attachments() -> void:
	var j = _load_json("res://assets/asset-converted/Units/Human/Footman/Footman.attachments.json")
	if j == null:
		return
	if j.attachments.size() < 5:
		push_error("test_5 FAIL: Footman attachments < 5 got %d" % j.attachments.size())
		return
	if j.geoset_expansions.size() < 3:
		push_error("test_5 FAIL: Footman geoset_expansions < 3 got %d" % j.geoset_expansions.size())
		return
	var ref_count := 0
	for a in j.attachments:
		if a.type == "attachment":
			ref_count += 1
	if ref_count < 5:
		push_error("test_5 FAIL: Footman ref attachments < 5 got %d" % ref_count)
		return
	print("  Footman attachments: %d, geoset_expansions: %d, ref: %d" % [j.attachments.size(), j.geoset_expansions.size(), ref_count])
	passed += 1


func _load_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("cannot open %s" % path)
		return null
	var text := f.get_as_text()
	f.close()
	return JSON.parse_string(text)
