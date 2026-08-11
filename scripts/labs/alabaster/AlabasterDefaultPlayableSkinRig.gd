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
const DefaultJunoGameplayBank := preload("res://scripts/labs/alabaster/AlabasterJunoGameplayBank.gd")
const DEFAULT_PROFILE_ID := "default"
const BASE_PROFILE_ID := "male_dummy"
const DEFAULT_FIGURE_LABEL := "Default"
const DEFAULT_ATLAS_PATH := "res://assets/sprites/characters/alabaster/default.png"
const EXPECTED_ATLAS_SIZE := Vector2i(672, 120)
const DEFAULT_CHROMA_RGB := Vector3i(255, 0, 195)
const DEFAULT_PELVIS_DEPTH_MOTIONS := ["", "idle", "walk", "run", "dash"]
const DEFAULT_JUNO_ARM_CHAIN_NODES := [
	"shoulderL", "armL", "handL", "fingerL",
	"shoulderR", "armR", "handR", "fingerR",
]
const DEFAULT_JUNO_ARM_GFX_NODES := ["armL", "handL", "fingerL", "armR", "handR", "fingerR"]

var _default_juno_arm_overlay_applied := false


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
	_install_juno_arm_chain_overlay()
	_figure["nodes"] = _nodes
	_figure["anims"] = _anims
	_animation_bank_loaded = true
	_animation_bank_source = "REPO_DEFAULT_BASE_MALE_DUMMY"
	_track_cache.clear()
	_root_dirs.clear()


func _install_juno_arm_chain_overlay() -> void:
	# DEFAULT and Dummy share the same artwork layout, but Dummy's arm attachment
	# mechanics visibly open a gap during rotation. Juno closes the same humanoid
	# chain using different local transforms/pivots. Reuse those proven mechanics
	# while preserving DEFAULT's own atlas regions and wider shoulder anchors.
	_default_juno_arm_overlay_applied = false
	var juno_figure := DefaultJunoGameplayBank.load_runtime_figure()
	var juno_nodes_value: Variant = juno_figure.get("nodes", {})
	if not juno_nodes_value is Dictionary:
		push_warning("AlabasterDefaultPlayableSkinRig: Juno arm overlay unavailable; keeping Dummy arm mechanics.")
		return
	var juno_nodes := juno_nodes_value as Dictionary
	var copied_nodes := 0

	for node_name in DEFAULT_JUNO_ARM_CHAIN_NODES:
		if not _nodes.has(node_name) or not juno_nodes.has(node_name):
			continue
		var target_value: Variant = _nodes[node_name]
		var source_value: Variant = juno_nodes[node_name]
		if not target_value is Dictionary or not source_value is Dictionary:
			continue
		var target_node := (target_value as Dictionary).duplicate(true)
		var source_node := source_value as Dictionary

		# Keep DEFAULT/Dummy shoulder X/Z anchors so the arms still meet the wider
		# torso. Everything below each shoulder uses Juno's proven local chain.
		if node_name.begins_with("shoulder"):
			_copy_node_transform_field(target_node, source_node, "dir")
		else:
			for field_name in ["pos", "dir", "pOff"]:
				_copy_node_transform_field(target_node, source_node, field_name)

		if node_name in DEFAULT_JUNO_ARM_GFX_NODES:
			_copy_juno_gfx_mechanics(target_node, source_node, node_name)

		_nodes[node_name] = target_node
		copied_nodes += 1

	_default_juno_arm_overlay_applied = copied_nodes >= 6
	print("ALABASTER_DEFAULT_JUNO_ARM_OVERLAY copied_nodes=%d applied=%s" % [
		copied_nodes,
		str(_default_juno_arm_overlay_applied),
	])


func _copy_node_transform_field(target_node: Dictionary, source_node: Dictionary, field_name: String) -> void:
	if not source_node.has(field_name):
		return
	var value: Variant = source_node[field_name]
	if value is Array:
		target_node[field_name] = (value as Array).duplicate(true)
	elif value is Dictionary:
		target_node[field_name] = (value as Dictionary).duplicate(true)
	else:
		target_node[field_name] = value


