extends "res://scripts/labs/alabaster/AlabasterPlayableSkinRig.gd"
class_name AlabasterDefaultPlayableSkinRig

# DEFAULT is the Oathwake-owned humanoid base from this point forward.
# It intentionally starts as an exact source clone of Male-Dummy so every pivot,
# bone, facing mode, authored z-order and native animation remains proven-good,
# while keeping a distinct runtime/profile id for future body, equipment and
# custom-animation work.
#
# The body atlas currently falls back to dummy.png. Once default.png is committed,
# only DEFAULT's atlas loader needs to move to that file; Dummy remains frozen as
# the reference source.

const DEFAULT_PROFILE_ID := "default"
const BASE_PROFILE_ID := "male_dummy"
const DEFAULT_FIGURE_LABEL := "Default"


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
	var source_figure := RepoSkinSource.load_skin_figure(BASE_PROFILE_ID)
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
	# Binary default.png will become the authored atlas. Until it is committed,
	# use the exact Dummy texture so DEFAULT is visually/structurally identical.
	_atlas = RepoSkinSource.load_skin_texture(BASE_PROFILE_ID)
	_skin_texture_source = "DEFAULT_CLONE_OF_DUMMY_PNG" if _atlas != null else ""


func get_runtime_summary() -> Dictionary:
	var result := super.get_runtime_summary()
	result["skin_profile_id"] = DEFAULT_PROFILE_ID
	result["figure_source"] = DEFAULT_FIGURE_LABEL
	result["default_base_profile"] = BASE_PROFILE_ID
	result["default_base_json"] = RepoSkinSource.get_source_path(BASE_PROFILE_ID)
	result["default_base_atlas"] = RepoSkinSource.get_repo_atlas_path(BASE_PROFILE_ID)
	result["default_has_independent_runtime_copy"] = true
	return result
