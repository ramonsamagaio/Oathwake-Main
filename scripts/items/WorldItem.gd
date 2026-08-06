extends Area2D

const SpriteResolverScript := preload("res://scripts/systems/SpriteResolver.gd")

const WORLD_ITEM_TARGET_SIZE := 22.0
const WORLD_ITEM_MAX_SCALE := 0.55
const WORLD_ITEM_MIN_SCALE := 0.12

@export var item_id: String = ""
@export var amount: int = 1
@export var pickup_radius: float = 48.0
@export var magnet_speed: float = 240.0
@export var spawn_magnet_delay: float = 0.3
@export var retry_pickup_delay: float = 0.45
@export var spawn_jump_enabled := true
var metadata: Dictionary = {}

var sprite_resolver := SpriteResolverScript.new()
var player: Node2D
var magnet_active := false
var collected := false
var magnet_delay_left := 0.0
var retry_pickup_left := 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var amount_label: Label = $AmountLabel
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("world_item")
	monitoring = true
	monitorable = true
	magnet_delay_left = spawn_magnet_delay
	if amount_label != null:
		amount_label.visible = false
		amount_label.text = ""
	_apply_visual()
	if spawn_jump_enabled:
		_play_spawn_jump()


func setup(new_item_id: String, new_amount: int, new_metadata: Dictionary = {}) -> void:
	item_id = new_item_id
	amount = max(new_amount, 1)
	metadata = new_metadata.duplicate(true) if not new_metadata.is_empty() else {}
	if is_node_ready():
		_apply_visual()


func is_collected() -> bool:
	return collected


func collect_for_player(target_player: Node2D) -> bool:
	if collected:
		return true
	if target_player == null or not is_instance_valid(target_player):
		return false
	player = target_player
	magnet_delay_left = 0.0
	retry_pickup_left = 0.0
	magnet_active = true
	set_meta("pet_fetch_requested", true)
	if global_position.distance_to(player.global_position) <= 12.0:
		_try_collect()
	return collected


func get_save_data() -> Dictionary:
	var data := {
		"item_id": item_id,
		"amount": amount,
		"position": {
			"x": global_position.x,
			"y": global_position.y,
		},
	}
	if not metadata.is_empty():
		data["metadata"] = metadata.duplicate(true)
	return data


func _process(delta: float) -> void:
	if collected:
		return

	if magnet_delay_left > 0.0:
		magnet_delay_left = max(magnet_delay_left - delta, 0.0)
		return

	if retry_pickup_left > 0.0:
		retry_pickup_left = max(retry_pickup_left - delta, 0.0)
		return

	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D
		if player == null:
			return

	if not magnet_active and global_position.distance_to(player.global_position) <= pickup_radius:
		magnet_active = true

	if magnet_active:
		_update_magnet(delta)


func _update_magnet(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		magnet_active = false
		return

	global_position = global_position.move_toward(player.global_position, magnet_speed * delta)
	if global_position.distance_to(player.global_position) <= 12.0:
		_try_collect()


func _try_collect() -> void:
	var main = get_tree().get_first_node_in_group("main")
	if main == null or not main.has_method("add_item_to_inventory"):
		magnet_active = false
		retry_pickup_left = retry_pickup_delay
		return

	var leftover: int = main.add_item_to_inventory(item_id, amount, metadata)
	if leftover <= 0:
		collected = true
		queue_free()
		return

	amount = leftover
	_apply_visual()
	magnet_active = false
	retry_pickup_left = retry_pickup_delay


func _apply_visual() -> void:
	if sprite == null:
		return

	sprite.texture = sprite_resolver.get_texture_for_item(item_id)
	sprite.centered = true
	sprite.scale = _get_normalized_world_item_scale(sprite.texture)
	if amount_label != null:
		amount_label.visible = false
		amount_label.text = ""


func _get_normalized_world_item_scale(texture: Texture2D) -> Vector2:
	if texture == null:
		return Vector2.ONE * WORLD_ITEM_MAX_SCALE

	var texture_size := texture.get_size()
	var biggest_axis := maxf(texture_size.x, texture_size.y)
	if biggest_axis <= 0.0:
		return Vector2.ONE * WORLD_ITEM_MAX_SCALE

	var scale_value := WORLD_ITEM_TARGET_SIZE / biggest_axis
	scale_value = clampf(scale_value, WORLD_ITEM_MIN_SCALE, WORLD_ITEM_MAX_SCALE)
	return Vector2.ONE * scale_value


func _play_spawn_jump() -> void:
	var horizontal_offset := Vector2(randf_range(-18.0, 18.0), randf_range(-10.0, 10.0))
	var start_position := position
	var peak_position := start_position + horizontal_offset * 0.5 + Vector2(0, -22)
	var end_position := start_position + horizontal_offset
	var tween := create_tween()
	tween.tween_property(self, "position", peak_position, 0.18)
	tween.tween_property(self, "position", end_position, 0.18)
