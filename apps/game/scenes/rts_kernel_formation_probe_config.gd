extends Resource
class_name RtsKernelFormationProbeConfig

## Read-only diagnostic content; formal game content will produce the same frozen movement definitions.
@export var grid_size: Vector2i = Vector2i(32, 32)
@export var cell_size: float = 10.0
@export var tick_rate: int = 30
@export var seed: int = 7
@export var spawn_positions: PackedVector2Array = PackedVector2Array(
    [Vector2(35, 35), Vector2(55, 35), Vector2(75, 35), Vector2(95, 35), Vector2(115, 35), Vector2(135, 35)])
@export var movement_definition_ids: PackedInt64Array = PackedInt64Array([1, 2, 1, 2, 1, 2])
@export_multiline var movement_definitions_json: String = '[{"id":1,"speed":30,"radius":4},{"id":2,"speed":20,"radius":6}]'
