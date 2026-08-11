extends "res://scripts/labs/alabaster/AlabasterPlayableSkinRig.gd"
class_name AlabasterDefaultPlayableSkinRig

# DEFAULT is the Oathwake-owned humanoid base from this point forward.
# It intentionally starts as an exact source clone of Male-Dummy so every pivot,
# bone, facing mode, authored z-order and native animation remains proven-good,
# while keeping a distinct runtime/profile id for future body, equipment and
# custom-animation work.
#
# default.png is now a drop-in authored atlas. Until it is committed, this rig
# deliberately falls back to dummy.png, keeping DEFAULT functional at all times.

const DefaultRepoSkinSource := preload("res://scripts/labs/alabaster/AlabasterExternalSkinSource.gd")
const DEFAULT_PROFILE_ID := "default"
const BASE_PROFILE_ID := "male_dummy"
const DEFAULT_FIGURE_LABEL := "Default"
const DEFAULT_ATLAS_PATH := "res://assets/sprites/characters/alabaster/default.png"
const EXPECTED_ATLAS_SIZE := Vector2i(672, 120)
const DEFAULT_CHROMA_RGB := Vector3i(255, 0, 195)
const DEFAULT_PELVIS_DEPTH_MOTIONS := ["", "idle", "walk", "run", "dash"]


func _init() -> void:
	skin_profile_id = DEFAULT_PROFILE_ID
	_skin_figure_source = DEFAULT_FIGURE_LABEL


func configure_skin_profile(profile_id: String) -> void:
	if is_inside_tree():
		push_warning("AlabasterDefaultPlayableSkinRig: configure_skin_profile must be called before add_child().")
		return
	# This class is intentionally locked to DEFAULT. Accepting the explicit id
	# keeps it API-compatible with AlabasterPlayableSkinRig.
	if not profile_id.is_empty() and profile_id != DEFAULT_PROFILE_ID:
		push_warning("AlabasterDefaultPlayableSkinRig ignores non-default profile '%s'." % profile_id)
	skin_profile_id = DEFAULT_PROFILE_ID
	_skin_figure_source = DEFAULT_FIGURE_LABEL


func _load_skin_data() -> void:
	# Deep-copy the proven Dummy source so DEFAULT can receive runtime overlays and
	# tuning without sharing mutable dictionaries with the reference profile.
	var source_figure := DefaultRepoSkinSource.load_skin_figure(BASE_PROFILE_ID)
	_figure = source_figure.duplicate(true) if not source_figure.is_empty() else {}
	if _figure.is_empty():
		push_error("AlabasterDefaultPlayableSkinRig: base figure could not be cloned from %s" % BASE_PROFILE_ID)
		return

	var nodes_value: Variant = _figure.get("nodes", {})
	var anims_value: Variant = _figure.get("anims", {})
	_nodes = (nodes_value as Dictionary).duplicate(true) if nodes_value is Dictionary else {}
	_anims = (anims_value as Dictionary).duplicate(true) if anims_value is Dictionary else {}
	_skin_data_source = "DEFAULT_CLONE_OF_MALE_DUMMY"
	if _nodes.is_empty() or _anims.is_empty():
		push_error("AlabasterDefaultPlayableSkinRig: cloned base is incomplete nodes=%d anims=%d" % [_nodes.size(), _anims.size()])
		return

	_install_weapon_sockets()
	_install_auxiliary_layer_nodes()
	_figure["nodes"] = _nodes
	_figure["anims"] = _anims
	_animation_bank_loaded = true
	_animation_bank_source = "REPO_DEFAULT_BASE_MALE_DUMMY"
	_track_cache.clear()
	_root_dirs.clear()


func _load_skin_atlas() -> void:
	# A real default.png wins automatically. The loader repeats Dummy's exact
	# chroma-key contract so changing only DEFAULT artwork never touches Dummy.
	var authored := _load_authored_default_texture()
	if authored != null:
		_atlas = authored
		_skin_texture_source = "REPO_DEFAULT_PNG"
		return

	_atlas = DefaultRepoSkinSource.load_skin_texture(BASE_PROFILE_ID)
	_skin_texture_source = "DEFAULT_CLONE_OF_DUMMY_PNG" if _atlas != null else ""


