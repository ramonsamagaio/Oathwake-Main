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

# Juno's arm works because every image has a distinct geometric job: gfx0 is the
# shoulder cap, gfx1 spans shoulder -> elbow, hand:gfx0 spans elbow -> wrist and
# finger:gfx0 is the hand. DEFAULT owns taller/longer art and longer Dummy bones,
# so we keep those bone lengths and copy only the attachment semantics that make
# Juno's pieces meet cleanly. Seven source pixels is Juno's connector pivot;
# DEFAULT's connector is 12 px tall, therefore 7 / 12 is the equivalent pivot.
const DEFAULT_ARM_CONNECTOR_PIVOT_Y := 0.5833333333333334

var _default_arm_fit_applied := false


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
	_install_default_arm_fit()
	_figure["nodes"] = _nodes
	_figure["anims"] = _anims
	_animation_bank_loaded = true
	_animation_bank_source = "REPO_DEFAULT_BASE_MALE_DUMMY"
	_track_cache.clear()
	_root_dirs.clear()


func _install_default_arm_fit() -> void:
	# Do not shorten DEFAULT to Juno's skeleton. The previous pass copied Juno's
	# arm/hand node positions and removed 0.1875 world units from the chain. At
	# source scale that is roughly three vertical screen pixels, exactly the short
	# arm visible in Mechanic Lab. Start from Dummy's longer authored bones and
	# modify only the four visual attachment roles below.
	var fitted_sides := 0
	for suffix_value in ["L", "R"]:
		if _fit_default_arm_side(str(suffix_value)):
			fitted_sides += 1
	_default_arm_fit_applied = fitted_sides == 2
	print("ALABASTER_DEFAULT_ARM_FIT sides=%d applied=%s policy=dummy_lengths_juno_attachments" % [
		fitted_sides,
		str(_default_arm_fit_applied),
	])


func _fit_default_arm_side(suffix: String) -> bool:
	var arm_name := "arm" + suffix
	var hand_name := "hand" + suffix
	var finger_name := "finger" + suffix
	if not _nodes.has(arm_name) or not _nodes.has(hand_name) or not _nodes.has(finger_name):
		return false

	var arm_value: Variant = _nodes[arm_name]
	var hand_value: Variant = _nodes[hand_name]
	var finger_value: Variant = _nodes[finger_name]
	if not arm_value is Dictionary or not hand_value is Dictionary or not finger_value is Dictionary:
		return false

	# arm:gfx0 = shoulder cap. Keep its exact DEFAULT/Dummy position, pivot,
	# facing and refAngles. Only establish Juno's internal depth: the cap is one
	# authored layer above the biceps connector, so the connector may tuck behind
	# it without occupying the same physical screen position.
	var arm_node := (arm_value as Dictionary).duplicate(true)
	var arm_gfx_value: Variant = arm_node.get("gfx", [])
	if not arm_gfx_value is Array:
		return false
	var arm_gfx := (arm_gfx_value as Array).duplicate(true)
	if arm_gfx.size() < 2:
		return false

	var shoulder_value: Variant = arm_gfx[0]
	if shoulder_value is Dictionary:
		var shoulder := (shoulder_value as Dictionary).duplicate(true)
		_set_gfx_billboard_value(shoulder, "zOrder", 1)
		arm_gfx[0] = shoulder

	# arm:gfx1 = the 8x12 biceps/upper-arm strip in DEFAULT. Anchor it at the arm
	# node itself, i.e. at the elbow end of the shoulder->arm bone, exactly like
	# Juno's connector. With Dummy's 0.375-long bone this puts the connector one
	# source pixel lower than the previous Juno-length overlay. Its pivot stays at
	# the same physical seven-pixel point Juno uses, converted to a 12-pixel tile.
	var biceps_value: Variant = arm_gfx[1]
	if biceps_value is Dictionary:
		var biceps := (biceps_value as Dictionary).duplicate(true)
		biceps["pos"] = [0.0, 0.0, 0.0]
		_set_gfx_billboard_value(biceps, "pivotX", 0.375)
		_set_gfx_billboard_value(biceps, "pivotY", DEFAULT_ARM_CONNECTOR_PIVOT_Y)
		_set_gfx_billboard_value(biceps, "zOrder", 0)
		_set_gfx_tex_rotate(biceps, "PARENT_ROTATE_CUT")
		arm_gfx[1] = biceps

	arm_node["gfx"] = arm_gfx
	_nodes[arm_name] = arm_node

	# hand:gfx0 is visually the forearm in this atlas. Keep Dummy's longer
	# arm->hand bone (0.4375 instead of Juno's 0.3125) and put the graphic exactly
	# on that wrist node. Relative to the previous overlay the wrist therefore
	# descends by 0.125 world units, roughly two source-screen pixels. Juno's
	# bottom pivot and PARENT_ROTATE_SCALE keep the forearm reaching back toward
	# the elbow rather than piling up at the shoulder.
	var hand_node := (hand_value as Dictionary).duplicate(true)
	var hand_gfx_value: Variant = hand_node.get("gfx", [])
	if hand_gfx_value is Array:
		var hand_gfx := (hand_gfx_value as Array).duplicate(true)
		if not hand_gfx.is_empty() and hand_gfx[0] is Dictionary:
			var forearm := (hand_gfx[0] as Dictionary).duplicate(true)
			forearm["pos"] = [0.0, 0.0, 0.0]
			_set_gfx_billboard_value(forearm, "pivotX", 0.375)
			_set_gfx_billboard_value(forearm, "pivotY", 1.0)
			_set_gfx_billboard_value(forearm, "zOrder", 2)
			_set_gfx_tex_rotate(forearm, "PARENT_ROTATE_SCALE")
			hand_gfx[0] = forearm
		hand_node["gfx"] = hand_gfx
	_nodes[hand_name] = hand_node

	# finger:gfx0 is the visible hand/fist. DEFAULT's finger bone remains intact,
	# so sockets and animation data do not move. Removing the old +0.125 visual
	# counter-offset lets the hand occupy the distal end of that bone instead of
	# collapsing back onto the forearm. Its Juno-equivalent centered pivot gives a
	# stable hand/forearm seam while keeping the authored directional cells.
	var finger_node := (finger_value as Dictionary).duplicate(true)
	var finger_gfx_value: Variant = finger_node.get("gfx", [])
	if finger_gfx_value is Array:
		var finger_gfx := (finger_gfx_value as Array).duplicate(true)
		if not finger_gfx.is_empty() and finger_gfx[0] is Dictionary:
			var hand_sprite := (finger_gfx[0] as Dictionary).duplicate(true)
			hand_sprite["pos"] = [0.0, 0.0, 0.0]
			_set_gfx_billboard_value(hand_sprite, "pivotX", 0.375)
			_set_gfx_billboard_value(hand_sprite, "pivotY", 0.5)
			_set_gfx_billboard_value(hand_sprite, "zOrder", 2)
			_set_gfx_tex_rotate(hand_sprite, "PARENT_ROTATE")
			finger_gfx[0] = hand_sprite
		finger_node["gfx"] = finger_gfx
	_nodes[finger_name] = finger_node
	return true


