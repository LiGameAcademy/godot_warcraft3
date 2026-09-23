class_name EntityId
extends RefCounted

## 对局内实体身份（D5）。不等于 Godot instance_id；跨存档前须经注册表映射。
## 第一版：value = creationNumber（正整数）；0 = 无效。

var value: int = 0


func _init(p_value: int = 0) -> void:
	value = p_value


func is_valid() -> bool:
	return value > 0


func equals(other: EntityId) -> bool:
	return other != null and other.value == value


static func invalid() -> EntityId:
	return EntityId.new(0)


static func from_creation_number(cn: int) -> EntityId:
	return EntityId.new(cn) if cn > 0 else invalid()


func _to_string() -> String:
	return "EntityId(%d)" % value
