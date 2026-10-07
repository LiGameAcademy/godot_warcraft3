class_name SelectorOverlayLayer
extends CanvasLayer

## 高图层（默认 [code]layer = 100[/code]）的框选矩形绘制壳。
##
## 自身持有 [MarqueeOverlay]；通过 [method bind_marquee] 一次性绑
## [MarqueeSelection] 状态，后续框选更新由 [code]MarqueeOverlay[/code] 完成。
##
## 由 [code]GameMain[/code] 平级挂入；[code]UnitSelector[/code] 通过
## [code]@export var overlay_layer: SelectorOverlayLayer[/code] 注入。

## [MarqueeOverlay] 相对路径，供选择器读取「自己人」以豁免 HUD 阻挡判定。
const OVERLAY_PATH: NodePath = ^"OverlayRoot/MarqueeOverlay"

var _overlay: MarqueeOverlay = null


func _ready() -> void:
	_overlay = get_node_or_null(OVERLAY_PATH) as MarqueeOverlay
	# 下一帧强制铺满视口（部分环境下 anchor 首帧 size=0）。
	if is_inside_tree():
		var vp_size: Vector2 = get_viewport().get_visible_rect().size
		var root: Control = get_node_or_null("OverlayRoot") as Control
		if root != null:
			root.set_deferred("size", vp_size)


## 绑定 [MarqueeSelection] 状态（只绑一次）。
func bind_marquee(marquee: MarqueeSelection) -> void:
	if _overlay == null:
		_overlay = get_node_or_null(OVERLAY_PATH) as MarqueeOverlay
	if _overlay != null:
		_overlay.bind(marquee)


## 给选择器用：取绘制节点引用（用于 HUD 阻挡豁免判定）。
func marquee_overlay() -> MarqueeOverlay:
	if _overlay == null:
		_overlay = get_node_or_null(OVERLAY_PATH) as MarqueeOverlay
	return _overlay
