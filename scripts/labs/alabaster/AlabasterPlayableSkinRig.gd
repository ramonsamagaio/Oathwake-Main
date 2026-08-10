extends "res://scripts/systems/bones/BonesSystem.gd"
class_name AlabasterPlayableSkinRig

const RepoSkinSource := preload("res://scripts/labs/alabaster/AlabasterExternalSkinSource.gd")
const HumanoidRetarget := preload("res://scripts/labs/alabaster/AlabasterHumanoidAnimationRetarget.gd")
const JunoGameplayBank := preload("res://scripts/labs/alabaster/AlabasterJunoGameplayBank.gd")

const BODY_DEPTH_MOTION_NAMES := ["", "idle", "walk", "run", "dash"]
const AUXILIARY_LAYER_NODE_NAMES := ["headGear", "tail", "tailEnd"]
const DEPTH_SCORE_EPSILON := 0.01

var skin_profile_id := "male_dummy"
var _skin_figure_source := "Male-Dummy"
var _skin_ready := false
var _skin_initialized := false
var _skin_initializing := false
var _skin_data_source := ""
var _skin_texture_source := ""
var _retarget_summary: Dictionary = {}


func configure_skin_profile(profile_id: String) -> void:
	if is_inside_tree():
		push_warning("AlabasterPlayableSkinRig: configure_skin_profile must be called before add_child().")
		return
	skin_profile_id = "male_temp" if profile_id == "male_temp" else "male_dummy"
	_skin_figure_source = "Male-Temp-01" if skin_profile_id == "male_temp" else "Male-Dummy"


func _ready() -> void:
	initialize_skin()


func initialize_skin() -> bool:
	if _skin_ready:
		return true
	if _skin_initializing:
		return false

	_skin_initializing = true
	_skin_initialized = false
	_skin_ready = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_reset_partial_skin_runtime()

	print("ALABASTER_SKIN_INIT_BEGIN profile=%s figure=%s inside_tree=%s" % [
		skin_profile_id,
		_skin_figure_source,
		str(is_inside_tree()),
	])

	_load_skin_data()
	if _figure.is_empty() or _nodes.is_empty():
		push_error("AlabasterPlayableSkinRig: repository figure/nodes are empty for %s" % skin_profile_id)
		_skin_initializing = false
		return false

	# This is the canonical shared animation installation point for Dummy/Male.
	# Gameplay, Mechanic Lab and Bone Studio all instantiate this same rig class,
	# therefore every correction made here is automatically shared everywhere.
	_retarget_summary = HumanoidRetarget.install_juno_gameplay(self, skin_profile_id)

	print("ALABASTER_SKIN_INIT_FIGURE profile=%s source=%s path=%s nodes=%d anims=%d" % [
		skin_profile_id,
		_skin_data_source,
		RepoSkinSource.get_source_path(skin_profile_id),
		_nodes.size(),
		_anims.size(),
	])

	_load_skin_atlas()
	if _atlas == null:
		push_error("AlabasterPlayableSkinRig: repository atlas is missing/invalid for %s path=%s" % [
			skin_profile_id,
			RepoSkinSource.get_repo_atlas_path(skin_profile_id),
		])
		_skin_initializing = false
		return false

	print("ALABASTER_SKIN_INIT_ATLAS profile=%s source=%s path=%s size=%dx%d" % [
		skin_profile_id,
		_skin_texture_source,
		RepoSkinSource.get_repo_atlas_path(skin_profile_id),
		_atlas.get_width(),
		_atlas.get_height(),
	])

	_build_sprite_records()
	print("ALABASTER_SKIN_INIT_SPRITES profile=%s pieces=%d" % [skin_profile_id, _sprite_records.size()])
	if _sprite_records.is_empty():
		push_error("AlabasterPlayableSkinRig: no sprite records built for %s" % skin_profile_id)
		_skin_initializing = false
		return false

	# Juno idle is now part of the same shared bank as walk/run/combat. If that
	# bank is unavailable for any reason, fall back to the authored rest pose.
	if _anims.has("idle"):
		current_animation = "idle"
	else:
		current_animation = ""
	animation_time = 0.0
	_apply_pose()
	prewarm_animations(_shared_prewarm_animations())

	var visible_pieces := _count_visible_pieces()
	_skin_ready = visible_pieces > 0
	_skin_initialized = _skin_ready
	_skin_initializing = false
	set_process(_skin_ready)

	print("ALABASTER_SKIN_READY profile=%s figure=%s data_source=%s texture_source=%s atlas=%dx%d nodes=%d pieces=%d visible=%d anims=%d ready=%s" % [
		skin_profile_id,
		_skin_figure_source,
		_skin_data_source,
		_skin_texture_source,
		_atlas.get_width(), _atlas.get_height(),
		_nodes.size(),
		_sprite_records.size(),
		visible_pieces,
		_anims.size(),
		str(_skin_ready),
	])
	if not _skin_ready:
		push_error("AlabasterPlayableSkinRig: %s built no visible sprite pieces" % _skin_figure_source)
	return _skin_ready


