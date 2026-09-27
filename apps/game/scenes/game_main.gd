extends Node3D

@onready var world_environment: WorldEnvironment = %WorldEnvironment
@onready var sun: DirectionalLight3D = %Sun
@onready var map_root: MapLoader = %MapRoot
@onready var rts_camera: RtsCamera = %RtsCamera
@onready var game_hud: GameHud = %GameHud
@onready var health_bar_manager: HealthBarManager = %HealthBarManager
@onready var unit_selector: UnitSelector = %UnitSelector
@onready var game_director: GameDirector = %GameDirector
@onready var game_cursor: Wc3GameCursor = %GameCursor
@onready var game_loading_screen: GameLoadingScreen = %GameLoadingScreen

func _ready() -> void:
	_setup_game_loading_screen()
	
func _setup_game_loading_screen() -> void:
	game_loading_screen.map_root = map_root
	game_loading_screen.game_director = game_director
	game_loading_screen.game_hud = game_hud
	game_loading_screen.health_bar_manager = health_bar_manager
	game_loading_screen.setup()
