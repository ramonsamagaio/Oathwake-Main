extends "res://scripts/labs/alabaster/AlabasterRigRuntimeProduction.gd"
class_name BonesSystem

# Production facade for the Oathwake bone-driven renderer.
# The low-level Alabaster source renderer stays isolated under /labs; gameplay
# talks to this class so cache lifetime, prewarming and runtime animation
# mutation have one clear owner.

const CORE_GAMEPLAY_ANIMATIONS := [
	"idle",
	"walk",
	"run",
	"dash",
	"guard",
	"damage",
	"dead",
]

var _compiled_animation_count := 0


func _ready() -> void:
	super._ready()
	prewarm_animations(CORE_GAMEPLAY_ANIMATIONS)


func set_animation(animation_name: String) -> void:
	if not _anims.has(animation_name):
		return
	if current_animation == animation_name:
		return
	current_animation = animation_name
	animation_time = 0.0
	# Switching clips must NOT invalidate compiled tracks. The old runtime cleared
	# the entire cache on every idle/attack transition and rebuilt heavy clips on
	# the combat input frame.


func set_rest_pose() -> void:
	# Some source figures do not author a separate "idle" clip. Their idle is the
	# unanimated/rest transform stored directly on each node. Empty animation name
	# intentionally samples no tracks, leaving the authored node transforms intact.
	current_animation = ""
	animation_time = 0.0
	_apply_pose()


func prewarm_animations(animation_names: Array) -> void:
	for raw_name in animation_names:
		var animation_name := str(raw_name).strip_edges()
		if animation_name.is_empty() or animation_name == "__rest__" or not _anims.has(animation_name):
			continue
		var cache_key := "source:" + animation_name
		if _track_cache.has(cache_key):
			continue
		_source_tracks(animation_name)
		_compiled_animation_count += 1


func prewarm_animation(animation_name: String) -> void:
	prewarm_animations([animation_name])


func install_runtime_animation(animation_name: String, animation_data: Dictionary) -> bool:
	var clean_name := animation_name.strip_edges()
	if clean_name.is_empty() or animation_data.is_empty():
		return false
	if not animation_data.has("frameCnt") or not animation_data.has("transforms"):
		push_warning("BonesSystem animation '%s' is missing frameCnt/transforms." % clean_name)
		return false
	_anims[clean_name] = animation_data.duplicate(true)
	_figure["anims"] = _anims
	_track_cache.erase("source:" + clean_name)
	return true


func remove_runtime_animation(animation_name: String) -> bool:
	var clean_name := animation_name.strip_edges()
	if not _anims.has(clean_name):
		return false
	_anims.erase(clean_name)
	_figure["anims"] = _anims
	_track_cache.erase("source:" + clean_name)
	if current_animation == clean_name:
		set_rest_pose()
	return true


func invalidate_animation_bank_cache() -> void:
	_track_cache.clear()
	_compiled_animation_count = 0