func is_skin_ready() -> bool:
	return _skin_ready and _skin_initialized and _atlas != null and not _figure.is_empty() and not _sprite_records.is_empty()


func _reset_partial_skin_runtime() -> void:
	for record_variant in _sprite_records:
		if not record_variant is Dictionary:
			continue
		var record := record_variant as Dictionary
		var sprite := record.get("sprite") as Sprite2D
		if sprite != null and is_instance_valid(sprite):
			sprite.queue_free()
	_sprite_records.clear()
	_figure = {}
	_nodes = {}
	_anims = {}
	_atlas = null
	_track_cache.clear()
	_root_dirs.clear()
	_states.clear()
	current_animation = ""
	animation_time = 0.0
	_skin_data_source = ""
	_skin_texture_source = ""
	_retarget_summary = {}


func _count_visible_pieces() -> int:
	var visible_pieces := 0
	for record_variant in _sprite_records:
		if not record_variant is Dictionary:
			continue
		var record := record_variant as Dictionary
		var sprite := record.get("sprite") as Sprite2D
		if sprite != null and sprite.visible:
			visible_pieces += 1
	return visible_pieces


func _load_skin_data() -> void:
	_figure = RepoSkinSource.load_skin_figure(skin_profile_id)
	if _figure.is_empty():
		push_error("AlabasterPlayableSkinRig: canonical repository JSON could not be loaded profile=%s path=%s" % [
			skin_profile_id,
			RepoSkinSource.get_source_path(skin_profile_id),
		])
		return

	var nodes_value: Variant = _figure.get("nodes", {})
	var anims_value: Variant = _figure.get("anims", {})
	_nodes = nodes_value as Dictionary if nodes_value is Dictionary else {}
	_anims = anims_value as Dictionary if anims_value is Dictionary else {}
	_skin_data_source = "REPO_SOURCE_JSON"
	if _nodes.is_empty() or _anims.is_empty():
		push_error("AlabasterPlayableSkinRig: canonical figure is incomplete profile=%s nodes=%d anims=%d" % [
			skin_profile_id, _nodes.size(), _anims.size(),
		])
		return

	_install_weapon_sockets()
	_install_auxiliary_layer_nodes()
	_figure["nodes"] = _nodes
	_figure["anims"] = _anims
	_animation_bank_loaded = true
	_animation_bank_source = "REPO_%s" % _skin_figure_source.to_upper().replace("-", "_")
	_track_cache.clear()
	_root_dirs.clear()


func _load_skin_atlas() -> void:
	_atlas = RepoSkinSource.load_skin_texture(skin_profile_id)
	_skin_texture_source = "REPO_SOURCE_PNG" if _atlas != null else ""


func _shared_prewarm_animations() -> Array:
	var desired := [
		"idle", "walk", "run", "dash", "guard", "damage", "dead", "atkSwordN1",
		HumanoidRetarget.get_native_name("walk"),
		HumanoidRetarget.get_native_name("run"),
		HumanoidRetarget.get_native_name("punch"),
	]
	var available := []
	for animation_name_variant in desired:
		var animation_name := str(animation_name_variant)
		if _anims.has(animation_name):
			available.append(animation_name)
	return available


