extends "res://scripts/labs/alabaster/AlabasterRigRuntimeProduction.gd"
class_name AlabasterRigRuntimeTunable

# Shared non-destructive tuning layer used by Bone Studio and gameplay.
# Custom animations may carry an `oathwake_tuning` dictionary with two scopes:
#   global[bone]      -> additive local bone correction for the whole animation
#   frames[frame][bone] -> additive correction for exactly one source frame
# The source Alabaster animation data itself is never rewritten.

const SharedAnimationBank := preload("res://scripts/labs/alabaster/AlabasterAnimationBank.gd")
const TUNING_KEY := "oathwake_tuning"
const GLOBAL_KEY := "global"
const FRAMES_KEY := "frames"
const HIGHLIGHT_GREEN := Color(0.08, 1.0, 0.22, 1.0)

var selected_sprite_part := ""
var selection_green_intensity := 0.65


# SourceLive historically falls back to juno_player_anims.json.gz.b64 when the
# complete 419-animation catalog is unavailable. That legacy payload is not a
# reliable repository source anymore and was producing a second Base64/GZIP
# failure after the real bank failure. Production, Mechanic Lab and Bone Studio
# all pass through this Tunable runtime, so use the canonical repository gameplay
# chunks instead. If the full bank loaded, this method is a no-op.
func _merge_player_animation_bank() -> void:
	if _animation_bank_loaded:
		return
	var gameplay := SharedAnimationBank.load_gameplay_animation_bank()
	if gameplay.is_empty():
		push_warning("AlabasterRigRuntime: repository gameplay fallback unavailable; keeping runtime subset (%d animations)" % _anims.size())
		return
	var diagnostics := SharedAnimationBank.get_diagnostics()
	_install_animation_catalog(gameplay, "GAMEPLAY_PACK")
	print("ALABASTER_RUNTIME_GAMEPLAY_FALLBACK source=%s animations=%d" % [
		str(diagnostics.get("source", "GAMEPLAY")),
		gameplay.size(),
	])


func _sample_animation_source(animation_name: String) -> Dictionary:
	var sampled := super._sample_animation_source(animation_name)
	_apply_animation_tuning(animation_name, sampled)
	return sampled


func _apply_animation_tuning(animation_name: String, sampled: Dictionary) -> void:
	if animation_name.is_empty() or not _anims.has(animation_name):
		return
	var anim_value: Variant = _anims.get(animation_name, {})
	if not anim_value is Dictionary:
		return
	var tuning_value: Variant = (anim_value as Dictionary).get(TUNING_KEY, {})
	if not tuning_value is Dictionary:
		return
	var tuning := tuning_value as Dictionary

	var global_value: Variant = tuning.get(GLOBAL_KEY, {})
	if global_value is Dictionary:
		_apply_tuning_scope(sampled, global_value as Dictionary)

	var frames_value: Variant = tuning.get(FRAMES_KEY, {})
	if not frames_value is Dictionary:
		return
	var source_frame := roundi(_src_frame)
	var frame_map := frames_value as Dictionary
	var frame_value: Variant = frame_map.get(str(source_frame), frame_map.get(source_frame, {}))
	if frame_value is Dictionary:
		_apply_tuning_scope(sampled, frame_value as Dictionary)


