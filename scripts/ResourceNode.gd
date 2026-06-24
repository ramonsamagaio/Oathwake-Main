extends Area2D

signal collected(resource_name: String, amount: int)

@export var resource_name: String = "Resource"
@export var collect_amount: int = 1

var player_in_range := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _unhandled_input(event: InputEvent) -> void:
	if not player_in_range:
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		get_viewport().set_input_as_handled()
		_collect()


func _collect() -> void:
	print("Collected %d %s" % [collect_amount, resource_name])
	collected.emit(resource_name, collect_amount)
	queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_in_range = false
