extends Area2D

signal collected(resource_id: String, item_id: String, amount: int)

@export var resource_id: String = ""
@export var resource_type_id: String = ""
@export var resource_name: String = "Resource"
@export var collect_amount: int = 1
@export var max_health: int = 30
@export var respawn_time_seconds: float = 60.0

var display_name := "Resource"
var drop_item_id := ""
var drop_amount := 1
var health: int = 30
var collected_state := false
var respawn_time_left := 0.0


func _ready() -> void:
	add_to_group("resource_node")
	health = max_health

	if resource_id.is_empty():
		resource_id = _generate_fallback_resource_id()
		print("ResourceNode missing resource_id. Generated fallback id: %s" % resource_id)

	_load_resource_data()
	health = max_health


func _process(delta: float) -> void:
	if not collected_state:
		return

	if respawn_time_left <= 0.0:
		_respawn()
		return

	respawn_time_left = max(respawn_time_left - delta, 0.0)
	if respawn_time_left == 0.0:
		_respawn()


func _collect() -> void:
	if collected_state:
		return

	print("Collected %d %s" % [drop_amount, drop_item_id])
	set_collected(true, respawn_time_seconds)
	collected.emit(resource_id, drop_item_id, drop_amount)


func take_damage(amount: int) -> void:
	if collected_state:
		return

	if amount <= 0:
		return

	health = max(health - amount, 0)

	if health == 0:
		_collect()


func get_resource_id() -> String:
	return resource_id


func get_resource_name() -> String:
	return resource_name


func get_resource_type_id() -> String:
	return resource_type_id


func get_drop_item_id() -> String:
	return drop_item_id


func is_collected() -> bool:
	return collected_state


func get_respawn_time_left() -> float:
	return respawn_time_left if collected_state else 0.0


func set_collected(is_resource_collected: bool, respawn_time_left_seconds := -1.0) -> void:
	collected_state = is_resource_collected
	respawn_time_left = respawn_time_seconds if collected_state else 0.0
	if collected_state and respawn_time_left_seconds >= 0.0:
		respawn_time_left = respawn_time_left_seconds

	health = 0 if collected_state else max_health
	visible = not collected_state
	monitoring = not collected_state
	monitorable = not collected_state
	_set_collision_shapes_disabled(self, collected_state)


func _respawn() -> void:
	set_collected(false)
	print("Respawned resource: %s" % resource_id)


func _load_resource_data() -> void:
	if resource_type_id.is_empty():
		resource_type_id = _get_fallback_resource_type_id()
		print("ResourceNode %s missing resource_type_id. Using fallback: %s" % [resource_id, resource_type_id])

	drop_item_id = _normalize_item_id(resource_name)
	drop_amount = collect_amount
	display_name = resource_name

	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null:
		return

	var resource_data: Dictionary = content_db.get_resource(resource_type_id)
	if resource_data.is_empty():
		push_error("ResourceNode %s could not load resource_type_id: %s" % [resource_id, resource_type_id])
		return

	display_name = str(resource_data.get("display_name", display_name))
	resource_name = display_name
	max_health = int(resource_data.get("max_health", max_health))
	drop_item_id = str(resource_data.get("drop_item_id", drop_item_id))
	drop_amount = int(resource_data.get("drop_amount", drop_amount))
	respawn_time_seconds = float(resource_data.get("respawn_time_seconds", respawn_time_seconds))


func _get_fallback_resource_type_id() -> String:
	match resource_name:
		"Wood":
			return "tree"
		"Stone":
			return "rock"
		_:
			return resource_name.to_lower()


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


func _generate_fallback_resource_id() -> String:
	return str(get_path()).replace("/", "_").replace(":", "_")


func _set_collision_shapes_disabled(node: Node, is_disabled: bool) -> void:
	for child in node.get_children():
		if child is CollisionShape2D:
			child.disabled = is_disabled

		_set_collision_shapes_disabled(child, is_disabled)
