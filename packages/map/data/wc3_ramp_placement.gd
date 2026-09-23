class_name Wc3RampPlacement
extends RefCounted

## Logic → Present：一格 CliffTrans 放置（对齐 HiveWE update_cliff_meshes 命中）。

const AXIS_H := "h"
const AXIS_V := "v"
const AXIS_D := "d"

const VARIANT_STRAIGHT := "straight"
## 外角整块：3×3 九旗（HiveWE allow_ramp_diagonal）
const VARIANT_DIAGONAL := "diagonal"
## 转角 L：两臂（各 3 点）+ 仅补凹口中心 1 点；绝不是 3×3
const VARIANT_L := "l"

var ix: int = 0
var iy: int = 0
## CliffTrans 四字 TAG（HiveWE 角序，见 Catalog）
var tag: String = ""
var base_layer: int = 2
var cliff_tex_index: int = 0
var model_dir: String = "CliffTrans"
var variation: int = 0
var axis: String = AXIS_V
## Catalog 已能 resolve 到 GLB
var has_glb: bool = false


static func make(
	p_ix: int,
	p_iy: int,
	p_tag: String,
	p_base_layer: int,
	p_tex_idx: int,
	p_model_dir: String,
	p_axis: String = AXIS_V,
	p_variation: int = 0,
	p_has_glb: bool = false
) -> Wc3RampPlacement:
	var p := Wc3RampPlacement.new()
	p.ix = p_ix
	p.iy = p_iy
	p.tag = p_tag
	p.base_layer = p_base_layer
	p.cliff_tex_index = p_tex_idx
	p.model_dir = p_model_dir if not p_model_dir.is_empty() else "CliffTrans"
	p.axis = p_axis
	p.variation = p_variation
	p.has_glb = p_has_glb
	return p
