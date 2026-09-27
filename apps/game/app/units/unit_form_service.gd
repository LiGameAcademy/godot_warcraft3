class_name UnitFormService
extends Node

## 形态切换事务：保留实体身份、生命比例，更新能力/导航；不操作 HUD。
signal changed(unit: Node3D)
const TOWN_BELL_RADIUS_WC3 := 2800.0
var _units: UnitsModule
var _map: MapLoader
var _navigation: NavigationModule
var _session: GameSession
var _router: CommandRouter
var _presenter: UnitModelPresenter
var _ensure_attack: Callable
var _controllers: Dictionary = {}

func configure(units: UnitsModule, map: MapLoader, navigation: NavigationModule,
		session: GameSession, router: CommandRouter, presenter: UnitModelPresenter, ensure_attack: Callable) -> void:
	_units = units
	_map = map
	_navigation = navigation
	_session = session
	_router = router
	_presenter = presenter
	_ensure_attack = ensure_attack

func shutdown() -> void:
	for ref: WeakRef in _controllers.values():
		var mc := ref.get_ref() as MilitiaController
		if is_instance_valid(mc):
			mc.shutdown()
	_controllers.clear()
	_units = null
	_map = null
	_navigation = null
	_session = null
	_router = null
	_presenter = null
	_ensure_attack = Callable()

func _exit_tree() -> void:
	shutdown()

func _unit_host() -> Node:
	return _map.get_unit_layer() if is_instance_valid(_map) else null

func _stock_for_owner(owner: int) -> PlayerStock:
	return _session.stocks.get(owner) as PlayerStock if _session != null else null

func _find_town_hall(unit: Node3D) -> Node3D:
	if not is_instance_valid(unit) or not is_instance_valid(_units):
		return null
	return _units.find_owned_unit_by_types(CombatQuery.owner_of(unit), PackedStringArray(["htow", "hkee", "hcas"]))

func _forget_controller(id: int) -> void:
	_controllers.erase(id)

func ensure_militia(unit: Node3D) -> MilitiaController:
	if unit == null or not is_instance_valid(unit):
		return null
	if not MilitiaController.unit_has_abil(unit):
		return null
	var existing := MilitiaController.of(unit)
	if existing != null:
		existing.configure(
			Callable(self, "apply_form"),
			Callable(self, "_find_town_hall").bind(unit),
			Callable(self, "_order_move_to_hall")
		)
		_track(existing)
		return existing
	var mc := MilitiaController.new()
	mc.name = MilitiaController.NODE_NAME
	mc.configure(
		Callable(self, "apply_form"),
		Callable(self, "_find_town_hall").bind(unit),
		Callable(self, "_order_move_to_hall")
	)
	unit.add_child(mc)
	_track(mc)
	return mc


func apply_form(unit: Node3D, new_type_id: String) -> bool:
	if unit == null or not is_instance_valid(unit) or new_type_id.is_empty():
		return false
	var d: Dictionary = unit.get_meta("unit_data", {}).duplicate(true)
	var old_tid := str(d.get("typeId", "")).strip_edges()
	if old_tid == new_type_id:
		return true
	var hc := unit.get_node_or_null("HarvestController") as HarvestController
	if hc != null:
		hc.abort()
	var ac := unit.get_node_or_null("AttackController") as AttackController
	if ac != null:
		ac.cancel()
	var uai := UnitAI.of(unit)
	if uai != null:
		uai.yield_to_player()
	var life_ratio := UnitLife.ratio(unit)
	d["typeId"] = new_type_id
	unit.set_meta("unit_data", d)
	if unit.has_meta(UnitLife.META_LIFE):
		unit.remove_meta(UnitLife.META_LIFE)
	if unit.has_meta(UnitLife.META_MAX_LIFE):
		unit.remove_meta(UnitLife.META_MAX_LIFE)
	UnitLife.ensure(unit)
	UnitLife.set_ratio(unit, life_ratio)
	if not _presenter.swap_model(unit, new_type_id, int(d.get("owner", 0)), int(d.get("variation", 0))):
		AppLog.warn(AppLog.Layer.LOGIC, "UnitFormService", "morph 模型失败 %s→%s" % [old_tid, new_type_id])
	var nav := unit.get_node_or_null("UnitNavigator") as UnitNavigator
	if nav != null:
		_navigation.apply_move_stats(unit, nav)
	if CombatQuery.has_weapon(unit):
		if _ensure_attack.is_valid():
			_ensure_attack.call(unit)
		_units.ensure_combat_ai(unit)
	else:
		# 收回农民：卸掉战斗 AI 空转（可选保留 PASSIVE）
		var ai2 := UnitAI.of(unit)
		if ai2 != null:
			ai2.set_profile(UnitAI.Profile.PASSIVE)
	changed.emit(unit)
	return true


