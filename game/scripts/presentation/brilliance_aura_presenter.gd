class_name BrillianceAuraPresenter
extends RefCounted

## 辉煌光环表现（Present）：薄封装，委托 AbilityAttachFxPresenter + AbilityFxCatalog。

const ABIL_ID := "AHab"
const ATTACH_NODE := "BrillianceAuraAttach"


static func sync_caster(host: Node3D, active: bool, cache: MapModelCache) -> void:
	AbilityAttachFxPresenter.sync_caster_abil(host, ABIL_ID, active, cache, ATTACH_NODE)


static func sync_beneficiaries(
	host: Node3D,
	in_range: Array,
	cache: MapModelCache,
	tracked: Dictionary
) -> void:
	AbilityAttachFxPresenter.sync_buff_beneficiaries_for_abil(host, in_range, ABIL_ID, cache, tracked)


static func clear_beneficiaries(tracked: Dictionary) -> void:
	AbilityAttachFxPresenter.clear_beneficiaries(tracked)
