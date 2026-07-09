extends Camera2D

@export var default_critical_shake_strength: float = 1.8
@export var default_critical_shake_duration: float = 0.10
@export var shake_decay_curve: float = 1.0

var base_offset := Vector2.ZERO
var shake_strength := 0.0
var shake_time_left := 0.0
var shake_duration := 0.0


func _ready() -> void:
	add_to_group("game_camera")
	base_offset = offset


func request_shake(strength: float = -1.0, duration: float = -1.0) -> void:
	var vfx_profile := _get_vfx_profile()
	var requested_strength := default_critical_shake_strength if strength < 0.0 else strength
	var requested_duration := default_critical_shake_duration if duration < 0.0 else duration
	if strength < 0.0:
		requested_strength = float(vfx_profile.get("critical_shake_strength", requested_strength))
	if duration < 0.0:
		requested_duration = float(vfx_profile.get("critical_shake_duration", requested_duration))
	if requested_strength <= 0.0 or requested_duration <= 0.0:
		return

	shake_strength = max(shake_strength, requested_strength)
	shake_time_left = max(shake_time_left, requested_duration)
	shake_duration = max(shake_duration, requested_duration)


func debug_trigger_critical_shake() -> void:
	request_shake()


func _process(delta: float) -> void:
	if shake_time_left <= 0.0:
		offset = base_offset
		return

	shake_time_left = max(shake_time_left - delta, 0.0)
	var progress := 1.0
	if shake_duration > 0.0:
		progress = clamp(shake_time_left / shake_duration, 0.0, 1.0)
	var eased := pow(progress, max(shake_decay_curve, 0.01))
	var current_strength := shake_strength * eased
	offset = base_offset + Vector2(
		randf_range(-current_strength, current_strength),
		randf_range(-current_strength, current_strength)
	)

	if shake_time_left == 0.0:
		offset = base_offset
		shake_strength = 0.0


func _get_vfx_profile() -> Dictionary:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("has_vfx_profile") and content_db.has_vfx_profile("default"):
		return content_db.get_vfx_profile("default")
	return {}