func _install_weapon_sockets() -> void:
	# Use Juno's authored socket definitions whenever they are available. This is
	# what makes Juno weapon animations transferable instead of animating guessed
	# hand offsets. The socket has no body graphics of its own on Dummy/Male.
	var authored_sockets := JunoGameplayBank.load_socket_nodes()
	for socket_name in ["weaponR", "weaponL", "weaponBelt"]:
		if _nodes.has(socket_name):
			continue
		var socket_value: Variant = authored_sockets.get(socket_name, {})
		if socket_value is Dictionary and not (socket_value as Dictionary).is_empty():
			var socket := (socket_value as Dictionary).duplicate(true)
			socket["gfx"] = []
			socket["colls"] = []
			_nodes[socket_name] = socket
			continue
		_nodes[socket_name] = _fallback_socket(socket_name)


func _install_auxiliary_layer_nodes() -> void:
	# Dummy/Male keep two currently-empty attachment strata matching Juno's rig:
	# headGear is the future head/halo layer; tail -> tailEnd is the future back
	# layer for capes/wings. They intentionally build no sprites yet.
	var juno_figure := JunoGameplayBank.load_runtime_figure()
	var juno_nodes_value: Variant = juno_figure.get("nodes", {})
	var juno_nodes := juno_nodes_value as Dictionary if juno_nodes_value is Dictionary else {}
	for node_name in AUXILIARY_LAYER_NODE_NAMES:
		if _nodes.has(node_name):
			continue
		var source_value: Variant = juno_nodes.get(node_name, {})
		var node: Dictionary
		if source_value is Dictionary and not (source_value as Dictionary).is_empty():
			node = (source_value as Dictionary).duplicate(true)
		else:
			node = _fallback_auxiliary_layer_node(node_name)
		node["gfx"] = []
		node["colls"] = []
		node["hidden"] = false
		_nodes[node_name] = node


func _fallback_auxiliary_layer_node(node_name: String) -> Dictionary:
	match node_name:
		"headGear":
			return {
				"parent": "head", "pos": [0.0, 0.0, 0.0],
				"colls": [], "gfx": [], "frameAnims": {}, "frameKeys": [],
			}
		"tailEnd":
			return {
				"parent": "tail", "pos": [0.0, 0.0, 0.0],
				"colls": [], "gfx": [], "frameAnims": {}, "frameKeys": [],
			}
		_:
			return {
				"parent": "head", "pos": [0.0, 0.0, 0.0],
				"colls": [], "gfx": [], "frameAnims": {}, "frameKeys": [],
			}


func _fallback_socket(socket_name: String) -> Dictionary:
	match socket_name:
		"weaponL":
			return {
				"parent": "handL", "part": "PART_6", "pOff": [0.0, 0.5, 0.0],
				"colls": [], "gfx": [], "frameAnims": {}, "frameKeys": ["down", "swoosh", "swooshDown"],
			}
		"weaponBelt":
			return {
				"parent": "bottom", "part": "PART_7", "pOff": [0.0, -0.25, -0.25],
				"colls": [], "gfx": [], "frameAnims": {}, "frameKeys": [],
			}
		_:
			return {
				"parent": "handR", "part": "PART_7", "pOff": [0.0, 0.5, 0.0],
				"colls": [], "gfx": [], "frameAnims": {}, "frameKeys": ["down", "swoosh", "swooshDown"],
			}


func _apply_directional_layer_override(_record: Dictionary, _sprite: Sprite2D) -> void:
	# Dummy/Male use the whole-chain humanoid policy below. Keeping the per-piece
	# Juno override disabled avoids mixing two depth systems on the same profile.
	pass


func _apply_profile_front_arm_over_legs() -> void:
	# Production invokes this only after every sprite has its authored z value.
	# Resolve complete leg chains every frame, preserve the proven arm/torso rule
	# for neutral locomotion, then make the skull a hard ceiling over bare hands.
	_apply_humanoid_leg_chain_depth()
	var motion_name := _normalized_motion_name(current_animation)
	if motion_name in BODY_DEPTH_MOTION_NAMES:
		_apply_humanoid_arm_torso_depth()
	_apply_humanoid_head_ceiling()
	_apply_auxiliary_layer_depth()


