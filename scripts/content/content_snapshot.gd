class_name ContentSnapshot
extends RefCounted

## 不可变内容快照（D3）。对局期间冻结；换包须重建对局并作废缓存。

var snapshot_id: String = ""
var schema_version: int = 1
var content_hash: String = ""
## 已挂载包 id，顺序即加载优先级（后者覆盖前者）
var package_ids: PackedStringArray = PackedStringArray()
var frozen: bool = false
var diagnostics: PackedStringArray = PackedStringArray()


func freeze() -> void:
	frozen = true


func describe() -> String:
	return "ContentSnapshot(id=%s hash=%s pkgs=%s frozen=%s)" % [
		snapshot_id, content_hash, ",".join(package_ids), str(frozen)
	]
