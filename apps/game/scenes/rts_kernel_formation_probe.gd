extends Node2D

@export var config: RtsKernelFormationProbeConfig
@onready var _bridge: Node = $RtsKernelBridge
@onready var _status: Label = $Status

var _selected: Array[int] = []
var _views: Array[Dictionary] = []
var _orders: Array[Dictionary] = []
var _sequence: int = 0
var _accumulator: float = 0.0
var _formation: int = 1
var _saved: String = ""
var _feedback: String = ""
var _map_size: Vector2 = Vector2.ZERO


func _ready() -> void:
    if config == null or config.spawn_positions.size() != config.movement_definition_ids.size():
        _status.text = "Invalid probe configuration"
        set_process(false)
        return
    var flags: PackedByteArray = PackedByteArray()
    flags.resize(config.grid_size.x * config.grid_size.y)
    _map_size = Vector2(config.grid_size) * config.cell_size
    if not bool(_bridge.call("ResetConfiguredNavigationMatch", config.grid_size.x, config.grid_size.y,
        config.cell_size, Vector2.ZERO, flags, config.movement_definitions_json, config.tick_rate, config.seed)):
        _status.text = str(_bridge.call("GetLastError"))
        set_process(false)
        return
    _bridge.connect("GroupMoveResultRaised", _on_group_result)
    for i: int in range(config.spawn_positions.size()):
        _bridge.call("SubmitConfiguredSpawn", 1, 0, _sequence, config.spawn_positions[i], config.movement_definition_ids[i])
        _sequence += 1
    _bridge.call("Step", 1)
    _sync_view()
    for view: Dictionary in _views:
        _selected.append(int(view["id"]))
    _sync_view()


func _process(delta: float) -> void:
    _accumulator += delta
    var tick: float = 1.0 / float(_bridge.call("GetTickRate"))
    while _accumulator >= tick:
        _bridge.call("Step", 1)
        _accumulator -= tick
    _sync_view()


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, _map_size), Color(0.10, 0.13, 0.16))
    for order: Dictionary in _orders:
        if bool(order["has_goal"]):
            var goal: Vector2 = order["goal"] as Vector2
            draw_circle(goal, 3.0, Color.ORANGE, false, 1.0)
    for view: Dictionary in _views:
        var position: Vector2 = view["position"] as Vector2
        var radius: float = float(view["radius"])
        draw_circle(position, radius, Color(0.3, 0.75, 1.0))
        draw_line(position, position + Vector2.RIGHT.rotated(float(view["facing"])) * (radius + 3.0), Color.WHITE)
        if _selected.has(int(view["id"])):
            draw_circle(position, radius + 2.0, Color.GREEN, false, 1.0)


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        var mouse: InputEventMouseButton = event as InputEventMouseButton
        if not mouse.pressed:
            return
        if mouse.button_index == MOUSE_BUTTON_LEFT:
            _select_nearest(mouse.position, mouse.shift_pressed)
        elif mouse.button_index == MOUSE_BUTTON_RIGHT and not _selected.is_empty():
            _bridge.call("SubmitGroupMove", int(_bridge.call("GetFrame")) + 1, 0, _sequence,
                PackedInt64Array(_selected), mouse.position, _formation if mouse.shift_pressed else 0,
                0, 0.0, true, mouse.ctrl_pressed, 0)
            _sequence += 1
    elif event is InputEventKey:
        var key: InputEventKey = event as InputEventKey
        if not key.pressed or key.echo:
            return
        if key.keycode >= KEY_1 and key.keycode <= KEY_4:
            _formation = int(key.keycode) - KEY_1
        elif key.keycode == KEY_A:
            _selected.clear()
            for view: Dictionary in _views:
                _selected.append(int(view["id"]))
        elif key.keycode == KEY_SPACE:
            for id: int in _selected:
                _bridge.call("SubmitStop", int(_bridge.call("GetFrame")) + 1, 0, _sequence, id)
                _sequence += 1
        elif key.keycode == KEY_S:
            _saved = str(_bridge.call("CaptureSnapshotJson"))
        elif key.keycode == KEY_R and not _saved.is_empty():
            if bool(_bridge.call("RestoreSnapshotJson", _saved)):
                _accumulator = 0.0
                _sync_view()


func _select_nearest(position: Vector2, additive: bool) -> void:
    var id: int = 0
    var distance: float = 15.0
    for view: Dictionary in _views:
        var point: Vector2 = view["position"] as Vector2
        var candidate: float = point.distance_to(position)
        if candidate < distance:
            id = int(view["id"])
            distance = candidate
    if not additive:
        _selected.clear()
    if id > 0:
        if _selected.has(id):
            _selected.erase(id)
        else:
            _selected.append(id)
    queue_redraw()


func _sync_view() -> void:
    _views = _bridge.call("ReadEntityViews")
    _orders = _bridge.call("ReadOrderViews")
    _status.text = "LMB select / Shift+LMB toggle / A all | RMB compact / Shift+RMB formation / Ctrl append
1 compact 2 rect 3 wedge 4 circle | Space Stop | S save R restore
frame=%d selected=%d formation=%d %s" % [
        int(_bridge.call("GetFrame")), _selected.size(), _formation, _feedback]
    queue_redraw()


func _on_group_result(_frame: int, _group_id: int, entity_id: int, slot: int, _goal: Vector2,
    assigned: bool, adjusted: bool, reason: String) -> void:
    _feedback = "unit=%d slot=%d assigned=%s adjusted=%s %s" % [entity_id, slot, str(assigned), str(adjusted), reason]
