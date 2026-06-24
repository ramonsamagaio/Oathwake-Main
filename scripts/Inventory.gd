extends RefCounted

signal changed

var resources := {
	"wood": 0,
	"stone": 0,
	"gel": 0,
}


func add_item(item_id: String, amount: int) -> void:
	if amount <= 0:
		return

	var normalized_id := _normalize_item_id(item_id)
	if not _is_known_item(normalized_id):
		push_error("Inventory cannot add unknown item_id: %s" % item_id)
		return

	if not resources.has(normalized_id):
		resources[normalized_id] = 0

	resources[normalized_id] += amount
	changed.emit()


func remove_item(item_id: String, amount: int) -> bool:
	if amount <= 0:
		return true

	var normalized_id := _normalize_item_id(item_id)
	if not _is_known_item(normalized_id):
		push_error("Inventory cannot remove unknown item_id: %s" % item_id)
		return false

	if not has_item(normalized_id, amount):
		return false

	resources[normalized_id] = get_count(normalized_id) - amount
	changed.emit()
	return true


func get_count(item_id: String) -> int:
	return resources.get(_normalize_item_id(item_id), 0)


func get_all_items() -> Dictionary:
	return resources.duplicate()


func has_item(item_id: String, amount: int) -> bool:
	return get_count(item_id) >= amount


func add_resource(resource_name: String, amount: int) -> void:
	add_item(resource_name, amount)


func can_spend_resource(resource_name: String, amount: int) -> bool:
	return has_item(resource_name, amount)


func spend_resource(resource_name: String, amount: int) -> bool:
	return remove_item(resource_name, amount)


func get_resource_amount(resource_name: String) -> int:
	return get_count(resource_name)


func set_resource_amount(resource_name: String, amount: int) -> void:
	var normalized_id := _normalize_item_id(resource_name)
	if not _is_known_item(normalized_id):
		push_error("Inventory cannot set unknown item_id: %s" % resource_name)
		return

	resources[normalized_id] = max(amount, 0)
	changed.emit()


func set_items(item_data: Dictionary) -> void:
	resources.clear()
	_seed_known_items()

	for item_id in item_data.keys():
		var normalized_id := _normalize_item_id(str(item_id))
		if not _is_known_item(normalized_id):
			push_error("Inventory cannot load unknown item_id: %s" % item_id)
			continue

		resources[normalized_id] = max(int(item_data[item_id]), 0)

	changed.emit()


func _normalize_item_id(item_id: String) -> String:
	match item_id:
		"Wood":
			return "wood"
		"Stone":
			return "stone"
		"Gel":
			return "gel"
		_:
			return item_id.to_lower()


func _is_known_item(item_id: String) -> bool:
	var content_db := _get_content_db()
	if content_db == null:
		return resources.has(item_id)

	return content_db.has_item(item_id)


func _seed_known_items() -> void:
	var content_db := _get_content_db()
	if content_db == null:
		resources = {
			"wood": 0,
			"stone": 0,
			"gel": 0,
		}
		return

	var items = content_db.get("items")
	if not items is Dictionary:
		return

	for item_id in items.keys():
		resources[str(item_id)] = 0


func _get_content_db() -> Node:
	var main_loop := Engine.get_main_loop()
	if not main_loop is SceneTree:
		return null

	return main_loop.root.get_node_or_null("ContentDB")
