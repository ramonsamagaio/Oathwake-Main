extends Area2D

signal collected(resource_id: String, resource_name: String, amount: int)

@export var resource_id: String = ""
@export var resource_name: String = "Resource"
@export var collect_amount: int = 1

var player_in_range := false
var collected_state := false


func _ready() -> void:
	if resource_id.is_empty():
		resource_id = _generate_fallback_resource_id()
		print("ResourceNode missing resource_id. Generated fallback id: %s" % resource_id)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _unhandled_input(event: InputEvent) -> void:
	if collected_state:
		return

	if not player_in_range:
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		get_viewport().set_input_as_handled()
		_collect()


func _collect() -> void:
	if collected_state:
		return

	print("Collected %d %s" % [collect_amount, resource_name])
	set_collected(true)
	collected.emit(resource_id, resource_name, collect_amount)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false


func get_resource_id() -> String:
	return resource_id


func is_collected() -> bool:
	return collected_state


func set_collected(is_resource_collected: bool) -> void:
	collected_state = is_resource_collected
	player_in_range = false
	visible = not collected_state
	monitoring = not collected_state
	monitorable = not collected_state
	_set_collision_shapes_disabled(self, collected_state)


func _generate_fallback_resource_id() -> String:
	return str(get_path()).replace("/", "_").replace(":", "_")


func _set_collision_shapes_disabled(node: Node, is_disabled: bool) -> void:
	for child in node.get_children():
		if child is CollisionShape2D:
			child.disabled = is_disabled

		_set_collision_shapes_disabled(child, is_disabled)
