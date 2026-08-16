class_name SmartInteractHandler
extends RefCounted
## 右键智能：能力 × SmartTarget → 认领单位并执行。
## 新增交互：加 Handler 并注册到 SmartHandlerRegistry，勿改 CommandRouter.issue_smart 中枢。

## 越大越先跑（特殊交互 > 移动 > 集结）。
func priority() -> int:
	return 0


func applies_to(_target: SmartTarget) -> bool:
	return false


## 从池中认领；就地从 movers/rally 移除已认领节点。
## 返回 { "movers": Array[Node3D], "rally": Array[Node3D] }。
## router：CommandRouter（避免与 Router 循环依赖，参数不写类型）。
func claim(
	_movers: Array[Node3D],
	_rally: Array[Node3D],
	_target: SmartTarget,
	_router: Variant
) -> Dictionary:
	return {"movers": [], "rally": []}


## 对已认领单位执行；返回部分计数（harvested/returned/moved/failed/rallied/built）。
func execute(
	_claimed_movers: Array,
	_claimed_rally: Array,
	_target: SmartTarget,
	_source: int,
	_router: Variant
) -> Dictionary:
	return {}


## 谓词为 true 的节点移出 pool，返回取出列表。
static func take_where(pool: Array[Node3D], pred: Callable) -> Array[Node3D]:
	var taken: Array[Node3D] = []
	var i := 0
	while i < pool.size():
		var n: Node3D = pool[i]
		if bool(pred.call(n)):
			taken.append(n)
			pool.remove_at(i)
		else:
			i += 1
	return taken


## 取出池中全部（复制后清空）。
static func take_all(pool: Array[Node3D]) -> Array[Node3D]:
	var taken: Array[Node3D] = pool.duplicate()
	pool.clear()
	return taken