func apply_building_upgrade(building: Node3D, new_type_id: String) -> bool:
	if building == null or not is_instance_valid(building) or new_type_id.is_empty():
		return false
	var d: Dictionary = building.get_meta("unit_data", {}).duplicate(true)
	var old_tid := str(d.get("typeId", "")).strip_edges()
	var want := TechPresence.filter_vertical_building_upgrade(old_tid, new_type_id)
	if want.is_empty():
		return false
	var old_food := BuildingCatalog.get_food_made(old_tid)
	var new_food := BuildingCatalog.get_food_made(want)
	var life_ratio := UnitLife.ratio(building)
	d["typeId"] = want
	building.set_meta("unit_data", d)
	if building.has_meta(UnitLife.META_LIFE):
		building.remove_meta(UnitLife.META_LIFE)
	if building.has_meta(UnitLife.META_MAX_LIFE):
		building.remove_meta(UnitLife.META_MAX_LIFE)
	UnitLife.ensure(building)
	UnitLife.set_ratio(building, life_ratio)
	var owner_id := int(d.get("owner", 0))
	var stock := _stock_for_owner(owner_id)
	if stock != null and new_food != old_food:
		stock.add_food_cap(new_food - old_food)
	_presenter.apply_building_phase(building, want)
	## 瞭望塔升守卫塔等：换 typeId 后按新武器挂 HOLD 开火。
	if is_instance_valid(_units):
		_units.ensure_combat_ai(building)
	changed.emit(building)
	return true


func issue_call_to_arms(selected: Array, source: int = UnitOrder.Source.PANEL) -> int:
	var bells: Array[Node3D] = []
	var direct: Array[Node3D] = []
	for n in selected:
		if not (n is Node3D):
			continue
		var unit := n as Node3D
		var tid := CombatQuery.type_id_of(unit)
		if BuildingVisual.is_building(tid) and _building_has_town_bell(tid):
			bells.append(unit)
		elif MilitiaController.unit_has_abil(unit):
			direct.append(unit)
	var n_ok := 0
	if not bells.is_empty():
		n_ok += _issue_town_bell_near_peasants(bells, source)
	for unit in direct:
		if _router != null:
			_router.issue_stop([unit], source)
		var mc := ensure_militia(unit)
		if mc != null and mc.toggle_call_to_arms():
			n_ok += 1
	return n_ok


func _building_has_town_bell(type_id: String) -> bool:
	var cat := CommandButtonCatalog.get_shared()
	for abil_id in cat.get_all_abil_list(type_id):
		if cat.get_ability_order(str(abil_id)) == "townbellon":
			return true
	return false


func _issue_town_bell_near_peasants(bells: Array[Node3D], source: int) -> int:
	var host := _unit_host()
	if host == null:
		return 0
	var n_ok := 0
	var touched: Dictionary = {}
	for bell in bells:
		if bell == null or not is_instance_valid(bell):
			continue
		var bell_owner := int(bell.get_meta("unit_data", {}).get("owner", 0))
		var bell_xy := Wc3Coords.godot_to_wc3_xy(bell.global_position)
		for c in host.get_children():
			if not (c is Node3D):
				continue
			var unit := c as Node3D
			if not is_instance_valid(unit):
				continue
			if int(unit.get_meta("unit_data", {}).get("owner", -1)) != bell_owner:
				continue
			var tid := CombatQuery.type_id_of(unit)
			if tid != "hpea" and tid != "hmil":
				continue
			var uid := unit.get_instance_id()
			if touched.has(uid):
				continue
			var uxy := Wc3Coords.godot_to_wc3_xy(unit.global_position)
			if uxy.distance_to(bell_xy) > TOWN_BELL_RADIUS_WC3:
				continue
			touched[uid] = true
			if _router != null:
				_router.issue_stop([unit], source)
			var mc := ensure_militia(unit)
			if mc != null and mc.toggle_call_to_arms():
				n_ok += 1
	return n_ok


func _order_move_to_hall(unit: Node3D, hall: Node3D) -> void:
	if unit == null or hall == null or _router == null:
		return
	if not is_instance_valid(unit) or not is_instance_valid(hall):
		return
	var goal := Wc3Coords.godot_to_wc3_xy(hall.global_position)
	_router.issue_move_to_wc3([unit], goal, UnitOrder.Source.PANEL)


func _track(mc: MilitiaController) -> void:
	var id := mc.get_instance_id()
	_controllers[id] = weakref(mc)
	var cb := _forget_controller.bind(id)
	if not mc.tree_exiting.is_connected(cb):
		mc.tree_exiting.connect(cb, CONNECT_ONE_SHOT)
