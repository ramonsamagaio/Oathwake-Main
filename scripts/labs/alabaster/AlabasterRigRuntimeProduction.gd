extends "res://scripts/labs/alabaster/AlabasterRigRuntimeImportable.gd"
class_name AlabasterRigRuntimeProduction

# Final Oathwake correction layer. The source-derived renderer remains intact;
# only camera-dependent CanvasItem depth is resolved here.

const NO_LAYER_OVERRIDE := 999999
const SIDE_DEPTH_EPSILON := 0.015


func _apply_directional_layer_override(record: Dictionary, sprite: Sprite2D) -> void:
	var node_name := String(record.get("node", ""))

	# Juno's floating hair ornament must cover the skull when seen from the
	# NORTH. SOUTH intentionally keeps the source-authored layer, which places
	# the ornament behind the head. Diagonals/profile also stay authored.
	if node_name == "headGear":
		if _angular_distance(facing_degrees, 0.0) <= 11.26:
			_set_logical_layer(sprite, 3)
		return

	# Keep the proven braid/tail ordering from the source correction layer.
	if node_name == "tailEnd":
		var north_distance := _angular_distance(facing_degrees, 0.0)
		if north_distance <= 67.5:
			_set_logical_layer(sprite, 3)
		elif north_distance <= 112.5:
			_set_logical_layer(sprite, 1)
		return

	# Legs: choose front/back from the actual 3D hip anchors after facing has
	# been applied. Larger global Y is closer to the source camera. This fixes
	# W/E and NW/SW without hardcoding anatomical left/right per direction.
	if node_name == "legL" or node_name == "legR":
		var side := "L" if node_name.ends_with("L") else "R"
		var front_state := _side_front_state("hipL", "hipR", side)
		if front_state == 1:
			_offset_logical_layer(sprite, 1)
		elif front_state == -1:
			_offset_logical_layer(sprite, -1)
		return

	# Arms/hands/fingers must move as one visual chain. The rear chain needs to
	# pass behind the torso, not merely behind the other arm. The front chain
	# gets a small positive offset. Shoulder depth is stable while hands swing.
	if node_name in ["armL", "handL", "fingerL", "armR", "handR", "fingerR"]:
		var side := "L" if node_name.ends_with("L") else "R"
		var front_state := _side_front_state("shoulderL", "shoulderR", side)
		if front_state == 1:
			_offset_logical_layer(sprite, 1)
		elif front_state == -1:
			_offset_logical_layer(sprite, -4)
		return


func _side_front_state(left_anchor: String, right_anchor: String, requested_side: String) -> int:
	if not _states.has(left_anchor) or not _states.has(right_anchor):
		return 0
	var left_state: Dictionary = _states[left_anchor]
	var right_state: Dictionary = _states[right_anchor]
	var left_pos: Vector3 = left_state.get("g_self", Vector3.ZERO)
	var right_pos: Vector3 = right_state.get("g_self", Vector3.ZERO)
	var delta := left_pos.y - right_pos.y
	if absf(delta) <= SIDE_DEPTH_EPSILON:
		return 0
	var left_is_front := delta > 0.0
	if requested_side == "L":
		return 1 if left_is_front else -1
	return -1 if left_is_front else 1


func _set_logical_layer(sprite: Sprite2D, logical_layer: int) -> void:
	if _embedded_world_mode:
		sprite.z_as_relative = true
		sprite.z_index = clampi(logical_layer, -32, 32)
	else:
		sprite.z_as_relative = false
		var figure_global_z := int(_figure.get("globalZOrder", 0))
		sprite.z_index = clampi((figure_global_z + logical_layer) * 16, -4096, 4096)
	sprite.set_meta("alabaster_layer_override", logical_layer)


func _offset_logical_layer(sprite: Sprite2D, logical_offset: int) -> void:
	if logical_offset == 0:
		return
	if _embedded_world_mode:
		sprite.z_as_relative = true
		sprite.z_index = clampi(sprite.z_index + logical_offset, -32, 32)
	else:
		sprite.z_as_relative = false
		sprite.z_index = clampi(sprite.z_index + logical_offset * 16, -4096, 4096)
	sprite.set_meta("alabaster_layer_offset", logical_offset)