func _sample_source_track(track: Array, frame: float, anim_repeat: float) -> Dictionary:
	# Production path uses binary search instead of scanning every key in every
	# bone track on every rendered frame. Interpolation semantics are unchanged.
	if track.is_empty():
		return _identity_pose(false)
	if track.size() == 1:
		return _pose_from_key(track[0])

	var low := 0
	var high := track.size()
	while low < high:
		var middle := (low + high) >> 1
		var key: Dictionary = track[middle]
		if float(key["frame"]) <= frame:
			low = middle + 1
		else:
			high = middle
	var upper_index := low
	if upper_index <= 0:
		return _pose_from_key(track[0])
	if upper_index >= track.size():
		return _pose_from_key(track[track.size() - 1])

	var prev: Dictionary = track[upper_index - 1]
	var next: Dictionary = track[upper_index]
	var local_frame := frame - float(prev["frame"])
	var next_repeat := maxf(float(next.get("frame_repeat", 1.0)), 1.0)
	if next_repeat != 1.0:
		var source_half_frame := 0.5 / maxf(anim_repeat, 1.0)
		local_frame = floor((local_frame + source_half_frame) / next_repeat) * next_repeat
	var frame_delta := maxf(float(next["frame"]) - float(prev["frame"]), 0.000001)
	var weight := clampf(local_frame / frame_delta, 0.0, 1.0)
	weight = _source_spline(weight, String(next.get("spline", "LINEAR")))
	var q0: Quaternion = prev.get("rot", Quaternion.IDENTITY)
	var q1: Quaternion = next.get("rot", Quaternion.IDENTITY)
	var t0: Vector3 = prev.get("trans", Vector3.ZERO)
	var t1: Vector3 = next.get("trans", Vector3.ZERO)
	return {
		"present": true,
		"rot": q0.slerp(q1, weight).normalized(),
		"trans": t0.lerp(t1, weight),
		"scale": lerpf(float(prev.get("scale", 1.0)), float(next.get("scale", 1.0)), weight),
		"rot_toggle": bool(prev.get("rot_toggle", false)),
	}


func get_external_gfx_world(node_name: String, local_gfx_pos: Vector3) -> Vector3:
	# Equipment figures reuse the player's authored attachment bone. Their local
	# gfx offset must then follow the exact same 3D transform/global facing path
	# used by the body renderer before projection.
	if not _states.has(node_name):
		return Vector3.ZERO
	var state: Dictionary = _states[node_name]
	if local_gfx_pos.length_squared() <= 0.00000001:
		return state.get("g_self", Vector3.ZERO)
	var offset := local_gfx_pos
	var scale := float(state.get("scale", 1.0))
	if scale != 1.0:
		offset *= scale
	if bool(state.get("rotated", false)):
		offset = _figure_transform(offset, state.get("dir", Quaternion.IDENTITY))
	return _snap_world(state.get("g_self", Vector3.ZERO) + _globalize(offset))


func resolve_external_billboard_transform(
	node_name: String,
	local_gfx_pos: Vector3,
	billboard: Dictionary,
	row: Dictionary,
	tex_rotate: String,
	tile_idx: int,
	tile_w: int,
	tile_h: int,
	pivot_px: Vector2,
	region: Rect2,
	flip_h: bool = false
) -> Dictionary:
	if not _states.has(node_name):
		return {}
	var state: Dictionary = _states[node_name]
	var gfx_world := get_external_gfx_world(node_name, local_gfx_pos)
	var gfx_screen := _project_world(gfx_world)
	var rot_mode := _rot_mode(tex_rotate)
	var result := {
		"screen_position": gfx_screen,
		"rotation": 0.0,
		"region": region,
		"pivot": pivot_px,
		"scale": Vector2.ONE,
	}
	if rot_mode == ROT_NONE:
		return result
	var source_xfm := _billboard_xfm(
		node_name,
		state,
		gfx_world,
		gfx_screen,
		billboard,
		row,
		rot_mode,
		tile_idx,
		tile_w,
		tile_h,
		pivot_px,
		region
	)
	for key in source_xfm.keys():
		result[key] = source_xfm[key]

	# SourceLive applies this correction for body billboards when the selected
	# directional cell is mirrored. External equipment does not have an active
	# body record, so mirror the same ref-angle correction explicitly here.
	if flip_h:
		var refs_value: Variant = row.get("refAngles", [])
		if refs_value is Array:
			var refs: Array = refs_value
			if tile_idx >= 0 and tile_idx < refs.size() and refs[tile_idx] != null:
				result["rotation"] = float(result.get("rotation", 0.0)) + 2.0 * deg_to_rad(float(refs[tile_idx]))
	return result


func get_animation_cache_summary() -> Dictionary:
	return {
		"cached_tracks": _track_cache.size(),
		"prewarmed_tracks": _compiled_animation_count,
		"current_animation": current_animation,
	}
