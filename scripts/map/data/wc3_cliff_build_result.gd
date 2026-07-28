class_name Wc3CliffBuildResult
extends RefCounted

## Present 侧：placements → MultiMesh 分组结果。

class Group extends RefCounted:
	var glb: String = ""
	var cliff_tex_index: int = 0
	var transforms: Array[Transform3D] = []
	## 与 transforms 等长；地表格锚点
	var tiles: Array[Vector2i] = []
	## 与 transforms 等长；叠段 base_layer（藏崖按模型实例判断）
	var base_layers: Array[int] = []


var groups: Array[Group] = []
var placed_cliffs: int = 0
var missing: int = 0
