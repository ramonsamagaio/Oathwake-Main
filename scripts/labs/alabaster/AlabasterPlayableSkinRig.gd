extends "res://scripts/systems/bones/BonesSystem.gd"
class_name AlabasterPlayableSkinRig

const SourceAssets := preload("res://scripts/labs/alabaster/AlabasterSourceAssetLibrary.gd")
const ExternalSkinSource := preload("res://scripts/labs/alabaster/AlabasterExternalSkinSource.gd")

var skin_profile_id := "male_dummy"
var _skin_figure_source := "Male-Dummy"
var _skin_ready := false
var _skin_initialized := false
var _skin_initializing := false
var _skin_data_source := ""
var _skin_texture_source := ""


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

	print("ALABASTER_SKIN_INIT_LOAD_FIGURE profile=%s" % skin_profile_id)
	_load_skin_data()
	if _figure.is_empty() or _nodes.is_empty():
		push_error("AlabasterPlayableSkinRig: initialization stopped because figure/nodes are empty for %s" % skin_profile_id)
		_skin_initializing = false
		return false

	print("ALABASTER_SKIN_INIT_FIGURE profile=%s source=%s nodes=%d anims=%d" % [
		skin_profile_id,
		_skin_data_source,
		_nodes.size(),
		_anims.size(),
	])

	_load_skin_atlas()
	if _atlas == null:
		push_error("AlabasterPlayableSkinRig: missing atlas for %s" % skin_profile_id)
		_skin_initializing = false
		return false

	print("ALABASTER_SKIN_INIT_ATLAS profile=%s source=%s size=%dx%d" % [
		skin_profile_id,
		_skin_texture_source,
		_atlas.get_width(),
		_atlas.get_height(),
	])

	_build_sprite_records()
	print("ALABASTER_SKIN_INIT_SPRITES profile=%s pieces=%d" % [skin_profile_id, _sprite_records.size()])
	if _sprite_records.is_empty():
		push_error("AlabasterPlayableSkinRig: no sprite records built for %s" % skin_profile_id)
		_skin_initializing = false
		return false

	current_animation = ""
	animation_time = 0.0
	_apply_pose()
	prewarm_animations(CORE_GAMEPLAY_ANIMATIONS)

	var visible_pieces := _count_visible_pieces()
	_skin_ready = not _sprite_records.is_empty() and visible_pieces > 0
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


func _count_visible_pieces() -> int:
	var visible_pieces := 0
	for record_variant in _sprite_records:
		var record: Dictionary = record_variant
		var sprite := record.get("sprite") as Sprite2D
		if sprite != null and sprite.visible:
			visible_pieces += 1
	return visible_pieces


func _load_skin_data() -> void:
	_figure = ExternalSkinSource.load_skin_figure(skin_profile_id)
	if not _figure.is_empty():
		_skin_data_source = "EXTERNAL_SOURCE_JSON"
	else:
		print("ALABASTER_SKIN_EXTERNAL_SOURCE_MISSING profile=%s using=EMBEDDED" % skin_profile_id)
		_figure = SourceAssets.load_skin_figure(skin_profile_id)
		_skin_data_source = "EMBEDDED_SOURCE_JSON"

	if _figure.is_empty():
		push_error("AlabasterPlayableSkinRig: figure could not be loaded for %s" % skin_profile_id)
		return

	var nodes_value: Variant = _figure.get("nodes", {})
	var anims_value: Variant = _figure.get("anims", {})
	_nodes = nodes_value as Dictionary if nodes_value is Dictionary else {}
	_anims = anims_value as Dictionary if anims_value is Dictionary else {}
	print("ALABASTER_SKIN_DATA_LOADED profile=%s source=%s path=%s nodes=%d anims=%d" % [
		skin_profile_id,
		_skin_data_source,
		ExternalSkinSource.get_source_path(skin_profile_id) if _skin_data_source == "EXTERNAL_SOURCE_JSON" else "embedded",
		_nodes.size(),
		_anims.size(),
	])
	if _nodes.is_empty():
		push_error("AlabasterPlayableSkinRig: %s has no nodes" % _skin_figure_source)
		return

	_install_weapon_sockets()
	_figure["nodes"] = _nodes
	_figure["anims"] = _anims
	_animation_bank_loaded = true
	_animation_bank_source = "%s_%s" % [_skin_data_source, _skin_figure_source.to_upper().replace("-", "_")]
	_track_cache.clear()
	_root_dirs.clear()


func _load_skin_atlas() -> void:
	_atlas = null
	_skin_texture_source = ""

	# The JSON and body sheet belong to the same authored source package. When the
	# original demo JSON is available, load its original media/char atlas too. The
	# repository's early .b64 fixtures were only a development convenience and are
	# known to be damaged on some profiles, so they are a fallback rather than the
	# primary source in development.
	if _skin_data_source == "EXTERNAL_SOURCE_JSON":
		_atlas = ExternalSkinSource.load_skin_texture(skin_profile_id)
		if _atlas != null:
			_skin_texture_source = "EXTERNAL_SOURCE_PNG"
			return
		print("ALABASTER_SKIN_EXTERNAL_ATLAS_FALLBACK profile=%s using=EMBEDDED" % skin_profile_id)

	_atlas = SourceAssets.load_skin_texture(skin_profile_id)
	if _atlas != null:
		_skin_texture_source = "EMBEDDED_SOURCE_PNG"


func _install_weapon_sockets() -> void:
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
	pass


func _apply_profile_front_arm_over_legs() -> void:
	pass


func get_runtime_summary() -> Dictionary:
	var result := super.get_runtime_summary()
	result["skin_profile_id"] = skin_profile_id
	result["figure_source"] = _skin_figure_source
	result["skin_data_source"] = _skin_data_source
	result["skin_texture_source"] = _skin_texture_source
	result["animation_bank_source"] = _animation_bank_source
	result["skin_ready"] = _skin_ready
	result["skin_initialized"] = _skin_initialized
	return result
