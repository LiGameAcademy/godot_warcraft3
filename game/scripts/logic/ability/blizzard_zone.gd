class_name BlizzardZone
extends Node

## 暴风雪引导区域（Logic+Present 桥）：引导期间按 DataD 落波；caster 失引导则中止。
## 每波：多点落冰 FX + EffectDamageAoe.run_all_victims（友伤/建筑）。

signal finished(success: bool)

const WAVE_FX_LIFETIME := 1.35
const WAVE_FX_JITTER_FRAC := 0.72
## 原作建筑约半伤；DataC 在本仓库用作每波落冰柱数（见 BLIZZARD.md）
const BUILDING_DAMAGE_FACTOR := 0.5

var _caster: Node3D = null
var _abil_id: String = ""
var _center_wc3 := Vector2.ZERO
var _radius: float = 200.0
var _waves_left: int = 0
var _damage: float = 0.0
var _interval: float = 0.5
var _timer: float = 0.0
var _shards_per_wave: int = 3
var _ctx: Dictionary = {}
var _cancelled: bool = false
var _decal: BlizzardAreaDecal = null
var _total_waves: int = 0
var _wave_index: int = 0
var _loop_sfx: AudioStreamPlayer3D = null


func is_active() -> bool:
	return is_instance_valid(self) and _waves_left > 0 and not _cancelled


func configure(
	caster: Node3D,
	abil_id: String,
	center_wc3: Vector2,
	radius: float,
	waves: int,
	damage_per_wave: float,
	interval_sec: float,
	pipeline: DamagePipeline,
	unit_host: Node,
	ctx: Dictionary = {},
	shards_per_wave: int = 3
) -> void:
	_caster = caster
	_abil_id = abil_id.strip_edges()
	_center_wc3 = center_wc3
	_radius = maxf(radius, 1.0)
	_total_waves = maxi(waves, 1)
	_waves_left = _total_waves
	_damage = maxf(damage_per_wave, 0.0)
	_interval = maxf(interval_sec, 0.05)
	_shards_per_wave = clampi(shards_per_wave, 1, 6)
	_ctx = ctx.duplicate(true)
	# 兼容旧调用方：pipeline / unit_host 写入 ctx，供 EffectContext 读取。
	if pipeline != null and not _ctx.has("damage_pipeline"):
		_ctx["damage_pipeline"] = pipeline
	if unit_host != null and not _ctx.has("unit_host"):
		_ctx["unit_host"] = Callable(func() -> Node: return unit_host)
	_timer = mini(_interval, 0.35)
	_wave_index = 0
	var dur := float(_total_waves) * _interval + 0.75
	_spawn_area_decal(dur)
	_start_loop_sfx()
	set_process(true)


func cancel() -> void:
	if _cancelled:
		return
	_cancelled = true
	_waves_left = 0
	set_process(false)
	_teardown_presentation()
	_finish(false)


func _spawn_area_decal(duration_sec: float) -> void:
	var map_root: Node = _ctx.get("map_root")
	var hf: Variant = _ctx.get("heightfield")
	if map_root == null:
		return
	_decal = BlizzardAreaDecal.spawn(
		map_root, _center_wc3, _radius, duration_sec, hf as Wc3Heightfield
	)


func _start_loop_sfx() -> void:
	var map_root: Node = _ctx.get("map_root")
	if map_root == null:
		return
	_loop_sfx = AbilitySfx.start_loop(map_root, "BlizzardLoop", "BlizzardLoopSfx")
	if _loop_sfx != null:
		var z := 0.0
		var hf: Variant = _ctx.get("heightfield")
		if hf is Wc3Heightfield and (hf as Wc3Heightfield).is_valid():
			z = (hf as Wc3Heightfield).interpolated_height(_center_wc3.x, _center_wc3.y)
		_loop_sfx.global_position = Wc3Coords.wc3_xy_to_godot(_center_wc3.x, _center_wc3.y, z)


func _teardown_presentation() -> void:
	if _decal != null and is_instance_valid(_decal):
		_decal.queue_free()
		_decal = null
	var map_root: Node = _ctx.get("map_root")
	AbilitySfx.stop_named(map_root, "BlizzardLoopSfx")
	_loop_sfx = null


func _process(delta: float) -> void:
	if _cancelled or _waves_left <= 0:
		set_process(false)
		return
	if _caster == null or not is_instance_valid(_caster):
		cancel()
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_apply_wave()
	_waves_left -= 1
	_wave_index += 1
	if _waves_left <= 0:
		_finish(true)
		return
	_timer = _interval


func _finish(success: bool) -> void:
	set_process(false)
	_teardown_presentation()
	finished.emit(success)
	queue_free()


func _apply_wave() -> void:
	_spawn_wave_ground_fx()
	_play_wave_sfx()
	if _caster == null or not is_instance_valid(_caster):
		return
	var ec := EffectContext.from_cast(_caster, _abil_id, _ctx, null, _center_wc3)
	EffectDamageAoe.run_all_victims(
		ec,
		_center_wc3,
		_radius,
		_damage,
		"spells",
		BUILDING_DAMAGE_FACTOR,
		true
	)


func _play_wave_sfx() -> void:
	var map_root: Node = _ctx.get("map_root")
	if map_root == null:
		return
	var z := 0.0
	var hf: Variant = _ctx.get("heightfield")
	if hf is Wc3Heightfield and (hf as Wc3Heightfield).is_valid():
		z = (hf as Wc3Heightfield).interpolated_height(_center_wc3.x, _center_wc3.y)
	var at := Wc3Coords.wc3_xy_to_godot(_center_wc3.x, _center_wc3.y, z)
	AbilitySfx.play_oneshot(map_root, "BlizzardWave", at)


## 每波多点随机落冰（柱数来自 DataC / shards_per_wave）。
func _spawn_wave_ground_fx() -> void:
	var map_root: Node = _ctx.get("map_root")
	if map_root == null:
		return
	var art := AbilityCastCatalog.ground_effect_art(_abil_id)
	if art.is_empty():
		return
	var cache: MapModelCache = _ctx.get("model_cache") as MapModelCache
	var hf: Variant = _ctx.get("heightfield")
	var hf_typed: Wc3Heightfield = hf as Wc3Heightfield if hf != null else null
	for _i in range(_shards_per_wave):
		var ang := randf() * TAU
		var rad := _radius * WAVE_FX_JITTER_FRAC * sqrt(randf())
		var pos := _center_wc3 + Vector2(cos(ang), sin(ang)) * rad
		AbilityGroundFx.spawn(
			map_root,
			pos,
			art,
			WAVE_FX_LIFETIME,
			cache,
			hf_typed
		)
