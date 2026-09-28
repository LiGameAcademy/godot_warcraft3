extends HBoxContainer
## Frame positions are preview samples, not source keyframe indices.
signal time_requested(seconds: float)
signal pause_requested
signal loop_changed

@export_range(1, 120) var preview_fps: int = 30
@onready var current: SpinBox = %CurrentFrame
@onready var maximum: Label = %MaximumFrame
@onready var rate: Label = %FrameRate
@onready var loop_toggle: CheckButton = %Loop
var _player: AnimationPlayer
var _length: float = 0.0

func _ready() -> void:
	current.value_changed.connect(_request_frame)
	loop_toggle.toggled.connect(_set_loop)
	current.get_line_edit().focus_entered.connect(func() -> void: pause_requested.emit())
	rate.text = "帧（%d FPS）" % preview_fps
	bind_animation(null)

func bind_animation(player: AnimationPlayer) -> void:
	if is_instance_valid(player) and player != _player:
		_isolate_animations(player)
	_player = player
	_length = 0.0
	if is_instance_valid(player) and player.has_animation(player.assigned_animation):
		_length = player.get_animation(player.assigned_animation).length
	current.editable = _length > 0.0
	loop_toggle.disabled = not current.editable
	loop_toggle.set_pressed_no_signal(current.editable and player.get_animation(player.assigned_animation).loop_mode != Animation.LOOP_NONE)
	current.set_value_no_signal(0.0)
	current.max_value = ceilf(_length * preview_fps)
	maximum.text = "/ %d" % int(current.max_value)
	set_process(current.editable)
	_sync_position()

func _process(_delta: float) -> void:
	if not current.get_line_edit().has_focus():
		_sync_position()

func _sync_position() -> void:
	if not is_instance_valid(_player) or _length <= 0.0:
		return
	var seconds: float = _player.current_animation_position
	var frame: int = int(current.max_value) if seconds >= _length else floori(seconds * preview_fps + 0.00001)
	current.set_value_no_signal(clampi(frame, 0, int(current.max_value)))

func _request_frame(value: float) -> void:
	if not is_instance_valid(_player) or _length <= 0.0:
		return
	pause_requested.emit()
	time_requested.emit(minf(value / preview_fps, _length))

func _set_loop(enabled: bool) -> void:
	if not is_instance_valid(_player) or _length <= 0.0:
		return
	var animation: Animation = _player.get_animation(_player.assigned_animation)
	animation.loop_mode = Animation.LOOP_LINEAR if enabled else Animation.LOOP_NONE
	loop_changed.emit()
	if enabled and not _player.is_playing():
		_player.play(_player.assigned_animation)
		_player.seek(0.0, true)

func _isolate_animations(player: AnimationPlayer) -> void:
	var selected: StringName = player.assigned_animation
	var position: float = player.current_animation_position if not selected.is_empty() else 0.0
	var playing: bool = player.is_playing()
	# Libraries and animations can be shared by PackedScene instances. Preview
	# loop edits must never reach another instance or the loaded template.
	for library_name: StringName in player.get_animation_library_list():
		var source: AnimationLibrary = player.get_animation_library(library_name)
		var local: AnimationLibrary = AnimationLibrary.new()
		for animation_name: StringName in source.get_animation_list():
			local.add_animation(animation_name, source.get_animation(animation_name).duplicate())
		player.remove_animation_library(library_name)
		player.add_animation_library(library_name, local)
	if not selected.is_empty():
		player.play(selected)
		player.seek(position, true)
		if not playing:
			player.pause()
