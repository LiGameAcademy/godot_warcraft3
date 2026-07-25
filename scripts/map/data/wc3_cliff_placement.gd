class_name Wc3CliffPlacement
extends RefCounted

## Logic → Present 的直崖放置契约（不含 GLB 路径）。
## Present 用 cliff_tex_index + Catalog 解析 modelDir / PNG / GLB。

var ix: int = 0
var iy: int = 0
var tag: String = ""
var base_layer: int = 2
var cliff_tex_index: int = 0
## 已按 Catalog 变体上限夹紧 / 哈希打散后的变体下标
var variation: int = 0


static func make(
	p_ix: int,
	p_iy: int,
	p_tag: String,
	p_base_layer: int,
	p_tex_idx: int,
	p_variation: int
) -> Wc3CliffPlacement:
	var p := Wc3CliffPlacement.new()
	p.ix = p_ix
	p.iy = p_iy
	p.tag = p_tag
	p.base_layer = p_base_layer
	p.cliff_tex_index = p_tex_idx
	p.variation = p_variation
	return p
