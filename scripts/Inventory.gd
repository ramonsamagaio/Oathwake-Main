extends RefCounted

signal changed

var resources := {
	"Wood": 0,
	"Stone": 0,
}


func add_resource(resource_name: String, amount: int) -> void:
	if not resources.has(resource_name):
		resources[resource_name] = 0

	resources[resource_name] += amount
	changed.emit()


func can_spend_resource(resource_name: String, amount: int) -> bool:
	return resources.get(resource_name, 0) >= amount


func spend_resource(resource_name: String, amount: int) -> bool:
	if not can_spend_resource(resource_name, amount):
		return false

	resources[resource_name] -= amount
	changed.emit()
	return true


func get_resource_amount(resource_name: String) -> int:
	return resources.get(resource_name, 0)