func _set_gfx_billboard_value(gfx: Dictionary, key: String, value: Variant) -> void:
	var shape_value: Variant = gfx.get("shape", {})
	if not shape_value is Dictionary:
		return
	var shape := (shape_value as Dictionary).duplicate(true)
	var billboard_value: Variant = shape.get("billboard", {})
	if not billboard_value is Dictionary:
		return
	var billboard := (billboard_value as Dictionary).duplicate(true)
	billboard[key] = value
	shape["billboard"] = billboard
	gfx["shape"] = shape


func _set_gfx_tex_rotate(gfx: Dictionary, rotate_mode: String) -> void:
	var tex_value: Variant = gfx.get("tex", {})
	if not tex_value is Dictionary:
		return
	var tex := (tex_value as Dictionary).duplicate(true)
	var multi_value: Variant = tex.get("multi", {})
	if not multi_value is Dictionary:
		return
	var multi := (multi_value as Dictionary).duplicate(true)
	var entries_value: Variant = multi.get("entries", {})
	if not entries_value is Dictionary:
		return
	var entries := (entries_value as Dictionary).duplicate(true)

	for entry_name in entries.keys():
		var entry_value: Variant = entries[entry_name]
		if not entry_value is Dictionary:
			continue
		var entry := (entry_value as Dictionary).duplicate(true)
		var rows_value: Variant = entry.get("rows", [])
		if rows_value is Array:
			var rows := (rows_value as Array).duplicate(true)
			for row_index in range(rows.size()):
				var row_value: Variant = rows[row_index]
				if not row_value is Dictionary:
					continue
				var row := (row_value as Dictionary).duplicate(true)
				row["texRotate"] = rotate_mode
				rows[row_index] = row
			entry["rows"] = rows
		entries[entry_name] = entry

	multi["entries"] = entries
	tex["multi"] = multi
	gfx["tex"] = tex


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
	result["default_arm_fit_applied"] = _default_arm_fit_applied
	result["default_arm_fit_policy"] = "Dummy bone lengths + Juno connector semantics"
	result["default_pelvis_depth_policy"] = "bottom:gfx0 above legL/legR during locomotion"
	return result
