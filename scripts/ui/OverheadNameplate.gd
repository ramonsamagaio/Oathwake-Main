extends Node2D

const OathwakeTextStyle := preload("res://scripts/ui/OathwakeTextStyle.gd")

@export var visibility_distance: float = 128.0
@export var damage_visible_duration: float = 3.0

@onready var name_label: Label = $NameLabel
@onready var health_bar: ProgressBar = $HealthBar

var _damage_visible_timer := 0.0
var _player: Node2D


func _ready() -> void:
	name_label.label_settings = OathwakeTextStyle.make_label_settings_for_profile("monster_name")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	health_bar.min_value = 0.0
	health_bar.max_value = 1.0
	health_bar.value = 1.0
	set_process(true)
	_update_visibility()


func setup(display_name: String, current_health: int, max_health: int) -> void:
	if not is_node_ready():
		await ready

	name_label.text = display_name
	set_health(current_health, max_health)
	_player = _get_player()
	_update_visibility()


func set_health(current_health: int, max_health: int) -> void:
	if not is_node_ready():
		await ready

	var safe_max: int = max(max_health, 1)
	health_bar.max_value = safe_max
	health_bar.value = clamp(current_health, 0, safe_max)
	var health_ratio: float = float(current_health) / float(safe_max)
	health_bar.modulate = Color(1.0, 0.25, 0.25, 1.0) if health_ratio <= 0.3 else Color.WHITE


func show_after_damage() -> void:
	_damage_visible_timer = damage_visible_duration
	_update_visibility()


func _process(delta: float) -> void:
	if _damage_visible_timer > 0.0:
		_damage_visible_timer = max(_damage_visible_timer - delta, 0.0)
	_update_visibility()


func _update_visibility() -> void:
	var should_show := _is_player_near() or _damage_visible_timer > 0.0
	visible = should_show


func _is_player_near() -> bool:
	_player = _get_player()
	if _player == null or not is_instance_valid(_player):
		return false
	return global_position.distance_to(_player.global_position) <= visibility_distance


func _get_player() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("player") as Node2D
