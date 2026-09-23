class_name BrillianceAuraPresenter
extends RefCounted

## 辉煌光环表现（Present）。
## - 施法者：AHab Targetart（Brilliance.mdl）— Stand 循环，双环骨骼 scale 外扩
## - 受益者（含自身，仅有蓝单位）：BHab Targetart（GeneralAuraTarget）
## 路径读 AbilityFxCatalog；挂单位实体根，避免进 MODEL_SCALE 子树缩没。

const ABIL_ID := "AHab"
const CASTER_NODE := "BrillianceCasterFx"


static func sync_caster(host: Node3D, active: bool, cache: MapModelCache) -> void:
	# AHab 无 Casterart，权威是 Targetart=Brilliance.mdl
	var art := AbilityFxCatalog.target_art(ABIL_ID) if active else ""
	if active and art.is_empty():
		art = AbilityFxCatalog.caster_art(ABIL_ID)
	var attach := AbilityFxCatalog.target_attach(ABIL_ID)
	if attach.is_empty():
		attach = "origin"
	AbilityAttachFxPresenter.sync_attach(
		host,
		CASTER_NODE,
		art,
		active,
		cache,
		Vector3.ZERO,
		true,
		attach,
		1.0,
		true
	)


static func sync_beneficiaries(
	host: Node3D,
	in_range: Array,
	cache: MapModelCache,
	tracked: Dictionary
) -> void:
	# 含施法者：原作脚下也有 GeneralAuraTarget
	AbilityAttachFxPresenter.sync_buff_beneficiaries_for_abil(
		host, in_range, ABIL_ID, cache, tracked, false, true
	)


static func clear_beneficiaries(tracked: Dictionary) -> void:
	AbilityAttachFxPresenter.clear_beneficiaries(tracked)
