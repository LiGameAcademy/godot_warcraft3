class_name SmartHandlerRegistry
extends RefCounted
## 智能右键 Handler 注册表（按 priority 降序）。
## 开闭：新能力 = 本文件加 class + all_sorted() 多一行。
## 优先级：送回(100) → 采金/伐木(90) → 加入建造(80) → 集结(15) → 移动(10)

class ReturnHandler extends SmartInteractHandler:
	func priority() -> int:
		return 100

	func applies_to(target: SmartTarget) -> bool:
		return target != null and target.kind == SmartTarget.Kind.DROPOFF

	func claim(
		movers: Array[Node3D],
		_rally: Array[Node3D],
		target: SmartTarget,
		router: Variant
	) -> Dictionary:
		var parts: Dictionary = router.split_can_return_to(movers, target.node)
		var special: Array = parts.get("special", [])
		var taken: Array[Node3D] = []
		for n in special:
			if n is Node3D and movers.has(n):
				taken.append(n as Node3D)
				movers.erase(n)
		return {"movers": taken, "rally": []}

	func execute(
		claimed_movers: Array,
		_claimed_rally: Array,
		target: SmartTarget,
		source: int,
		router: Variant
	) -> Dictionary:
		if claimed_movers.is_empty():
			return {}
		var n: int = int(router.issue_return_goods(claimed_movers, source, target.node))
		return {"returned": n}


class HarvestGoldHandler extends SmartInteractHandler:
	func priority() -> int:
		return 90

	func applies_to(target: SmartTarget) -> bool:
		return target != null and target.kind == SmartTarget.Kind.GOLD_MINE

	func claim(
		movers: Array[Node3D],
		_rally: Array[Node3D],
		_target: SmartTarget,
		router: Variant
	) -> Dictionary:
		var parts: Dictionary = router.split_can_harvest(movers)
		var special: Array = parts.get("special", [])
		var taken: Array[Node3D] = []
		for n in special:
			if n is Node3D and movers.has(n):
				taken.append(n as Node3D)
				movers.erase(n)
		return {"movers": taken, "rally": []}

	func execute(
		claimed_movers: Array,
		_claimed_rally: Array,
		target: SmartTarget,
		source: int,
		router: Variant
	) -> Dictionary:
		if claimed_movers.is_empty():
			return {}
		var n: int = int(router.issue_harvest_gold(claimed_movers, target.node, source))
		return {"harvested": n}


class HarvestLumberHandler extends SmartInteractHandler:
	func priority() -> int:
		return 90

	func applies_to(target: SmartTarget) -> bool:
		return target != null and target.kind == SmartTarget.Kind.TREE

	func claim(
		movers: Array[Node3D],
		_rally: Array[Node3D],
		_target: SmartTarget,
		router: Variant
	) -> Dictionary:
		var parts: Dictionary = router.split_can_harvest(movers)
		var special: Array = parts.get("special", [])
		var taken: Array[Node3D] = []
		for n in special:
			if n is Node3D and movers.has(n):
				taken.append(n as Node3D)
				movers.erase(n)
		return {"movers": taken, "rally": []}

	func execute(
		claimed_movers: Array,
		_claimed_rally: Array,
		target: SmartTarget,
		source: int,
		router: Variant
	) -> Dictionary:
		if claimed_movers.is_empty():
			return {}
		var n: int = int(router.issue_harvest_lumber(claimed_movers, target.tree_cn, source))
		return {"harvested": n}


