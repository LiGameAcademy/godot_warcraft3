class_name BlizzardAbility
extends RefCounted

## 暴风雪（Logic · AHbz）：引导型区域多段伤害。

const ABIL_BLIZZARD := "AHbz"


## 即时 try_cast 不再用于暴风雪（走 begin_channel）。
static func try_cast(caster: Node3D, abil_id: String, goal_wc3: Vector2, ctx: Dictionary) -> Dictionary:
	var out := {"ok": false, "reason": "暴风雪需引导施法", "unit": null}
	if abil_id.strip_edges() != ABIL_BLIZZARD:
		out["reason"] = "未实现的技能"
	return out


## 引导开始：生成 BlizzardZone，扣蓝/冷却在引导完整结束后由 Controller 提交。
static func begin_channel(
	caster: Node3D,
	abil_id: String,
	goal_wc3: Vector2,
	ctx: Dictionary
) -> Dictionary:
	var out := {"ok": false, "reason": "", "zone": null}
	if abil_id.strip_edges() != ABIL_BLIZZARD:
		out["reason"] = "未实现的技能"
		return out
	var lv := AbilityCatalog.level_for(caster, abil_id)
	var check := AbilityCastRules.can_cast_point(caster, abil_id, goal_wc3, lv)
	if not bool(check.get("ok", false)):
		return check
	var ab := AbilityCatalog.data(abil_id)
	if ab == null:
		return {"ok": false, "reason": "无技能数据"}
	var pipeline: Variant = ctx.get("damage_pipeline")
	var host_cb: Callable = ctx.get("unit_host", Callable())
	var map_root: Node = ctx.get("map_root")
	if pipeline == null or map_root == null or not host_cb.is_valid():
		return {"ok": false, "reason": "战斗服务未就绪"}
	var unit_host: Node = host_cb.call() as Node
	if unit_host == null:
		return {"ok": false, "reason": "单位层未就绪"}
	var waves := maxi(int(round(ab.data_a_at(lv))), 1)
	var dmg := maxf(ab.data_b_at(lv), 0.0)
	var interval := maxf(ab.data_d_at(lv), 0.05)
	var radius := maxf(ab.area_at(lv), 1.0)
	# DataC：本仓库用作每波落冰柱数（原作建筑系数另用 50% 常量）
	var shards := clampi(int(round(ab.data_c_at(lv))), 2, 6)
	var zone := BlizzardZone.new()
	zone.name = "BlizzardZone"
	map_root.add_child(zone)
	zone.configure(
		caster,
		abil_id,
		goal_wc3,
		radius,
		waves,
		dmg,
		interval,
		pipeline as DamagePipeline,
		unit_host,
		ctx,
		shards
	)
	out["ok"] = true
	out["zone"] = zone
	return out
