class_name GroundItem
extends Node3D

## 地面运行时物品；不加入单位层，不参与单位战斗、人口或寻路占位。
var item: ItemInstance
var claimed: bool = false