func _apply_tuning_scope(sampled: Dictionary, scope: Dictionary) -> void:
	for bone_value in scope.keys():
		var bone_name := str(bone_value)
		if bone_name.is_empty() or not _nodes.has(bone_name):
			continue
		var delta_value: Variant = scope[bone_value]
		if not delta_value is Dictionary:
			continue
		var delta := delta_value as Dictionary
		var pose_value: Variant = sampled.get(bone_name, _identity_pose(false))
		var pose := (pose_value as Dictionary).duplicate(true) if pose_value is Dictionary else _identity_pose(false)

		var rot_delta := _vec3_from_array(delta.get("rot", [0.0, 0.0, 0.0]))
		var trans_delta := _vec3_from_array(delta.get("trans", [0.0, 0.0, 0.0]))
		var scale_delta := float(delta.get("scale", 1.0))
		var has_rotation := rot_delta.length_squared() > 0.0000000001
		var has_translation := trans_delta.length_squared() > 0.0000000001
		var has_scale := absf(scale_delta - 1.0) > 0.000001
		if not has_rotation and not has_translation and not has_scale:
			continue

		if has_rotation:
			var base_q: Quaternion = pose.get("rot", Quaternion.IDENTITY)
			var delta_q := _source_quat(rot_delta)
			pose["rot"] = (base_q * delta_q).normalized()
		if has_translation:
			var base_t: Vector3 = pose.get("trans", Vector3.ZERO)
			pose["trans"] = base_t + trans_delta
		if has_scale:
			pose["scale"] = float(pose.get("scale", 1.0)) * scale_delta
		pose["present"] = true
		sampled[bone_name] = pose


func get_animation_tuning(animation_name: String) -> Dictionary:
	var anim_value: Variant = _anims.get(animation_name, {})
	if not anim_value is Dictionary:
		return {}
	var tuning_value: Variant = (anim_value as Dictionary).get(TUNING_KEY, {})
	return (tuning_value as Dictionary).duplicate(true) if tuning_value is Dictionary else {}


func set_animation_tuning(animation_name: String, tuning: Dictionary) -> bool:
	if not _anims.has(animation_name):
		return false
	var anim_value: Variant = _anims[animation_name]
	if not anim_value is Dictionary:
		return false
	var anim := (anim_value as Dictionary).duplicate(true)
	anim[TUNING_KEY] = tuning.duplicate(true)
	_anims[animation_name] = anim
	_figure["anims"] = _anims
	if current_animation == animation_name:
		_apply_pose()
	return true


func get_current_tuning_frame() -> int:
	return roundi(_src_frame)


func get_sprite_part_names() -> Array[String]:
	var seen := {}
	for record_value in _sprite_records:
		if not record_value is Dictionary:
			continue
		var record := record_value as Dictionary
		var sprite := record.get("sprite") as Sprite2D
		var node_name := str(record.get("node", ""))
		if sprite != null and not node_name.is_empty():
			seen[node_name] = true
	var names: Array[String] = []
	for node_name_value in seen.keys():
		names.append(str(node_name_value))
	names.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return names


func set_selected_sprite_part(node_name: String) -> void:
	selected_sprite_part = node_name.strip_edges()
	_refresh_sprite_selection_modulation()


func get_selected_sprite_part() -> String:
	return selected_sprite_part


func set_selection_green_intensity(value: float) -> void:
	selection_green_intensity = clampf(value, 0.0, 1.0)
	_refresh_sprite_selection_modulation()


func get_selection_green_intensity() -> float:
	return selection_green_intensity


func set_sprite_opacity(value: float) -> void:
	super.set_sprite_opacity(value)
	_refresh_sprite_selection_modulation()


func _update_sprite_source(record: Dictionary) -> void:
	super._update_sprite_source(record)
	var sprite := record.get("sprite") as Sprite2D
	if sprite != null:
		_apply_sprite_selection_modulation(record, sprite)


func _refresh_sprite_selection_modulation() -> void:
	for record_value in _sprite_records:
		if not record_value is Dictionary:
			continue
		var record := record_value as Dictionary
		var sprite := record.get("sprite") as Sprite2D
		if sprite != null:
			_apply_sprite_selection_modulation(record, sprite)


func _apply_sprite_selection_modulation(record: Dictionary, sprite: Sprite2D) -> void:
	var node_name := str(record.get("node", ""))
	var tint := Color.WHITE
	if not selected_sprite_part.is_empty() and node_name == selected_sprite_part:
		tint = Color.WHITE.lerp(HIGHLIGHT_GREEN, selection_green_intensity)
	tint.a = sprite_opacity
	sprite.self_modulate = tint