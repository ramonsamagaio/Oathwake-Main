extends "res://scripts/systems/bones/BonesSystem.gd"
class_name AlabasterJunoBaseRig

const Profile := preload("res://scripts/labs/alabaster/AlabasterJunoBaseProfile.gd")
const CORE_ATLAS_PATH := "res://data/labs/alabaster/juno_base_core_atlas.png"

var _juno_base_core_atlas_active := false


func _ready() -> void:
	# Start from the exact production Juno runtime, skeleton, authored positions and
	# rotation semantics. JunoBase then owns an independent animation dictionary and
	# swaps only the visual atlas for the audit-generated core sheet.
	super._ready()
	_filter_to_core_animation_bank()
	_install_core_atlas_if_available()
	if _anims.has("idle"):
		current_animation = "idle"
		animation_time = 0.0
	_apply_pose()


func _filter_to_core_animation_bank() -> void:
	var filtered := Profile.filter_animation_bank(_anims)
	if filtered.is_empty():
		push_warning("JunoBase: core animation filter returned no clips; preserving Juno bank as safety fallback.")
		return
	_anims = filtered
	_figure["anims"] = _anims
	_track_cache.clear()
	invalidate_animation_bank_cache()
	prewarm_animations(Profile.core_animation_names())


func _install_core_atlas_if_available() -> void:
	if not ResourceLoader.exists(CORE_ATLAS_PATH):
		push_warning("JunoBase: generated core atlas is not imported yet; using full Juno atlas for this session.")
		return
	var texture_value: Variant = load(CORE_ATLAS_PATH)
	if not texture_value is Texture2D:
		push_warning("JunoBase: generated core atlas could not be loaded; using full Juno atlas.")
		return
	_atlas = texture_value as Texture2D
	for record_value in _sprite_records:
		if not record_value is Dictionary:
			continue
		var sprite := (record_value as Dictionary).get("sprite") as Sprite2D
		if sprite != null:
			sprite.texture = _atlas
	_juno_base_core_atlas_active = true


func get_runtime_summary() -> Dictionary:
	var result := super.get_runtime_summary()
	result["profile"] = Profile.PROFILE_ID
	result["profile_label"] = Profile.LABEL
	result["core_animation_count"] = _anims.size()
	result["core_atlas_active"] = _juno_base_core_atlas_active
	result["core_atlas_path"] = CORE_ATLAS_PATH
	return result


func get_juno_base_profile_summary() -> Dictionary:
	return {
		"profile": Profile.PROFILE_ID,
		"label": Profile.LABEL,
		"core_animations": Profile.core_animation_names(),
		"animation_count": _anims.size(),
		"core_atlas_active": _juno_base_core_atlas_active,
		"core_atlas_path": CORE_ATLAS_PATH,
		"bone_count": _nodes.size(),
		"sprite_record_count": _sprite_records.size(),
	}