func _normalized_motion_name(animation_name: String) -> String:
	if animation_name.begins_with(HumanoidRetarget.NATIVE_PREFIX):
		return animation_name.trim_prefix(HumanoidRetarget.NATIVE_PREFIX)
	for base_name in ["idle", "walk", "run"]:
		if animation_name == HumanoidRetarget.get_retarget_name(base_name):
			return base_name
	return animation_name


func _apply_humanoid_leg_chain_depth() -> void:
	var left_front := _resolve_leg_front_state()
	if left_front == 0:
		return
	var front_suffix := "L" if left_front == 1 else "R"
	var back_suffix := "R" if front_suffix == "L" else "L"
	var front_nodes := ["leg" + front_suffix, "foot" + front_suffix, "toe" + front_suffix]
	var back_nodes := ["leg" + back_suffix, "foot" + back_suffix, "toe" + back_suffix]
	var layer_step := 1 if _embedded_world_mode else 16
	_shift_visible_nodes(front_nodes, layer_step, "front_leg_chain")
	_shift_visible_nodes(back_nodes, -layer_step, "rear_leg_chain")


func _resolve_leg_front_state() -> int:
	# Profile/diagonal views can use the stable hip anchors. Exact north/south
	# views collapse both hips to the same depth, so use the animated leg chain.
	var hip_state := _side_front_state("hipL", "hipR", "L")
	if hip_state != 0:
		return hip_state
	var left_depth := _chain_camera_depth(["legL", "footL", "toeL"])
	var right_depth := _chain_camera_depth(["legR", "footR", "toeR"])
	if is_nan(left_depth) or is_nan(right_depth):
		return 0
	var delta := left_depth - right_depth
	if absf(delta) <= DEPTH_SCORE_EPSILON:
		return 0
	return 1 if delta > 0.0 else -1


func _chain_camera_depth(node_names: Array) -> float:
	var total := 0.0
	var count := 0
	for node_name_value in node_names:
		var node_name := str(node_name_value)
		if not _states.has(node_name):
			continue
		var state_value: Variant = _states[node_name]
		if not state_value is Dictionary:
			continue
		var world: Vector3 = (state_value as Dictionary).get("g_self", Vector3.ZERO)
		total += _camera_depth_score(world)
		count += 1
	if count == 0:
		return NAN
	return total / float(count)


func _camera_depth_score(world: Vector3) -> float:
	# Same view-space Z used by the source perspective camera, without the camera
	# translation constant. Larger values are closer to the camera.
	var source_y := -world.y + CAMERA_SKEW * world.z
	var camera_rotation := deg_to_rad(editor_camera_pitch_degrees) if editor_camera_enabled else CAMERA_X_ROT
	return source_y * sin(camera_rotation) + world.z * cos(camera_rotation)


func _apply_humanoid_arm_torso_depth() -> void:
	if not _states.has("shoulderL") or not _states.has("shoulderR"):
		return
	var left_front := _side_front_state("shoulderL", "shoulderR", "L")
	if left_front == 0:
		# Exact front/back views have no meaningful shoulder depth separation. Keep
		# the figure's authored cardinal ordering there.
		return

	var torso_bounds := _visible_z_bounds(["top"])
	if not bool(torso_bounds.get("found", false)):
		return
	var front_suffix := "L" if left_front == 1 else "R"
	var back_suffix := "R" if front_suffix == "L" else "L"
	var front_nodes := ["arm" + front_suffix, "hand" + front_suffix, "finger" + front_suffix]
	var back_nodes := ["arm" + back_suffix, "hand" + back_suffix, "finger" + back_suffix]
	var layer_step := 1 if _embedded_world_mode else 16
	_shift_chain_above(front_nodes, int(torso_bounds.get("max", 0)), layer_step, "front_arm")
	_shift_chain_below(back_nodes, int(torso_bounds.get("min", 0)), layer_step, "rear_arm")


