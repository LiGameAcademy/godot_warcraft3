class_name ResourcePresenter
extends Node

## 库存 VM 推送：订阅 PlayerStock.changed → UiManager.push_resources(vm)。
## 挂在 UiGameplayBridge 子节点；attach(stock) / detach() 由 director 在
## bind_session / shud 上下文中触发。
##
## 设计：docs/design/game/UI_FRAMEWORK.md §5

var _stock: PlayerStock = null
var _on_changed: Callable = Callable()


func _ready() -> void:
	_on_changed = _on_stock_changed


func attach(stock: PlayerStock) -> void:
	detach()
	_stock = stock
	if _stock == null:
		return
	_stock.changed.connect(_on_changed)
	_push_once(_stock)


func detach() -> void:
	if _stock == null:
		return
	if _stock.changed.is_connected(_on_changed):
		_stock.changed.disconnect(_on_changed)
	_stock = null


func _on_stock_changed(stock: PlayerStock) -> void:
	_push_once(stock)


func _push_once(stock: PlayerStock) -> void:
	if stock == null or not is_instance_valid(stock):
		return
	if not is_instance_valid(UiManager):
		return
	UiManager.push_resources({
		"gold": stock.gold,
		"lumber": stock.lumber,
		"food_used": stock.food_used,
		"food_cap": stock.food_cap,
	})