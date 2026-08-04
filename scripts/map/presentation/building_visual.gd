class_name BuildingVisual
extends RefCounted
## 建筑模型视觉状态：按 typeId / 建造·升级阶段选 Sequence。
## 人族主城 htow/hkee/hcas 共用 TownHall.mdx，靠 Stand / Stand Upgrade First|Second 切换 geoset。
## 同步 PE2：`Wc3Pe2Particles.apply_sequence`（训练烟、建造尘、死亡爆等）。
## 放在 map/Presentation，编辑器与游戏共用（勿放 game/ 以免 map→game 反向依赖）。

const _Pe2 := preload("res://scripts/map/presentation/effects/wc3_pe2_particles.gd")

enum Phase {
	IDLE = 0,
	BIRTH = 1,
	WORK = 2,
	UPGRADE_BIRTH = 3,
}

## 主城三档 → 动画名后缀（转换器把空格换成 _）。
const TOWN_HALL_TIER := {
	"htow": "",
	"hkee": " Upgrade First",
	"hcas": " Upgrade Second",
}


static func is_building(type_id: String) -> bool:
	if type_id.is_empty() or type_id == "sloc":
		return false
	if TOWN_HALL_TIER.has(type_id):
		return true
	Wc3DefStore.ensure_table(UnitBalanceDef.TABLE_NAME)
	var row: Resource = Wc3DefStore.get_row(UnitBalanceDef.TABLE_NAME, type_id)
	if row is UnitBalanceDef:
		return (row as UnitBalanceDef).isbldg
	return false


static func town_hall_tier_suffix(type_id: String) -> String:
	return str(TOWN_HALL_TIER.get(type_id, ""))


## 逻辑动画名（WC3 Sequence 名，空格版）；播放时再解析 GLB 里的 _ 变体。
static func sequence_name(type_id: String, phase: int) -> String:
	var suffix := town_hall_tier_suffix(type_id)
	match phase:
		Phase.BIRTH, Phase.UPGRADE_BIRTH:
			if suffix.is_empty():
				return "Birth"
			return "Birth" + suffix
		Phase.WORK:
			if suffix.is_empty():
				return "Stand Work"
			return "Stand Work" + suffix
		_:
			if suffix.is_empty():
				return "Stand"
			return "Stand" + suffix


static func apply_phase(cache: MapModelCache, root: Node, type_id: String, phase: int = Phase.IDLE) -> bool:
	if cache == null or root == null:
		return false
	var want := sequence_name(type_id, phase)
	var resolved := resolve_animation(root, want)
	var ok := false
	if resolved.is_empty():
		ok = cache.autoplay_stand(root, false)
		want = "Stand"
	else:
		var loop := phase == Phase.IDLE or phase == Phase.WORK
		ok = cache.play_animation(root, resolved, loop)
	_Pe2.apply_sequence(root, want)
	return ok


static func apply_idle(cache: MapModelCache, root: Node, type_id: String) -> bool:
	return apply_phase(cache, root, type_id, Phase.IDLE)


## 在 AnimationPlayer 中解析「Stand Upgrade First」↔「Stand_Upgrade_First」。
static func resolve_animation(root: Node, logical_name: String) -> String:
	if root == null or logical_name.is_empty():
		return ""
	var ap := _find_animation_player(root)
	if ap == null:
		return ""
	var candidates: Array[String] = [
		logical_name,
		logical_name.replace(" ", "_"),
		logical_name.replace(" ", ""),
	]
	var names := ap.get_animation_list()
	for cand in candidates:
		var cand_l := cand.to_lower()
		for n in names:
			var leaf := _anim_leaf(str(n))
			if leaf == cand or leaf.to_lower() == cand_l:
				return str(n)
	# 无精确 Stand：回退 Stand - 1 / Stand_1（地精商店、酒馆等）
	var want_l := logical_name.to_lower().strip_edges()
	if want_l == "stand":
		for n in names:
			var leaf2 := _anim_leaf(str(n)).to_lower()
			if leaf2 == "stand":
				return str(n)
			if not leaf2.begins_with("stand"):
				continue
			# 排除 Stand Work / Ready / Upgrade / Channel 等业务态
			if (
				leaf2.begins_with("stand_work")
				or leaf2.begins_with("standwork")
				or leaf2.contains("upgrade")
				or leaf2.contains("ready")
				or leaf2.contains("channel")
				or leaf2.contains("hit")
			):
				continue
			return str(n)
	return ""


static func _anim_leaf(anim_path: String) -> String:
	var i := anim_path.rfind("/")
	return anim_path.substr(i + 1) if i >= 0 else anim_path


static func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var found := _find_animation_player(c)
		if found:
			return found
	return null
