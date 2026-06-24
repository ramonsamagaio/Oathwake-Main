extends Node2D

const Inventory = preload("res://scripts/Inventory.gd")

var inventory := Inventory.new()

@onready var resources_root: Node2D = $World/Resources
@onready var wood_label: Label = $UI/WoodLabel
@onready var stone_label: Label = $UI/StoneLabel


func _ready() -> void:
	inventory.changed.connect(_update_resource_labels)
	_connect_resource_nodes()
	_update_resource_labels()


func _connect_resource_nodes() -> void:
	for resource_node in resources_root.get_children():
		if resource_node.has_signal("collected"):
			resource_node.connect("collected", _on_resource_collected)


func _on_resource_collected(resource_name: String, amount: int) -> void:
	add_resource(resource_name, amount)


func add_resource(resource_name: String, amount: int) -> void:
	inventory.add_resource(resource_name, amount)


func can_spend_resource(resource_name: String, amount: int) -> bool:
	return inventory.can_spend_resource(resource_name, amount)


func spend_resource(resource_name: String, amount: int) -> bool:
	return inventory.spend_resource(resource_name, amount)


func _update_resource_labels() -> void:
	wood_label.text = "Wood: %d" % inventory.get_resource_amount("Wood")
	stone_label.text = "Stone: %d" % inventory.get_resource_amount("Stone")
