class_name ContentSnapshot
extends RefCounted

var _frozen := false
var snapshot_id: String = "":
	set(value):
		if not _frozen: snapshot_id = value
var schema_version: int = 1:
	set(value):
		if not _frozen: schema_version = value
var content_hash: String = "":
	set(value):
		if not _frozen: content_hash = value
var _package_ids := PackedStringArray()
var package_ids: PackedStringArray:
	get: return _package_ids.duplicate()
	set(value):
		if not _frozen: _package_ids = value.duplicate()
var _diagnostics := PackedStringArray()
var diagnostics: PackedStringArray:
	get: return _diagnostics.duplicate()
	set(value):
		if not _frozen: _diagnostics = value.duplicate()
var frozen: bool:
	get: return _frozen

func freeze() -> void:
	_frozen = true

func describe() -> String:
	return "ContentSnapshot(id=%s hash=%s pkgs=%s frozen=%s)" % [snapshot_id, content_hash, ",".join(package_ids), frozen]
