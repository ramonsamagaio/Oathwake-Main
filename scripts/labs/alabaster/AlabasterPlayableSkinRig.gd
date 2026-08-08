extends "res://scripts/systems/bones/BonesSystem.gd"
class_name AlabasterPlayableSkinRig

const SourceAssets := preload("res://scripts/labs/alabaster/AlabasterSourceAssetLibrary.gd")

var skin_profile_id := "male_dummy"
var _skin_figure_source := "Male-Dummy"
var _skin_ready := false
var _skin_initialized := false


func configure_skin_profile(profile_id: String) -> void:
	if is_inside_tree():
		push_warning("AlabasterPlayableSkinRig: configure_skin_profile must be called before add_child().")
		return
	skin_profile_id = "male_temp" if profile_id == "male_temp" else "male_dummy"
	_skin_figure_source = "Male-Temp-01" if skin_profile_id == "male_temp" else "Male-Dummy"


func _ready() -> void:
	# Do not rely on Node._ready() timing for playable skins. The player visual
	# controller can create this node from inside Player._ready(), where checking
	# readiness immediately after add_child() is too early on some scene-tree
	# paths. initialize_skin() is explicit and idempotent so both paths are safe.
	initialize_skin()


func initialize_skin() -> bool:
	if _skin_initialized:
		return is_skin_ready()
	_skin_initialized = true
	_skin_ready = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	print("ALABASTER_SKIN_INIT_BEGIN profile=%s figure=%s inside_tree=%s" % [
		skin_profile_id,
		_skin_figure_source,
		str(is_inside_tree()),
	])

	_load_skin_data()
	if _figure.is_empty():
		push_error("AlabasterPlayableSkinRig: initialization stopped because figure is empty for %s" % skin_profile_id)
		return false

	print("ALABASTER_SKIN_INIT_FIGURE profile=%s nodes=%d anims=%d" % [
		skin_profile_id,
		_nodes.size(),
		_anims.size(),
	])

	_atlas = SourceAssets.load_skin_texture(skin_profile_id)
	if _atlas == null:
		push_error("AlabasterPlayableSkinRig: missing atlas for %s" % skin_profile_id)
		return false

	print("ALABASTER_SKIN_INIT_ATLAS profile=%s size=%dx%d" % [
		skin_profile_id,
		_atlas.get_width(),
		_atlas.get_height(),
	])

	_build_sprite_records()
	print("ALABASTER_SKIN_INIT_SPRITES profile=%s pieces=%d" % [skin_profile_id, _sprite_records.size()])
	_apply_pose()
	if has_method("_merge_custom_animation_library"):
		call("_merge_custom_animation_library")
	prewarm_animations(CORE_GAMEPLAY_ANIMATIONS)
	var visible_pieces := _count_visible_pieces()
	_skin_ready = not _sprite_records.is_empty() and visible_pieces > 0
	set_process(_skin_ready)
	print("ALABASTER_SKIN_READY profile=%s figure=%s atlas=%dx%d nodes=%d pieces=%d visible=%d anims=%d ready=%s" % [
		skin_profile_id,
		_skin_figure_source,
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
	return _skin_ready and _atlas != null and not _figure.is_empty() and not _sprite_records.is_empty()


func _count_visible_pieces() -> int:
	var visible_pieces := 0
	for record_variant in _sprite_records:
		var record: Dictionary = record_variant
		var sprite := record.get("sprite") as Sprite2D
		if sprite != null and sprite.visible:
			visible_pieces += 1
	return visible_pieces


func _load_skin_data() -> void:
	_figure = SourceAssets.load_skin_figure(skin_profile_id)
	if _figure.is_empty():
		push_error("AlabasterPlayableSkinRig: figure could not be loaded for %s" % skin_profile_id)
		return
	_nodes = _figure.get("nodes", {})
	_anims = _figure.get("anims", {})
	if _nodes.is_empty():
		push_error("AlabasterPlayableSkinRig: %s has no nodes" % _skin_figure_source)
		return
	_install_weapon_sockets()
	_figure["nodes"] = _nodes
	_animation_bank_loaded = true
	_animation_bank_source = "BUNDLED_%s" % _skin_figure_source.to_upper().replace("-", "_")
	_track_cache.clear()
	_root_dirs.clear()


func _install_weapon_sockets() -> void:
	# These source test figures predate the player weapon attachment nodes.
	# The sockets are graphics-free and inherit the authored hand/body transforms.
	if not _nodes.has("weaponR"):
		_nodes["weaponR"] = {
			"parent": "handR",
			"part": "PART_7",
			"pos": [0.0, 0.5, 0.0],
			"colls": [],
			"gfx": [],
			"frameAnims": {},
			"frameKeys": ["down", "swoosh", "swooshDown"],
		}
	if not _nodes.has("weaponL"):
		_nodes["weaponL"] = {
			"parent": "handL",
			"part": "PART_6",
			"pos": [0.0, 0.5, 0.0],
			"colls": [],
			"gfx": [],
			"frameAnims": {},
			"frameKeys": ["down", "swoosh", "swooshDown"],
		}
	if not _nodes.has("weaponBelt"):
		_nodes["weaponBelt"] = {
			"parent": "bottom",
			"part": "PART_7",
			"pos": [0.0, -0.25, -0.25],
			"colls": [],
			"gfx": [],
			"frameAnims": {},
			"frameKeys": [],
		}


func _apply_directional_layer_override(_record: Dictionary, _sprite: Sprite2D) -> void:
	# Dummy/Male have their own authored zOrder tables. The Production layer also
	# contains Oathwake corrections made specifically for Juno's arm/leg/headGear
	# crossings; those must never overwrite a different source figure.
	pass


func _apply_profile_front_arm_over_legs() -> void:
	# Same rule as above: these test figures use their native source layer order.
	pass


func get_runtime_summary() -> Dictionary:
	var result := super.get_runtime_summary()
	result["skin_profile_id"] = skin_profile_id
	result["figure_source"] = _skin_figure_source
	result["animation_bank_source"] = _animation_bank_source
	result["skin_ready"] = _skin_ready
	return result
