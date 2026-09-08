class_name InnerFireController
extends Node

## 心灵之火 Ainf（Logic）：限时加攻/加甲；Present 由 Catalog 路径驱动。

const ABIL_ID := "Ainf"
const NODE_NAME := "InnerFireController"
const ATTACH_NODE := "InnerFireFxAttach"

var _left: float = 0.0
var _bonus_armor: float = 0.0
var _dmg_mul: float = 1.0
var _cache: MapModelCache = null


static func of(unit: Node3D) -> InnerFireController:
	if unit == null:
		return null
	return unit.get_node_or_null(NODE_NAME) as InnerFireController


static func ensure_on(unit: Node3D) -> InnerFireController:
	if unit == null:
		return null
	var existing := of(unit)
	if existing != null:
		return existing
	var c := InnerFireController.new()
	c.name = NODE_NAME
	unit.add_child(c)
	return c


func is_active() -> bool:
	return _left > 0.0


func activate(level: int, cache: MapModelCache = null) -> bool:
	var host := get_parent() as Node3D
	if host == null or not is_instance_valid(host):
		return false
	var ab := AbilityCatalog.data(ABIL_ID)
	if ab == null:
		return false
	var lv := ab.clamp_level(level)
	_bonus_armor = maxf(ab.data_b_at(lv), 0.0)
	var bonus_pct := maxf(ab.data_a_at(lv), 0.0)
	_dmg_mul = 1.0 + bonus_pct
	_left = maxf(ab.duration_at(lv), 0.1)
	_cache = cache
	BuffHost.ensure_on(host).apply(BuffCatalog.ID_INNER_FIRE, _left, {
		"armor": _bonus_armor,
		"dmg_mul": _dmg_mul,
	})
	_spawn_target_fx(host)
	set_process(true)
	return true


func refresh(level: int, cache: MapModelCache = null) -> bool:
	_deactivate(false)
	return activate(level, cache)


func _process(delta: float) -> void:
	if delta <= 0.0 or _left <= 0.0:
		return
	var host := get_parent() as Node3D
	if host != null and is_instance_valid(host):
		var bh := BuffHost.of(host)
		if bh != null and not bh.has_buff(BuffCatalog.ID_INNER_FIRE):
			_deactivate()
			return
	_left -= delta
	if _left > 0.0:
		return
	_deactivate()


func _deactivate(clear_fx: bool = true) -> void:
	_left = 0.0
	_bonus_armor = 0.0
	_dmg_mul = 1.0
	set_process(false)
	var host := get_parent() as Node3D
	if host != null and is_instance_valid(host):
		var bh := BuffHost.of(host)
		if bh != null:
			bh.remove(BuffCatalog.ID_INNER_FIRE)
	if clear_fx and host != null and is_instance_valid(host):
		AbilityAttachFxPresenter.sync_attach(host, ATTACH_NODE, "", false, _cache)


func _spawn_target_fx(host: Node3D) -> void:
	var art := AbilityFxCatalog.target_art(ABIL_ID)
	if art.is_empty():
		art = AbilityFxCatalog.caster_art(ABIL_ID)
	var attach := AbilityFxCatalog.target_attach(ABIL_ID)
	if attach.is_empty():
		attach = "overhead"
	# overhead：挂实体根（on_entity_root），避免进 MODEL_SCALE≈0.01 子树被二次缩小；
	# scale 0.45 对齐原作相对体型（与辉煌光环 Present 同一挂法）。
	AbilityAttachFxPresenter.sync_attach(
		host,
		ATTACH_NODE,
		art,
		true,
		_cache,
		Vector3(0.0, 0.1, 0.0),
		true,
		attach,
		0.45,
		true
	)


func _exit_tree() -> void:
	if is_active():
		_deactivate()


## 单位死亡时清 Buff + 头顶 FX（DeathService 入口调用）。
static func cleanup_on_death(unit: Node3D) -> void:
	var c := of(unit)
	if c != null:
		c._deactivate()
