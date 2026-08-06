extends Node2D

@export_range(20.0, 300.0, 5.0) var follow_speed := 108.0
@export_range(20.0, 400.0, 5.0) var fetch_speed := 135.0
@export_range(20.0, 600.0, 5.0) var catch_up_speed := 155.0
@export_range(32.0, 500.0, 4.0) var pickup_search_radius := 190.0
@export_range(0.05, 2.0, 0.05) var search_interval := 0.20
@export_range(2.0, 32.0, 1.0) var collect_distance := 10.0
@export_range(20.0, 120.0, 1.0) var hover_radius_min := 30.0
@export_range(20.0, 140.0, 1.0) var hover_radius_max := 52.0
@export_range(10.0, 120.0, 1.0) var trailing_distance := 34.0
@export_range(50.0, 800.0, 5.0) var steering_acceleration := 330.0

var player: Node2D
var pet_data: Dictionary = {}
var target_item: Node2D
var _search_time_left := 0.0
var _flight_phase := 0.0
var _hover_target_time_left := 0.0
var _hover_offset := Vector2(-34.0, -10.0)
var _velocity := Vector2.ZERO
var _rng := RandomNumberGenerator.new()

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var shadow: Polygon2D = $GroundShadow


func _ready() -> void:
	_rng.randomize()
	_choose_hover_offset()


func setup(owner_player: Node2D, item_data: Dictionary = {}) -> void:
	player = owner_player
	pet_data = item_data.duplicate(true)
	pickup_search_radius = float(item_data.get("pet_pickup_radius", pickup_search_radius))
	set_meta("pet_id", str(item_data.get("pet_id", "butterfly_pickup_blue")))
	set_meta("pet_color", str(item_data.get("pet_color", "blue")))
	_configure_sprite_animation()


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		queue_free()
		return

	_flight_phase += delta * 6.2
	_hover_target_time_left = maxf(_hover_target_time_left - delta, 0.0)
	_search_time_left = maxf(_search_time_left - delta, 0.0)
	_update_visual_flight()
	_update_pickup_target()

	if target_item != null and is_instance_valid(target_item):
		_update_fetch(delta)
	else:
		_update_follow(delta)


func _configure_sprite_animation() -> void:
	if sprite == null:
		return
	var texture_path := str(pet_data.get("sprite_path", ""))
	if texture_path.is_empty() or not ResourceLoader.exists(texture_path):
		return
	var texture := ResourceLoader.load(texture_path) as Texture2D
	if texture == null:
		return
	var frame_width := maxi(int(pet_data.get("frame_width", 16)), 1)
	var frame_height := maxi(int(pet_data.get("frame_height", 16)), 1)
	var frame_count := maxi(int(pet_data.get("frames", 5)), 1)
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("fly")
	frames.set_animation_loop("fly", true)
	frames.set_animation_speed("fly", float(pet_data.get("fps", 10.0)))
	for frame_index in range(frame_count):
		var x := frame_index * frame_width
		if x + frame_width > texture.get_width() or frame_height > texture.get_height():
			break
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(x, 0, frame_width, frame_height)
		frames.add_frame("fly", atlas)
	sprite.sprite_frames = frames
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if frames.get_frame_count("fly") > 0:
		sprite.play("fly")


func _update_visual_flight() -> void:
	if sprite != null:
		sprite.position = Vector2(
			sin(_flight_phase * 0.63) * 2.0,
			-18.0 + sin(_flight_phase) * 4.5 + sin(_flight_phase * 0.37) * 1.8
		)
	if shadow != null:
		var pulse := 1.0 + sin(_flight_phase * 0.72) * 0.08
		shadow.scale = Vector2(pulse, 1.0 / pulse)


func _update_pickup_target() -> void:
	if target_item == null or not is_instance_valid(target_item) or _is_item_collected(target_item):
		target_item = null
	if target_item == null and _search_time_left <= 0.0:
		_search_time_left = search_interval
		target_item = _find_nearest_world_item()


func _update_follow(delta: float) -> void:
	var player_velocity := _get_player_velocity()
	var player_is_moving := player_velocity.length() > 6.0
	var desired_position: Vector2
	if player_is_moving:
		var travel_direction := player_velocity.normalized()
		var trailing_side := Vector2(-travel_direction.y, travel_direction.x) * sin(_flight_phase * 0.41) * 18.0
		desired_position = player.global_position - travel_direction * trailing_distance + trailing_side + Vector2(0, -8)
	else:
		if _hover_target_time_left <= 0.0 or global_position.distance_to(player.global_position + _hover_offset) < 8.0:
			_choose_hover_offset()
		desired_position = player.global_position + _hover_offset

	var distance := global_position.distance_to(desired_position)
	var active_speed := catch_up_speed if distance > 170.0 else follow_speed
	_steer_toward(desired_position, active_speed, delta, 0.52)
	z_index = player.z_index + 2


func _update_fetch(delta: float) -> void:
	if target_item.global_position.distance_to(player.global_position) > pickup_search_radius * 1.35:
		target_item = null
		return
	var orbit := Vector2(cos(_flight_phase * 0.77), sin(_flight_phase * 1.09)) * 5.0
	_steer_toward(target_item.global_position + orbit, fetch_speed, delta, 0.34)
	z_index = target_item.z_index + 2
	if global_position.distance_to(target_item.global_position) > collect_distance:
		return
	if target_item.has_method("collect_for_player"):
		target_item.call("collect_for_player", player)
	else:
		target_item.set("player", player)
		target_item.set("magnet_active", true)
	target_item = null
	_search_time_left = search_interval


func _steer_toward(target_position: Vector2, target_speed: float, delta: float, flutter_strength: float) -> void:
	var offset := target_position - global_position
	if offset.length_squared() <= 0.01:
		_velocity = _velocity.move_toward(Vector2.ZERO, steering_acceleration * delta)
		global_position += _velocity * delta
		return
	var direction := offset.normalized()
	var perpendicular := Vector2(-direction.y, direction.x)
	var flutter := perpendicular * sin(_flight_phase * 1.55) * flutter_strength
	var vertical_weave := Vector2(0.0, cos(_flight_phase * 0.91) * 0.22)
	var desired_velocity := (direction + flutter + vertical_weave).normalized() * target_speed
	_velocity = _velocity.move_toward(desired_velocity, steering_acceleration * delta)
	global_position += _velocity * delta


func _choose_hover_offset() -> void:
	var angle := _rng.randf_range(0.0, TAU)
	var radius := _rng.randf_range(hover_radius_min, maxf(hover_radius_max, hover_radius_min))
	_hover_offset = Vector2.RIGHT.rotated(angle) * radius + Vector2(0.0, _rng.randf_range(-18.0, 8.0))
	_hover_target_time_left = _rng.randf_range(0.85, 1.85)


func _get_player_velocity() -> Vector2:
	if player is CharacterBody2D:
		return (player as CharacterBody2D).velocity
	return Vector2.ZERO


func _find_nearest_world_item() -> Node2D:
	var nearest: Node2D
	var nearest_distance := pickup_search_radius
	for candidate in get_tree().get_nodes_in_group("world_item"):
		if not candidate is Node2D:
			continue
		var item := candidate as Node2D
		if _is_item_collected(item):
			continue
		var distance := player.global_position.distance_to(item.global_position)
		if distance > nearest_distance:
			continue
		nearest = item
		nearest_distance = distance
	return nearest


func _is_item_collected(item: Node) -> bool:
	return item.has_method("is_collected") and bool(item.call("is_collected"))


func get_fetch_target() -> Node2D:
	return target_item if target_item != null and is_instance_valid(target_item) else null
