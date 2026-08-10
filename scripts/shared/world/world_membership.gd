class_name WorldMembership
extends RefCounted

## 「在世界成员资格」—— 把单位从游戏世界临时移除 / 添加回。
##
## 与 `visible` 或 `selection_blocked` 不同，本 API 表达的是"这个实体当前是
## 否参与世界（选择 / 寻路 / 镜头 / 渲染 / 物理）"。视觉上的隐身、未来
## 「灵魂 / 缴械 / 空运」等表现层效果都可以叠在 enter/exit 之上，但本
## 概念本身只负责"在不在场"。
##
## 典型调用点：
## - 农民进金矿 / 出矿（HarvestController）
## - 农民到位 → 工地（BuildController._on_arrived）
## - 工地完工 → 真实建筑（BuildController._on_site_completed）
## - 训练中模型（未来 TrainQueue）
## - 死亡 / 空运等暂态（未来）
##
## 副作用（exit 时一次性投递）：
##   1. 写入 META_IN_WORLD = false（用于 UnitCrowdQuery / UnitSelector 查询）
##   2. 顶层节点 visible = false（保留子节点原始状态，enter 时恢复）
##   3. 若节点在 UnitSelector 当前选中里，自动移除（无需调用方手动选择清理）
##
## 约束：
## - 仅 Node3D。其他类型 → push_error 拒收。
## - exit/enter 幂等（重复 exit 不重复存档；未 exit 过直接 enter 不操作）。
## - enter 之前必须 exit 过（避免误把首次可见的节点"恢复"成另一个状态）。

const META_IN_WORLD := "world_member_in_world"


## 离开游戏世界：不再参与选择 / 寻路裁剪 / 渲染 / 物理。
static func exit(node: Node3D) -> void:
	if node == null:
		return
	if not (node is Node3D):
		push_error("WorldMembership.exit: 期望 Node3D，实际 %s" % node.get_class())
		return
	# 幂等：已离场则不重复
	if not is_in_world(node):
		return
	node.set_meta(META_IN_WORLD, false)
	node.visible = false
	_remove_from_selection(node)


## 回到游戏世界：恢复其在选择 / 寻路裁剪 / 渲染 / 物理中的角色。
## 若节点从未 exit 过（首次 enter），不操作（避免误把任意可见节点"恢复"）。
static func enter(node: Node3D) -> void:
	if node == null:
		return
	if not (node is Node3D):
		push_error("WorldMembership.enter: 期望 Node3D，实际 %s" % node.get_class())
		return
	# 仅恢复曾被 exit 的节点；首次调用 enter（无 meta）时不动作
	if not node.has_meta(META_IN_WORLD):
		return
	node.set_meta(META_IN_WORLD, true)
	node.visible = true


## 查询：节点当前是否在游戏世界中。无 meta 视为"在场"（首次进入默认在场）。
static func is_in_world(node: Node) -> bool:
	if node == null:
		return false
	if not node.has_meta(META_IN_WORLD):
		return true
	return bool(node.get_meta(META_IN_WORLD, false))


## 内部：从当前 UnitSelector 选中移除（若存在）。失败静默（开发期走
## `Engine.has_singleton` 不靠谱；改为 duck-call）。
static func _remove_from_selection(node: Node3D) -> void:
	var root := Engine.get_main_loop()
	if root == null:
		return
	# UnitSelector 可能在 GameDirector / Editor 任意路径下；用 `find_child` 易漏。
	# 改成「找到第一个带 deselect_unit 方法的 Node」即可。
	var sel := _find_unit_selector()
	if sel == null:
		return
	if sel.has_method("deselect_unit"):
		sel.call("deselect_unit", node)


static func _find_unit_selector() -> Node:
	# 1. 当前 scene 主树里找
	var root := Engine.get_main_loop()
	if root is SceneTree:
		var tree: SceneTree = root
		var cur := tree.current_scene
		var guard := 0
		while cur != null and guard < 8:
			if cur.has_method("deselect_unit"):
				return cur
			# 优先找名字为 UnitSelector 的子节点
			var c := cur.find_child("UnitSelector", true, false)
			if c != null and c.has_method("deselect_unit"):
				return c
			cur = cur.get_parent()
			guard += 1
	return null
