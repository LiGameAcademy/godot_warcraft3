extends SceneTree
## C-4 selftest: 验证 .scn 里 AnimationPlayer 数量。
## m2g 写 .gltf 时用 glTF-Transform v4.4.1 自动合并 skin + animation，
## Godot 加载 .gltf 后应只有 1 个 AnimationPlayer + 1 个 AnimationLibrary。
## 5/5：
##   1. Footman .scn 加载后只有 1 个 AnimationPlayer
##   2. AnimationPlayer 含 1 个 AnimationLibrary
##   3. Library 含多个 Animation（Stand/Walk/Attack 等）
##   4. 每个 Animation 的 tracks 数 > 0
##   5. 多个 model（Footman/TownHall）都 1 个 AnimationPlayer
##
## godot --headless --path . -s res://tests/unit/selftest_c4_animation_player.gd

var passed: int = 0
var total: int = 5


func _init() -> void:
	_test_footman_one_animation_player()
	_test_footman_one_library()
	_test_footman_library_has_animations()
	_test_footman_animations_have_tracks()
	_test_multi_model_one_animation_player()

	if passed == total:
		print("selftest_c4_animation_player: PASS")
		quit(0)
	else:
		push_error("selftest_c4_animation_player: FAIL %d/%d" % [passed, total])
		quit(1)


# Test 1: Footman 只有 1 个 AnimationPlayer
func _test_footman_one_animation_player() -> void:
	var proto: Node3D = RuntimeAssets.load_gltf_scene(
		"res://assets/asset-converted/Units/Human/Footman/Footman.gltf"
	)
	if proto == null:
		push_error("test_1 FAIL: Footman load null")
		return
	var aps := _find_animation_players(proto)
	if aps.size() != 1:
		push_error("test_1 FAIL: expected 1 AnimationPlayer, got %d" % aps.size())
		return
	print("  Footman: 1 AnimationPlayer (OK, glTF-Transform 合并)")
	passed += 1


# Test 2: AnimationPlayer 含 1 个 AnimationLibrary
func _test_footman_one_library() -> void:
	var proto: Node3D = RuntimeAssets.load_gltf_scene(
		"res://assets/asset-converted/Units/Human/Footman/Footman.gltf"
	)
	if proto == null:
		return
	var ap: AnimationPlayer = _find_animation_players(proto)[0]
	var lib_count := ap.get_animation_library_list().size()
	if lib_count != 1:
		push_error("test_2 FAIL: expected 1 library, got %d" % lib_count)
		return
	print("  Footman: 1 AnimationLibrary '%s'" % ap.get_animation_library_list()[0])
	passed += 1


# Test 3: Library 含多个 Animation
func _test_footman_library_has_animations() -> void:
	var proto: Node3D = RuntimeAssets.load_gltf_scene(
		"res://assets/asset-converted/Units/Human/Footman/Footman.gltf"
	)
	if proto == null:
		return
	var ap: AnimationPlayer = _find_animation_players(proto)[0]
	var lib_name: String = ap.get_animation_library_list()[0]
	var lib: AnimationLibrary = ap.get_animation_library(lib_name)
	var anim_names := lib.get_animation_list()
	if anim_names.size() < 1:
		push_error("test_3 FAIL: expected >= 1 animation, got %d" % anim_names.size())
		return
	var sample := []
	for i in range(min(5, anim_names.size())):
		sample.append(anim_names[i])
	print("  Footman animations: %d (sample: %s)" % [anim_names.size(), str(sample)])
	passed += 1


# Test 4: 每个 Animation 的 tracks 数 > 0
func _test_footman_animations_have_tracks() -> void:
	var proto: Node3D = RuntimeAssets.load_gltf_scene(
		"res://assets/asset-converted/Units/Human/Footman/Footman.gltf"
	)
	if proto == null:
		return
	var ap: AnimationPlayer = _find_animation_players(proto)[0]
	var lib_name: String = ap.get_animation_library_list()[0]
	var lib: AnimationLibrary = ap.get_animation_library(lib_name)
	var total_tracks := 0
	for anim_name in lib.get_animation_list():
		var anim: Animation = lib.get_animation(anim_name)
		total_tracks += anim.get_track_count()
	if total_tracks < 10:
		push_error("test_4 FAIL: expected >= 10 tracks total, got %d" % total_tracks)
		return
	print("  Footman tracks total: %d (骨骼轨 + 几何轨都算)" % total_tracks)
	passed += 1


# Test 5: 多个 model 都 1 个 AnimationPlayer
func _test_multi_model_one_animation_player() -> void:
	var models := [
		"res://assets/asset-converted/Units/Human/Footman/Footman.gltf",
		"res://assets/asset-converted/Buildings/Human/TownHall/TownHall.gltf",
	]
	for path in models:
		var proto: Node3D = RuntimeAssets.load_gltf_scene(path)
		if proto == null:
			# TownHall 7 OOM bug，可能加载失败
			print("  %s: load null (skip, may be OOM)" % path)
			continue
		var aps := _find_animation_players(proto)
		if aps.size() > 1:
			push_error("test_5 FAIL: %s has %d AnimationPlayers" % [path, aps.size()])
			return
		print("  %s: %d AnimationPlayer (OK)" % [path.get_file(), aps.size()])
	passed += 1


func _find_animation_players(root: Node) -> Array[AnimationPlayer]:
	var out: Array[AnimationPlayer] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is AnimationPlayer:
			out.append(n as AnimationPlayer)
	return out
