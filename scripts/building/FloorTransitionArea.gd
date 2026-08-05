extends Area2D

@export_category("Floor Transition")
@export var building_id := "building_01"
@export_range(0, 32, 1) var target_floor := 1
@export var player_group := "player"
@export var require_interaction := false
@export var interaction_action := "interact"
@export var destination_marker: NodePath
@export var transition_cooldown := 0.25

var _candidate: Node2D
var _cooldown_until_msec := 0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _unhandled_input(event: InputEvent) -> void:
	if not require_interaction or _candidate == null:
		return
	if event.is_action_pressed(interaction_action):
		_transition(_candidate)
		get_viewport().set_input_as_handled()


func _on_body_entered(body: Node) -> void:
	if not body is Node2D or not body.is_in_group(player_group):
		return
	_candidate = body as Node2D
	if not require_interaction:
		_transition(_candidate)


func _on_body_exited(body: Node) -> void:
	if body == _candidate:
		_candidate = null


func _transition(body: Node2D) -> void:
	if Time.get_ticks_msec() < _cooldown_until_msec:
		return
	_cooldown_until_msec = Time.get_ticks_msec() + int(transition_cooldown * 1000.0)
	if not FloorManager.set_active_floor(building_id, target_floor):
		return

	var marker := get_node_or_null(destination_marker) as Node2D
	if marker != null:
		body.global_position = marker.global_position