func _load_authored_default_texture() -> Texture2D:
	if not FileAccess.file_exists(DEFAULT_ATLAS_PATH) and not ResourceLoader.exists(DEFAULT_ATLAS_PATH):
		return null
	var image: Image = null
	if ResourceLoader.exists(DEFAULT_ATLAS_PATH):
		var resource := load(DEFAULT_ATLAS_PATH)
		if resource is Texture2D:
			image = (resource as Texture2D).get_image()
	if image == null or image.is_empty():
		image = Image.new()
		var load_error := image.load(DEFAULT_ATLAS_PATH)
		if load_error != OK or image.is_empty():
			push_error("AlabasterDefaultPlayableSkinRig: failed to load %s error=%s" % [DEFAULT_ATLAS_PATH, load_error])
			return null
	if image.get_width() != EXPECTED_ATLAS_SIZE.x or image.get_height() != EXPECTED_ATLAS_SIZE.y:
		push_error("AlabasterDefaultPlayableSkinRig: rejected %s size=%dx%d expected=%dx%d" % [
			DEFAULT_ATLAS_PATH,
			image.get_width(), image.get_height(),
			EXPECTED_ATLAS_SIZE.x, EXPECTED_ATLAS_SIZE.y,
		])
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var rgba := image.get_data()
	var keyed_pixels := 0
	var index := 0
	while index + 3 < rgba.size():
		if int(rgba[index]) == DEFAULT_CHROMA_RGB.x and int(rgba[index + 1]) == DEFAULT_CHROMA_RGB.y and int(rgba[index + 2]) == DEFAULT_CHROMA_RGB.z:
			rgba[index + 3] = 0
			keyed_pixels += 1
		index += 4
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, rgba)
	var texture := ImageTexture.create_from_image(image)
	if texture != null:
		print("ALABASTER_DEFAULT_ATLAS_OK path=%s size=%dx%d chroma_pixels=%d" % [
			DEFAULT_ATLAS_PATH, texture.get_width(), texture.get_height(), keyed_pixels,
		])
	return texture


func _apply_profile_front_arm_over_legs() -> void:
	# Keep every shared Dummy-derived correction first, then apply DEFAULT's own
	# clothing-friendly pelvis/thigh contract. This is intentionally DEFAULT-only:
	# Dummy remains an untouched visual reference while our production body can
	# evolve independently.
	super._apply_profile_front_arm_over_legs()
	_apply_default_pelvis_thigh_depth()


func _apply_default_pelvis_thigh_depth() -> void:
	var motion_name := _normalized_motion_name(current_animation)
	if motion_name not in DEFAULT_PELVIS_DEPTH_MOTIONS:
		return

	# The source Dummy has two pelvis graphics on the same `bottom` bone: gfx0 is
	# the visible/front copy while gfx1 is deliberately authored far behind. The
	# previous generic leg correction only ordered L/R chains against each other,
	# so in E/W locomotion a thigh could still rise above the front pelvis copy.
	# Preserve the rear copy and constrain only bottom:gfx0 above both upper legs.
	var thigh_bounds := _visible_z_bounds(["legL", "legR"])
	if not bool(thigh_bounds.get("found", false)):
		return
	var layer_step := 1 if _embedded_world_mode else 16
	var required_pelvis_z := int(thigh_bounds.get("max", 0)) + layer_step

	for record_variant in _sprite_records:
		if not record_variant is Dictionary:
			continue
		var record := record_variant as Dictionary
		if str(record.get("node", "")) != "bottom" or int(record.get("gfx_index", -1)) != 0:
			continue
		var sprite := record.get("sprite") as Sprite2D
		if sprite == null or not sprite.visible:
			continue
		if sprite.z_index < required_pelvis_z:
			sprite.z_index = clampi(required_pelvis_z, -4096, 4096)
			sprite.set_meta("alabaster_default_depth_reason", "pelvis_over_thighs")
			sprite.set_meta("alabaster_default_pelvis_floor", required_pelvis_z)


func get_runtime_summary() -> Dictionary:
	var result := super.get_runtime_summary()
	result["skin_profile_id"] = DEFAULT_PROFILE_ID
	result["figure_source"] = DEFAULT_FIGURE_LABEL
	result["default_base_profile"] = BASE_PROFILE_ID
	result["default_base_json"] = DefaultRepoSkinSource.get_source_path(BASE_PROFILE_ID)
	result["default_base_atlas"] = DefaultRepoSkinSource.get_repo_atlas_path(BASE_PROFILE_ID)
	result["default_authored_atlas"] = DEFAULT_ATLAS_PATH
	result["default_has_independent_runtime_copy"] = true
	result["default_pelvis_depth_policy"] = "bottom:gfx0 above legL/legR during locomotion"
	return result
