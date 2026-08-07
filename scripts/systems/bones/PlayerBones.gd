extends "res://scripts/player/PlayerAlabasterRigSuite.gd"
class_name PlayerBones

# Single gameplay entry point for bone-driven player rendering.
# Low-level source rendering remains in the Alabaster lab, but the live Player
# scene only references this production facade plus BonesSystem/BonesWeapons.

const BonesWeaponRuntime := preload("res://scripts/systems/bones/BonesWeapons.gd")

var _bones_ground_offset := Vector2.ZERO


func _init() -> void:
	_weapon_visual = BonesWeaponRuntime.new()


func _setup_character_visual() -> void:
	super._setup_character_visual()
	_refresh_bones_character_profile()
	_apply_bones_ground_alignment()
	if _rig_visual.active:
		_rig_visual.prewarm_actions()


func _apply_player_visual_tuning() -> void:
	super._apply_player_visual_tuning()
	_apply_bones_ground_alignment()


func refresh_alabaster_character_visual() -> void:
	super.refresh_alabaster_character_visual()
	_refresh_bones_character_profile()
	_apply_bones_ground_alignment()
	if _rig_visual.active:
		_rig_visual.prewarm_actions()


func _refresh_bones_character_profile() -> void:
	_bones_ground_offset = Vector2.ZERO
	if not _rig_visual.active:
		return
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_character") or not content_db.has_character(character_id):
		return
	var character_data: Dictionary = content_db.get_character(character_id)
	var offset_value: Variant = character_data.get("bones_ground_offset", {})
	if offset_value is Dictionary:
		var offset_data := offset_value as Dictionary
		_bones_ground_offset = Vector2(
			float(offset_data.get("x", 0.0)),
			float(offset_data.get("y", 0.0))
		)
	set_meta("bones_ground_offset", _bones_ground_offset)


func _apply_bones_ground_alignment() -> void:
	if not _rig_visual.active or _rig_visual.rig == null or not is_instance_valid(_rig_visual.rig):
		return
	_rig_visual.rig.position = _content_visual_offset + _bones_ground_offset
	_rig_visual.rig.scale = Vector2.ONE * _content_visual_scale
	set_meta("bones_visual_position", _rig_visual.rig.position)
	set_meta("bones_ground_world_position", global_position + Vector2(0.0, 12.0))
	_force_rig_visual()
