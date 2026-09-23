class_name ConstructionProfile
extends RefCounted

## F2-A 契约：建造语义按种族分四套（人/兽/灵/亡）。
## 数据，不是脚本分叉。BuildController/BuildSite 只读 profile 字段。
## 来源：docs/design/game/BUILD_SYSTEM.md §4.2
##
## 关键字段：
##   profile_id: human / orc / nightelf / undead / naga
##   builder_slot_policy: MANY_VISIBLE / ONE_HIDDEN / NONE_SUMMON
##   progress_model: REPAIR_HP / OCCUPIED_TIMER / SUMMON_TIMER
##   join_via_repair: true 仅人
##   consume_builder_on_complete: true 仅灵（古树）
##   release_builder_on_complete: true 人/兽
##   cancel_refund_ratio: 0.75 WC3 经典

enum SlotPolicy {
	MANY_VISIBLE,    # 人：工人可见，可多
	ONE_HIDDEN,      # 兽/灵：单工人占工地，隐藏
	NONE_SUMMON,     # 亡：召唤中无工人占用
}

enum ProgressModel {
	REPAIR_HP,        # 人：工地作为未完工建筑，基础建造 + Repair 加速
	OCCUPIED_TIMER,   # 兽/灵：单工人绑定 timer
	SUMMON_TIMER,     # 亡：纯 timer
}

## profile_id（human/orc/nightelf/undead/naga）
var profile_id: String = "human"
## 工人占用策略
var builder_slot_policy: int = SlotPolicy.MANY_VISIBLE
## 最大工人数（人 ∞ 软上限；兽灵 1；亡 0）
var max_builders: int = -1  # -1 = 软上限
## 工人是否隐藏（MANY_VISIBLE 时通常 false，ONE_HIDDEN 时 true）
var builder_hidden: bool = false
## 工人是否无敌（隐藏时通常 true）
var builder_invulnerable: bool = false
## 完工是否消耗工人（古树 true；兽/人 false）
var consume_builder_on_complete: bool = false
## 完工是否释放工人（人/兽 true；灵 false；亡 n/a）
var release_builder_on_complete: bool = true
## 进度模型
var progress_model: int = ProgressModel.REPAIR_HP
## 是否支持 join_via_repair（仅人）
var join_via_repair: bool = false
## 取消退款比例
var cancel_refund_ratio: float = 0.75


## 工厂：构造一份 profile（人/兽/灵/亡 各自默认）
static func human() -> ConstructionProfile:
	var p := ConstructionProfile.new()
	p.profile_id = "human"
	p.builder_slot_policy = SlotPolicy.MANY_VISIBLE
	p.max_builders = -1
	p.builder_hidden = false
	p.builder_invulnerable = false
	p.consume_builder_on_complete = false
	p.release_builder_on_complete = true
	p.progress_model = ProgressModel.REPAIR_HP
	p.join_via_repair = true
	p.cancel_refund_ratio = 0.75
	return p


static func orc() -> ConstructionProfile:
	var p := ConstructionProfile.new()
	p.profile_id = "orc"
	p.builder_slot_policy = SlotPolicy.ONE_HIDDEN
	p.max_builders = 1
	p.builder_hidden = true
	p.builder_invulnerable = true
	p.consume_builder_on_complete = false
	p.release_builder_on_complete = true
	p.progress_model = ProgressModel.OCCUPIED_TIMER
	p.join_via_repair = false
	p.cancel_refund_ratio = 0.75
	return p


static func nightelf() -> ConstructionProfile:
	var p := ConstructionProfile.new()
	p.profile_id = "nightelf"
	p.builder_slot_policy = SlotPolicy.ONE_HIDDEN
	p.max_builders = 1
	p.builder_hidden = true
	p.builder_invulnerable = true
	p.consume_builder_on_complete = true  # 古树消耗 wisp
	p.release_builder_on_complete = false
	p.progress_model = ProgressModel.OCCUPIED_TIMER
	p.join_via_repair = false
	p.cancel_refund_ratio = 0.75
	return p


static func undead() -> ConstructionProfile:
	var p := ConstructionProfile.new()
	p.profile_id = "undead"
	p.builder_slot_policy = SlotPolicy.NONE_SUMMON
	p.max_builders = 0
	p.builder_hidden = false
	p.builder_invulnerable = false
	p.consume_builder_on_complete = false
	p.release_builder_on_complete = true
	p.progress_model = ProgressModel.SUMMON_TIMER
	p.join_via_repair = false
	p.cancel_refund_ratio = 0.75
	return p


## 是否支持多工（人）
func supports_multi_builder() -> bool:
	return builder_slot_policy == SlotPolicy.MANY_VISIBLE


## 是否隐藏工人
func hides_builder() -> bool:
	return builder_hidden
