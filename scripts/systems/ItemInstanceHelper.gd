extends RefCounted


static func create_item_stack(item_id: String, amount: int = 1, metadata: Dictionary = {}) -> Dictionary:
	var slot: Dictionary = {
		"item_id": item_id,
		"amount": amount,
		"metadata": metadata.duplicate(true) if not metadata.is_empty() else {},
	}
	ensure_item_metadata(slot)
	return slot


static func ensure_item_metadata(slot: Dictionary) -> bool:
	if not slot is Dictionary:
		return false
	var item_id := str(slot.get("item_id", ""))
	if item_id.is_empty():
		return false
	if not slot.has("metadata") or not slot["metadata"] is Dictionary:
		slot["metadata"] = {}
	var metadata: Dictionary = slot["metadata"]
	var max_dura := get_max_durability(item_id)
	if max_dura > 0 and not metadata.has("current_durability"):
		metadata["current_durability"] = max_dura
		return true
	return false


static func get_current_durability(slot: Dictionary) -> int:
	if not slot is Dictionary:
		return 0
	var metadata = slot.get("metadata", {})
	if not metadata is Dictionary:
		return 0
	return int(metadata.get("current_durability", 0))


static func get_max_durability(item_id: String) -> int:
	if item_id.is_empty():
		return 0
	var content_db := _get_content_db()
	if content_db == null or not content_db.has_method("has_item") or not content_db.has_item(item_id):
		return 0
	var item_data: Dictionary = content_db.get_item(item_id)
	return int(item_data.get("durability", 0))


static func is_broken(slot: Dictionary) -> bool:
	if not slot is Dictionary:
		return true
	var item_id := str(slot.get("item_id", ""))
	if item_id.is_empty():
		return true
	var max_dura := get_max_durability(item_id)
	if max_dura <= 0:
		return false
	return get_current_durability(slot) <= 0


static func reduce_durability(slot: Dictionary, amount: int = 1) -> void:
	if not slot is Dictionary:
		return
	var metadata = slot.get("metadata", {})
	if not metadata is Dictionary:
		return
	var current := int(metadata.get("current_durability", 0))
	if current <= 0:
		return
	metadata["current_durability"] = max(0, current - amount)


static func _get_content_db() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("ContentDB")