func _copy_juno_gfx_mechanics(target_node: Dictionary, source_node: Dictionary, node_name: String) -> void:
	var target_gfx_value: Variant = target_node.get("gfx", [])
	var source_gfx_value: Variant = source_node.get("gfx", [])
	if not target_gfx_value is Array or not source_gfx_value is Array:
		return
	var target_gfx := (target_gfx_value as Array).duplicate(true)
	var source_gfx := source_gfx_value as Array
	var copy_count := mini(target_gfx.size(), source_gfx.size())

	# Juno has additional authored arm variants/layers that do not exist in the
	# 672x120 DEFAULT atlas. Copy only mechanics for artwork DEFAULT already owns;
	# never import Juno atlas coordinates into DEFAULT.
	for gfx_index in range(copy_count):
		var target_record_value: Variant = target_gfx[gfx_index]
		var source_record_value: Variant = source_gfx[gfx_index]
		if not target_record_value is Dictionary or not source_record_value is Dictionary:
			continue
		var target_record := (target_record_value as Dictionary).duplicate(true)
		var source_record := source_record_value as Dictionary
		var target_tile_size := _gfx_default_tile_size(target_record)
		var source_tile_size := _gfx_default_tile_size(source_record)

		if source_record.has("pos"):
			var source_pos: Variant = source_record["pos"]
			target_record["pos"] = (source_pos as Array).duplicate(true) if source_pos is Array else source_pos

		# Shape owns the billboard pivot/cut/parenting behavior. Copy Juno's shape,
		# then convert normalized pivots through pixel space because DEFAULT's
		# forearm is 8x12 while Juno's joint segment is 8x8.
		if source_record.get("shape", null) is Dictionary:
			var source_shape := (source_record["shape"] as Dictionary).duplicate(true)
			_adapt_shape_pivot_to_target_tile(source_shape, source_tile_size, target_tile_size)
			target_record["shape"] = source_shape

		target_gfx[gfx_index] = target_record

	# The second arm graphic is the existing DEFAULT/Dummy forearm/joint artwork.
	# Juno parents this segment's cut rotation to the arm, which keeps the pieces
	# overlapped during motion instead of letting a shoulder/elbow gap open.
	if (node_name == "armL" or node_name == "armR") and target_gfx.size() > 1:
		var joint_value: Variant = target_gfx[1]
		if joint_value is Dictionary:
			var joint := (joint_value as Dictionary).duplicate(true)
			_set_gfx_tex_rotate(joint, "PARENT_ROTATE_CUT")
			target_gfx[1] = joint

	target_node["gfx"] = target_gfx


func _gfx_default_tile_size(gfx: Dictionary) -> Vector2:
	var tex_value: Variant = gfx.get("tex", {})
	if not tex_value is Dictionary:
		return Vector2.ZERO
	var multi_value: Variant = (tex_value as Dictionary).get("multi", {})
	if not multi_value is Dictionary:
		return Vector2.ZERO
	var entries_value: Variant = (multi_value as Dictionary).get("entries", {})
	if not entries_value is Dictionary:
		return Vector2.ZERO
	var entries := entries_value as Dictionary
	var entry_value: Variant = entries.get("default", {})
	if not entry_value is Dictionary:
		return Vector2.ZERO
	var range_value: Variant = (entry_value as Dictionary).get("range", [])
	if not range_value is Array or (range_value as Array).size() < 4:
		return Vector2.ZERO
	var range_data := range_value as Array
	return Vector2(float(range_data[2]), float(range_data[3]))


func _adapt_shape_pivot_to_target_tile(shape: Dictionary, source_size: Vector2, target_size: Vector2) -> void:
	if source_size.x <= 0.0 or source_size.y <= 0.0 or target_size.x <= 0.0 or target_size.y <= 0.0:
		return
	var billboard_value: Variant = shape.get("billboard", {})
	if not billboard_value is Dictionary:
		return
	var billboard := (billboard_value as Dictionary).duplicate(true)
	if billboard.has("pivotX"):
		var pivot_px_x := float(billboard.get("pivotX", 0.5)) * source_size.x
		billboard["pivotX"] = pivot_px_x / target_size.x
	if billboard.has("pivotY"):
		var pivot_px_y := float(billboard.get("pivotY", 0.5)) * source_size.y
		billboard["pivotY"] = pivot_px_y / target_size.y
	shape["billboard"] = billboard


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
	result["default_juno_arm_overlay"] = _default_juno_arm_overlay_applied
	result["default_arm_joint_policy"] = "Juno local arm-chain mechanics over DEFAULT atlas"
	result["default_pelvis_depth_policy"] = "bottom:gfx0 above legL/legR during locomotion"
	return result
