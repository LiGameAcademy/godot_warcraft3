class_name CombatRng
extends RefCounted

## 可注入战斗 RNG（Logic）。测试可塞固定序列。

var _rng := RandomNumberGenerator.new()			## 随机数生成器
var _seq: Array[int] = []						## 序列
var _idx: int = 0								## 索引

## 初始化
func _init() -> void:
	_rng.randomize()

## 清空序列
func clear_sequence() -> void:
	_seq.clear()
	_idx = 0

## 推入序列
func push_sequence(values: Array) -> void:
	_seq.clear()
	_idx = 0
	for v in values:
		_seq.append(int(v))

## 随机数范围
func randi_range(from_v: int, to_v: int) -> int:
	if from_v > to_v:
		var t := from_v
		from_v = to_v
		to_v = t
	if not _seq.is_empty():
		var v := _seq[_idx % _seq.size()]
		_idx += 1
		return clampi(v, from_v, to_v)
	return _rng.randi_range(from_v, to_v)
