class_name BlizzardZone
extends Node

## 暴风雪引导区域（Logic+Present 桥）：引导期间按 DataD 落波；caster 失引导则中止。

signal finished(success: bool)

var _caster: Node3D = null
var _abil_id: String = ""
var _center_wc3 := Vector2.ZERO
var _radius: float = 200.0
var _waves_left: int = 0
var _damage: float = 0.0
var _interval: float = 0.5
var _timer: float = 0.0
var _pipeline: DamagePipeline = null
var _unit_host: Node = null
var _ctx: Dictionary = {}
var _cancelled: bool = false
var _decal: BlizzardAreaDecal = null
var _ground_fx: AbilityGroundFx = null
var _total_waves: int = 0


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
	ctx: Dictionary = {}
) -> void:
	_caster = caster
	_abil_id = abil_id.strip_edges()
	_center_wc3 = center_wc3
	_radius = maxf(radius, 1.0)
	_total_waves = maxi(waves, 1)
	_waves_left = _total_waves
	_damage = maxf(damage_per_wave, 0.0)
	_interval = maxf(interval_sec, 0.05)
	_pipeline = pipeline
	_unit_host = unit_host
	_ctx = ctx.duplicate(true)
	_timer = _interval
	var dur := float(_total_waves) * _interval + 0.5
	_spawn_presentation(dur)
	set_process(true)


func cancel() -> void:
	if _cancelled:
		return
	_cancelled = true
	_waves_left = 0
	set_process(false)
	_teardown_presentation()
	_finish(false)


func _spawn_presentation(duration_sec: float) -> void:
	var map_root: Node = _ctx.get("map_root")
	var hf: Variant = _ctx.get("heightfield")
	var cache: MapModelCache = _ctx.get("model_cache") as MapModelCache
	if map_root == null:
		return
	_decal = BlizzardAreaDecal.spawn(
		map_root, _center_wc3, _radius, duration_sec, hf as Wc3Heightfield
	)
	var art := AbilityCastCatalog.ground_effect_art(_abil_id)
	if not art.is_empty():
		_ground_fx = AbilityGroundFx.spawn(
			map_root,
			_center_wc3,
			art,
			duration_sec,
			cache,
			hf as Wc3Heightfield if hf != null else null
		)


func _teardown_presentation() -> void:
	if _decal != null and is_instance_valid(_decal):
		_decal.queue_free()
		_decal = null
	if _ground_fx != null and is_instance_valid(_ground_fx):
		_ground_fx.queue_free()
		_ground_fx = null


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
	if _waves_left <= 0:
		_finish(true)
		return
	_timer = _interval


func _finish(success: bool) -> void:
	set_process(false)
	finished.emit(success)
	queue_free()


func _apply_wave() -> void:
	if _pipeline == null or _caster == null or not is_instance_valid(_caster):
		return
	if _unit_host == null:
		return
	var cache: MapModelCache = _ctx.get("model_cache") as MapModelCache
	var hit_art := AbilityCastCatalog.hit_effect_art(_abil_id)
	for target in CombatQuery.units_blizzard_victims_in_radius(
		_unit_host, _caster, _center_wc3, _radius
	):
		if not (target is Node3D) or not is_instance_valid(target):
			continue
		var result := _pipeline.apply({
			"attacker": _caster,
			"target": target,
			"atk_type": "magic",
			"dice": 0,
			"sides": 1,
			"dmgplus": _damage,
			"source_kind": "spell",
		})
		if bool(result.get("ok", false)):
			if not hit_art.is_empty():
				SpellHitFx.spawn_on(target as Node3D, hit_art, cache)
