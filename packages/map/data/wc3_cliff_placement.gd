class_name Wc3CliffPlacement
extends RefCounted

## Logic → Present 的直崖放置契约。
## Present 禁止改 Heightfield；只拿本结构 + Catalog 做资源解析与挂接。

var ix: int = 0
var iy: int = 0
var tag: String = ""
var base_layer: int = 2
var cliff_tex_index: int = 0
## Catalog.cliff_model_dir 结果（配置）；Present 用其 resolve_glb
var model_dir: String = "Cliffs"
## 已按变体上限夹紧 / 哈希打散
var variation: int = 0


static func make(
	p_ix: int,
	p_iy: int,
	p_tag: String,
	p_base_layer: int,
	p_tex_idx: int,
	p_model_dir: String,
	p_variation: int
) -> Wc3CliffPlacement:
	var p := Wc3CliffPlacement.new()
	p.ix = p_ix
	p.iy = p_iy
	p.tag = p_tag
	p.base_layer = p_base_layer
	p.cliff_tex_index = p_tex_idx
	p.model_dir = p_model_dir if not p_model_dir.is_empty() else "Cliffs"
	p.variation = p_variation
	return p
