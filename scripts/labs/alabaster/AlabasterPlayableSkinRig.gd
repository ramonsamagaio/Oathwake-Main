extends "res://scripts/labs/alabaster/AlabasterRigRuntimeProduction.gd"
class_name AlabasterPlayableSkinRig

const SourceAssets := preload("res://scripts/labs/alabaster/AlabasterSourceAssetLibrary.gd")

var skin_profile_id := "male_dummy"


func configure_skin_profile(profile_id: String) -> void:
	if is_inside_tree():
		push_warning("AlabasterPlayableSkinRig: configure_skin_profile must be called before add_child().")
		return
	skin_profile_id = "male_temp" if profile_id == "male_temp" else "male_dummy"


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_load_skin_data()
	if _figure.is_empty():
		return
	_atlas = SourceAssets.load_skin_texture(skin_profile_id)
	if _atlas == null:
		push_error("AlabasterPlayableSkinRig: missing atlas for %s" % skin_profile_id)
		return
	_build_sprite_records()
	_apply_pose()
	set_process(true)
	if has_method("_merge_custom_animation_library"):
		call("_merge_custom_animation_library")
	print("ALABASTER_SKIN_READY profile=%s nodes=%d anims=%d" % [skin_profile_id, _nodes.size(), _anims.size()])


func _load_skin_data() -> void:
	_figure = SourceAssets.load_male_dummy_figure()
	if _figure.is_empty():
		push_error("AlabasterPlayableSkinRig: Male-Dummy figure could not be loaded")
		return
	_nodes = _figure.get("nodes", {})
	_anims = _figure.get("anims", {})
	_install_weapon_sockets()
	_figure["nodes"] = _nodes
	_animation_bank_loaded = true
	_animation_bank_source = "BUNDLED_MALE_DUMMY"
	_track_cache.clear()
	_root_dirs.clear()


func _install_weapon_sockets() -> void:
	# The test Male-Dummy figure predates the player weapon attachment nodes.
	# These sockets are intentionally graphics-free and inherit hand/body motion.
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


func get_runtime_summary() -> Dictionary:
	var result := super.get_runtime_summary()
	result["skin_profile_id"] = skin_profile_id
	result["figure_source"] = "Male-Dummy"
	result["animation_bank_source"] = _animation_bank_source
	return result
