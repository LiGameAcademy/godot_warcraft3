class_name ContentPackRules
extends RefCounted

## 内容包 / DLC 资源解析（与 MPQ 同路径覆盖正交）。
## 权威说明：docs/data/CONTENT_PACKS.md
##
## 层 A（VFS）：extract / overlay 后写覆盖 — 见 mpq-extract MPQ_PRIORITY。
## 层 B（Edition）：UnitUI.fileVerFlags → Name_V1 等版本后缀。

const SETTING_ACTIVE_EDITION := "warcraft3/content/active_edition"

const EDITION_ROC := "roc"
const EDITION_TFT := "tft"

## 经典 UnitUI：非 0 表示存在 expansion 模型（表内多为 2 → TFT _V1）。
## 保留常量便于日后按 bit 展开多 DLC 后缀。
const FILE_VER_HAS_EXPANSION := 1


## 当前内容版本；缺省 / 空 → tft（EI 内战默认最终版）。
static func active_edition() -> String:
	var v := str(ProjectSettings.get_setting(SETTING_ACTIVE_EDITION, EDITION_TFT))
	v = v.strip_edges().to_lower()
	if v.is_empty():
		return EDITION_TFT
	return v


## 是否优先尝试 expansion 模型（_V1 等）。
static func prefer_expansion_model() -> bool:
	return active_edition() != EDITION_ROC


## 逻辑内容包栈（先 → 后；后覆盖前）。未来 DLC 往尾部追加 id。
static func pack_stack() -> PackedStringArray:
	return PackedStringArray([EDITION_ROC, EDITION_TFT])


## Edition → 模型文件名后缀（基模为 ""）。
static func model_version_suffix(edition: String) -> String:
	match edition.strip_edges().to_lower():
		EDITION_ROC, "":
			return ""
		EDITION_TFT:
			return "_V1"
		_:
			# 未知 DLC：约定先试 _V2；正式包应在此表或 manifest 登记。
			return "_V2"


## 按当前 edition + fileVerFlags 给出 stem 候选（先试先用）。
## base_stem：已去扩展名的 UnitUI.file，如 units/human/Priest/Priest。
static func expansion_model_candidates(base_stem: String, file_ver_flags: int) -> PackedStringArray:
	var base := base_stem.strip_edges().replace("\\", "/")
	var out: PackedStringArray = []
	if base.is_empty():
		return out
	if prefer_expansion_model() and file_ver_flags != 0:
		var suf := model_version_suffix(active_edition())
		if not suf.is_empty():
			var expanded := _join_stem_suffix(base, suf)
			if expanded != base:
				out.append(expanded)
	out.append(base)
	return out


static func _join_stem_suffix(base: String, suffix: String) -> String:
	if suffix.is_empty():
		return base
	var dir := base.get_base_dir()
	var leaf := base.get_file()
	if leaf.ends_with(suffix):
		return base
	if dir.is_empty():
		return leaf + suffix
	return "%s/%s%s" % [dir, leaf, suffix]