class JoinBuildHandler extends SmartInteractHandler:
	func priority() -> int:
		return 80

	func applies_to(target: SmartTarget) -> bool:
		return target != null and target.kind == SmartTarget.Kind.BUILD_SITE

	func claim(
		movers: Array[Node3D],
		_rally: Array[Node3D],
		_target: SmartTarget,
		_router: Variant
	) -> Dictionary:
		# 工地：全体可移动单位由本 Handler 消化（join 失败再内部降级移动）
		return {"movers": SmartInteractHandler.take_all(movers), "rally": []}

	func execute(
		claimed_movers: Array,
		_claimed_rally: Array,
		target: SmartTarget,
		source: int,
		router: Variant
	) -> Dictionary:
		if claimed_movers.is_empty():
			return {}
		var joined: int = int(router.issue_join_build(claimed_movers, target.node, source))
		var out := {"built": joined, "moved": 0, "failed": 0}
		if joined <= 0:
			var mr: Dictionary = router.issue_move_subset(claimed_movers, target.goal_wc3, source)
			out["moved"] = int(mr.get("moved", 0))
			out["failed"] = int(mr.get("failed", 0))
		return out


class MoveHandler extends SmartInteractHandler:
	func priority() -> int:
		return 10

	func applies_to(target: SmartTarget) -> bool:
		return target != null and target.goal_wc3 != Vector2.INF

	func claim(
		movers: Array[Node3D],
		_rally: Array[Node3D],
		_target: SmartTarget,
		_router: Variant
	) -> Dictionary:
		return {"movers": SmartInteractHandler.take_all(movers), "rally": []}

	func execute(
		claimed_movers: Array,
		_claimed_rally: Array,
		target: SmartTarget,
		source: int,
		router: Variant
	) -> Dictionary:
		if claimed_movers.is_empty():
			return {}
		var mr: Dictionary = router.issue_move_subset(claimed_movers, target.goal_wc3, source)
		return {
			"moved": int(mr.get("moved", 0)),
			"failed": int(mr.get("failed", 0)),
		}


class RallyHandler extends SmartInteractHandler:
	func priority() -> int:
		# 高于 Move(10)：与移动同目标时先写集结；两池互不抢占，但状态/反馈优先看集结
		return 15

	func applies_to(target: SmartTarget) -> bool:
		return target != null and target.goal_wc3 != Vector2.INF

	func claim(
		_movers: Array[Node3D],
		rally: Array[Node3D],
		_target: SmartTarget,
		_router: Variant
	) -> Dictionary:
		return {"movers": [], "rally": SmartInteractHandler.take_all(rally)}

	func execute(
		_claimed_movers: Array,
		claimed_rally: Array,
		target: SmartTarget,
		_source: int,
		router: Variant
	) -> Dictionary:
		if claimed_rally.is_empty():
			return {}
		var typed: Array[Node3D] = []
		for n in claimed_rally:
			if n is Node3D:
				typed.append(n as Node3D)
		return {"rallied": int(router.issue_rally_subset(typed, target))}


class AttackHandler extends SmartInteractHandler:
	func priority() -> int:
		return 50

	func applies_to(target: SmartTarget) -> bool:
		return target != null and target.kind == SmartTarget.Kind.ENEMY_UNIT

	func claim(
		movers: Array[Node3D],
		_rally: Array[Node3D],
		target: SmartTarget,
		_router: Variant
	) -> Dictionary:
		var taken: Array[Node3D] = []
		for n in movers.duplicate():
			if n is Node3D and CombatQuery.is_auto_acquire_target(n, target.node) and CombatQuery.has_weapon(n):
				taken.append(n as Node3D)
				movers.erase(n)
		return {"movers": taken, "rally": []}

	func execute(
		claimed_movers: Array,
		_claimed_rally: Array,
		target: SmartTarget,
		source: int,
		router: Variant
	) -> Dictionary:
		if claimed_movers.is_empty() or target.node == null:
			return {}
		var n: int = int(router.issue_attack_target(claimed_movers, target.node, source))
		return {"moved": n}


static func all_sorted() -> Array[SmartInteractHandler]:
	var list: Array[SmartInteractHandler] = [
		ReturnHandler.new(),
		HarvestGoldHandler.new(),
		HarvestLumberHandler.new(),
		JoinBuildHandler.new(),
		AttackHandler.new(),
		MoveHandler.new(),
		RallyHandler.new(),
	]
	list.sort_custom(func(a: SmartInteractHandler, b: SmartInteractHandler) -> bool:
		return a.priority() > b.priority()
	)
	return list
