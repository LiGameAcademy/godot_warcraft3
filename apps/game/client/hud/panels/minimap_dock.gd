class_name MinimapDock
extends MarginContainer

## 左下角小地图坞：容器职责仅布局；地图交互在 GameMinimap。

signal clicked(uv: Vector2)

@onready var minimap: GameMinimap = %Minimap


func _ready() -> void:
	if minimap != null and not minimap.clicked.is_connected(_on_minimap_clicked):
		minimap.clicked.connect(_on_minimap_clicked)


func configure(
	map_directory: String,
	heightfield: Wc3Heightfield,
	unit_host: Node,
	camera: Camera3D,
	camera_rig: Node3D,
	local_player: int = 0,
	catalog: Wc3IdCatalog = null
) -> void:
	if minimap == null:
		return
	minimap.configure(heightfield, unit_host, camera, camera_rig, local_player, catalog)
	if not map_directory.is_empty():
		minimap.load_from_map_dir(map_directory)


func load_from_map_dir(map_directory: String) -> bool:
	if minimap == null:
		return false
	return minimap.load_from_map_dir(map_directory)


func set_background_texture(tex: Texture2D) -> void:
	if minimap != null:
		minimap.set_background_texture(tex)


## 响应式：左下角方坞，边长跟底栏高度联动。
func apply_layout(side: float, margin: float) -> void:
	var s := maxf(side, 96.0)
	var m := maxf(margin, 4.0)
	custom_minimum_size = Vector2(s, s)
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = m
	offset_right = m + s
	offset_top = -(m + s)
	offset_bottom = -m
	var panel := get_node_or_null("MinimapPanel") as PanelContainer
	if panel != null:
		panel.custom_minimum_size = Vector2(s, s)
	if minimap != null:
		minimap.custom_minimum_size = Vector2(s, s)


func _on_minimap_clicked(uv: Vector2) -> void:
	clicked.emit(uv)
