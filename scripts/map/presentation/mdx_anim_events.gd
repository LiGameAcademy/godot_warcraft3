class_name MdxAnimEvents
extends Node
## AnimationPlayer Method Track 目标。MDX EventObject（SND/FPT/SPL/SPN）
## 在 clip 相对秒触发 `fire`；表现层可连接 `event_fired`。无监听则静默。

const NODE_NAME := "MdxEvents"
const META_MDX_NAME := "wc3_mdx_name"
const META_RARITY := "wc3_rarity"
const META_MOVE_SPEED := "wc3_move_speed"
const META_LOOPING := "wc3_seq_looping"

signal event_fired(event_name: String)


func fire(event_name: String) -> void:
	event_fired.emit(event_name)
