class_name Wc3RampPlacement
extends RefCounted

## Logic → Present 的斜坡（CliffTrans）放置契约。
## Present 禁止改 Heightfield；只拿本结构 + Catalog 做资源解析与挂接。
## 字段对齐重建前 Dictionary placement（见 git 060b5ce），禁止再散落字符串键。

var ix: int = 0
var iy: int = 0
## CliffTrans 四字 TAG（角序 TL,TR,BR,BL）
var tag: String = ""
var base_layer: int = 2
## heightfield.cliff_textures 下标（岩壁贴图族）
var cliff_tex_index: int = 0
## Catalog.ramp_model_dir / CliffTypes.rampModelDir（配置）；Present 用其 resolve
var model_dir: String = "CliffTrans"
var variation: int = 0
## "v" | "h"（Wc3RampKinds.AXIS_*）
var axis: String = Wc3RampKinds.AXIS_V
## 竖条：旗在左列；横条：旗在底行
var ramp_left: bool = true
var ramp_bottom: bool = true
## Logic 拓扑形态（Straight / Outer / …）
var topology: int = Wc3RampKinds.TOPO_STRAIGHT
## 幻影对侧（同脊双 TAG 中不挂模的一侧）
var phantom: bool = false
## 宽坡（邻脊 / 双旗列）
var wide: bool = false
## Logic 已确认 Catalog 有 GLB；Present 仍应 resolve，缺模则记 missing
var has_glb: bool = false


static func make(
	p_ix: int,
	p_iy: int,
	p_tag: String,
	p_base_layer: int,
	p_tex_idx: int,
	p_model_dir: String,
	p_variation: int = 0,
	p_axis: String = Wc3RampKinds.AXIS_V,
	p_ramp_left: bool = true,
	p_ramp_bottom: bool = true
) -> Wc3RampPlacement:
	var p := Wc3RampPlacement.new()
	p.ix = p_ix
	p.iy = p_iy
	p.tag = p_tag
	p.base_layer = p_base_layer
	p.cliff_tex_index = p_tex_idx
	p.model_dir = p_model_dir if not p_model_dir.is_empty() else "CliffTrans"
	p.variation = p_variation
	p.axis = p_axis
	p.ramp_left = p_ramp_left
	p.ramp_bottom = p_ramp_bottom
	return p
