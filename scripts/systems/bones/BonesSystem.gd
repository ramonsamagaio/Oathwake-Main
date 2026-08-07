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
	# IMPORTANT: switching clips must NOT invalidate compiled tracks. The old
	# runtime cleared the entire cache on every idle/attack transition, forcing
	# large clips such as atkHammer1fast to be rebuilt during input frames.


func prewarm_animations(animation_names: Array) -> void:
	for raw_name in animation_names:
		var animation_name := str(raw_name).strip_edges()
		if animation_name.is_empty() or not _anims.has(animation_name):
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
		set_animation("idle")
	return true


func invalidate_animation_bank_cache() -> void:
	_track_cache.clear()
	_compiled_animation_count = 0


func get_animation_cache_summary() -> Dictionary:
	return {
		"cached_tracks": _track_cache.size(),
		"prewarmed_tracks": _compiled_animation_count,
		"current_animation": current_animation,
	}