func _apply_humanoid_head_ceiling() -> void:
	# Male-Temp has arm pieces authored above its head layer. During attacks that
	# lets a raised hand paint over the skull. The head remains the top body layer
	# for Dummy/Male while equipment keeps its own independent weapon ordering.
	var arm_bounds := _visible_z_bounds([
		"armL", "handL", "fingerL",
		"armR", "handR", "fingerR",
	])
	if not bool(arm_bounds.get("found", false)):
		return
	var layer_step := 1 if _embedded_world_mode else 16
	_shift_chain_above(["head"], int(arm_bounds.get("max", 0)), layer_step, "head_over_hands")


func _apply_auxiliary_layer_depth() -> void:
	var layer_step := 1 if _embedded_world_mode else 16
	var head_bounds := _visible_z_bounds(["head"])
	if bool(head_bounds.get("found", false)):
		_shift_chain_above(["headGear"], int(head_bounds.get("max", 0)), layer_step, "head_attachment_layer")

	var body_bounds := _visible_z_bounds([
		"root", "top", "head", "bottom",
		"legL", "footL", "toeL", "legR", "footR", "toeR",
		"armL", "handL", "fingerL", "armR", "handR", "fingerR",
	])
	if bool(body_bounds.get("found", false)):
		_shift_chain_below(["tail", "tailEnd"], int(body_bounds.get("min", 0)), layer_step, "back_attachment_layer")


func _visible_z_bounds(node_names: Array) -> Dictionary:
	var found := false
	var min_z := 4096
	var max_z := -4096
	for record_variant in _sprite_records:
		if not record_variant is Dictionary:
			continue
		var record := record_variant as Dictionary
		var node_name := str(record.get("node", ""))
		if node_name not in node_names:
			continue
		var sprite := record.get("sprite") as Sprite2D
		if sprite == null or not sprite.visible:
			continue
		found = true
		min_z = mini(min_z, sprite.z_index)
		max_z = maxi(max_z, sprite.z_index)
	return {"found": found, "min": min_z, "max": max_z}


func _shift_chain_above(node_names: Array, reference_z: int, layer_step: int, reason: String = "front_chain") -> void:
	var bounds := _visible_z_bounds(node_names)
	if not bool(bounds.get("found", false)):
		return
	var chain_min := int(bounds.get("min", reference_z + layer_step))
	var required_min := reference_z + layer_step
	if chain_min >= required_min:
		return
	_shift_visible_nodes(node_names, required_min - chain_min, reason)


func _shift_chain_below(node_names: Array, reference_z: int, layer_step: int, reason: String = "rear_chain") -> void:
	var bounds := _visible_z_bounds(node_names)
	if not bool(bounds.get("found", false)):
		return
	var chain_max := int(bounds.get("max", reference_z - layer_step))
	var required_max := reference_z - layer_step
	if chain_max <= required_max:
		return
	_shift_visible_nodes(node_names, required_max - chain_max, reason)


func _shift_visible_nodes(node_names: Array, delta_z: int, reason: String) -> void:
	if delta_z == 0:
		return
	for record_variant in _sprite_records:
		if not record_variant is Dictionary:
			continue
		var record := record_variant as Dictionary
		if str(record.get("node", "")) not in node_names:
			continue
		var sprite := record.get("sprite") as Sprite2D
		if sprite == null or not sprite.visible:
			continue
		sprite.z_index = clampi(sprite.z_index + delta_z, -4096, 4096)
		sprite.set_meta("alabaster_humanoid_depth_reason", reason)
		sprite.set_meta("alabaster_humanoid_depth_shift", delta_z)


func get_runtime_summary() -> Dictionary:
	var result := super.get_runtime_summary()
	result["skin_profile_id"] = skin_profile_id
	result["figure_source"] = _skin_figure_source
	result["skin_data_source"] = _skin_data_source
	result["skin_texture_source"] = _skin_texture_source
	result["animation_bank_source"] = _animation_bank_source
	result["skin_ready"] = _skin_ready
	result["skin_initialized"] = _skin_initialized
	result["source_path"] = RepoSkinSource.get_source_path(skin_profile_id)
	result["atlas_path"] = RepoSkinSource.get_repo_atlas_path(skin_profile_id)
	result["juno_shared_retarget"] = _retarget_summary.duplicate(true)
	result["auxiliary_head_layer"] = "headGear"
	result["auxiliary_back_layer"] = "tailEnd"
	result["auxiliary_layers_active"] = false
	return result
