class_name PathAgentProfile
extends RefCounted
## 寻路智能体轮廓（Logic）：把 UnitBalance.collision 收成格子净空。
##
## PATHFINDING_CHOICE · PathAgentProfile：
## - 全局图仍是 WPM；本结构只描述「这个单位要多宽的通道」。
## - clearance_cells=0：与旧行为一致（单格可走即可）。
## - clearance_cells=1：中心格周围 3×3 都必须可走，避免胖子钻墙缝。

## WC3 碰撞半径（来自 UnitBalance.collision）
var radius_wc3: float = 16.0
## Chebyshev 净空：检查 [-c..c]×[-c..c] 邻域全可走
var clearance_cells: int = 0
## 预留：walk / float / fly / amphibious
var move_type: String = "foot"


## 由碰撞半径推导净空格数。
## 直径占满几格 → 半宽向下取整为 clearance。
## 例：r=16→径32→1 格→c=0；r=48→径96→3 格→c=1。
static func clearance_from_radius(
	p_radius_wc3: float,
	cell_size: float = Wc3Coords.PATHING_CELL
) -> int:
	if p_radius_wc3 <= 0.0 or cell_size <= 0.0:
		return 0
	var diam_cells := int(ceil((p_radius_wc3 * 2.0) / cell_size))
	@warning_ignore("integer_division")
	return maxi(0, (diam_cells - 1) / 2)


static func make(p_radius_wc3: float, p_move_type: String = "foot") -> RefCounted:
	var p = new()
	p.radius_wc3 = maxf(p_radius_wc3, 0.0)
	p.clearance_cells = clearance_from_radius(p.radius_wc3)
	p.move_type = p_move_type
	return p
