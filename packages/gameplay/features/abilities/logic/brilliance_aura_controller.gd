class_name BrillianceAuraController
extends Node

## 辉煌光环 AHab（Logic）：Area 内友军挂 brilliance Buff；回蓝由 UnitRegen 读 Buff。
## Present：施法者 / 受益者附着仍由 BrillianceAuraPresenter 同步。

const ABIL_ID: String = "AHab"
const NODE_NAME: String = "BrillianceAuraController"
## 在范围内每帧续期；离场显式 remove（避免短 duration 导致 HUD 闪烁）。
const AURA_REFRESH_SEC: float = 1.0

var _host: Node3D = null
var _active: bool = false
var _unit_host_cb: Callable = Callable()
var _cache: MapModelCache = null
var _beneficiary_fx: Dictionary = {}
## 本施法者上一帧仍挂着 Buff 的单位（instance_id → Node3D），用于离范围 remove。
var _buffed: Dictionary = {}


static func of(unit: Node3D) -> BrillianceAuraController:
	if unit == null:
		return null
	return unit.get_node_or_null(NODE_NAME) as BrillianceAuraController


static func ensure_on(unit: Node3D) -> BrillianceAuraController:
	if unit == null:
		return null
	var existing: BrillianceAuraController = of(unit)
	if existing != null:
		return existing
	var c: BrillianceAuraController = BrillianceAuraController.new()
	c._host = unit
	c.name = NODE_NAME
	unit.add_child(c)
	return c


static func unit_can_have(unit: Node3D) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	var d: Dictionary = unit.get_meta("unit_data", {})
	var tid: String = str(d.get("typeId", "")).strip_edges()
	for abil_id: String in AbilityCatalog.ability_ids_for_unit(tid):
		if str(abil_id) == ABIL_ID:
			return true
	return false


func configure(unit_host_cb: Callable, cache: MapModelCache = null) -> void:
	_unit_host_cb = unit_host_cb
	_cache = cache
	set_process(true)


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	var host: Node3D = _host
	if host == null or not is_instance_valid(host):
		set_process(false)
		return
	var lv: int = AbilityCatalog.level_for(host, ABIL_ID)
	var ab: AbilityDataDef = AbilityCatalog.data(ABIL_ID)
	if lv <= 0 or ab == null or not unit_can_have(host) or not CombatQuery.is_alive_in_world(host):
		if _active:
			BrillianceAuraPresenter.sync_caster(host, false, _cache)
			BrillianceAuraPresenter.clear_beneficiaries(_beneficiary_fx)
			_clear_all_buffs()
			_active = false
		# 未学习/死亡只进入空闲；学习、洗点或复活后下一帧恢复，不依赖 UI 重挂。
		return
	var rate: float = maxf(ab.data_a_at(lv), 0.0)
	var radius: float = maxf(ab.area_at(lv), 1.0)
	var unit_host: Node = _unit_host_cb.call() as Node if _unit_host_cb.is_valid() else null
	if unit_host == null or rate <= 0.0:
		return
	var center: Vector2 = Wc3Coords.godot_to_wc3_xy(host.global_position)
	var allies: Array = CombatQuery.units_friendly_in_radius(unit_host, host, center, radius)
	# 原作：仅有魔法值的友军享受辉煌（脚兵等无蓝单位不挂 Buff / 受益特效）
	var mana_allies: Array = []
	for n: Node3D in allies:
		if n is Node3D and UnitMana.has_mana(n as Node3D):
			mana_allies.append(n)
	_active = true
	BrillianceAuraPresenter.sync_caster(host, true, _cache)
	BrillianceAuraPresenter.sync_beneficiaries(host, mana_allies, _cache, _beneficiary_fx)
	_sync_buffs(host, mana_allies, rate)


func _sync_buffs(host: Node3D, allies: Array, mana_regen: float) -> void:
	var source_id: int = host.get_instance_id()
	var in_range: Dictionary = {}
	for n: Node3D in allies:
		if not (n is Node3D):
			continue
		var u: Node3D = n as Node3D
		if not is_instance_valid(u):
			continue
		if not UnitMana.has_mana(u):
			continue
		var bh: BuffHost = BuffHost.ensure_on(u)
		bh.apply(BuffCatalog.ID_BRILLIANCE, AURA_REFRESH_SEC, {
			"mana_regen": mana_regen,
			"aura": true,
			"source_id": source_id,
		})
		in_range[u.get_instance_id()] = u
	# 离范围：仅移除本施法者施加的辉煌
	for iid: int in _buffed.keys():
		if in_range.has(iid):
			continue
		var prev: Node3D = _buffed[iid] as Node3D
		if prev != null and is_instance_valid(prev):
			_remove_if_sourced(prev, source_id)
	_buffed = in_range


func _remove_if_sourced(unit: Node3D, source_id: int) -> void:
	var bh: BuffHost = BuffHost.of(unit)
	if bh == null or not bh.has_buff(BuffCatalog.ID_BRILLIANCE):
		return
	var p: Dictionary = bh.get_params(BuffCatalog.ID_BRILLIANCE)
	if int(p.get("source_id", 0)) != source_id:
		return
	bh.remove(BuffCatalog.ID_BRILLIANCE)


func _clear_all_buffs() -> void:
	var host: Node3D = _host
	var source_id: int = host.get_instance_id() if host != null else 0
	for iid: int in _buffed.keys():
		var u: Node3D = _buffed[iid] as Node3D
		if u != null and is_instance_valid(u):
			_remove_if_sourced(u, source_id)
	_buffed.clear()


func _exit_tree() -> void:
	BrillianceAuraPresenter.clear_beneficiaries(_beneficiary_fx)
	_clear_all_buffs()
	var host: Node3D = _host
	if host != null and is_instance_valid(host):
		BrillianceAuraPresenter.sync_caster(host, false, _cache)
