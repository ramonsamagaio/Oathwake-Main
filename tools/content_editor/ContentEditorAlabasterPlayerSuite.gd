extends "res://tools/content_editor/ContentEditorPetSaveDashSideSuite.gd"

const PLAYER_CHARACTER_FIELD := "alabaster_active_player_character"


func _build_player_tuning_form() -> void:
	super._build_player_tuning_form()
	_add_subsection_title("Player Character")
	var note := Label.new()
	note.text = "Chooses which Characters record drives the player visual. Bone-rig characters and classic sprite-sheet characters use the same gameplay body; only the visual runtime changes."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)
	_add_player_character_picker(str(current_record.get("character_id", "player")))


func _add_player_character_picker(selected_character_id: String) -> void:
	var option := OptionButton.new()
	var selected_index := 0
	var index := 0
	for character_record in data_store.get_records(ContentEditorData.SECTION_CHARACTERS):
		var character_id := str(character_record.get("id", "")).strip_edges()
		if character_id.is_empty():
			continue
		var display_name := str(character_record.get("display_name", character_id)).strip_edges()
		var runtime_name := str(character_record.get("visual_runtime", "sprite_sheet"))
		var label := "%s  [%s]" % [display_name, character_id]
		if runtime_name == "alabaster":
			label += "  • Bone Rig"
		option.add_item(label)
		option.set_item_metadata(index, character_id)
		if character_id == selected_character_id:
			selected_index = index
		index += 1
	if option.item_count == 0:
		option.add_item("No character records")
		option.set_item_metadata(0, "")
	option.select(clampi(selected_index, 0, option.item_count - 1))
	option.item_selected.connect(func(_index: int) -> void: _mark_dirty())
	option.tooltip_text = "The selected Characters record becomes the player visual after Save. Juno - Alabaster Rig uses the bone-driven runtime."
	_add_form_row("Active Player Character", option)
	field_controls[PLAYER_CHARACTER_FIELD] = option


func _get_player_tuning_form_record() -> Dictionary:
	# The legacy form only rebuilds fields that are currently visible. Preserve
	# every existing tuning key first, then overlay all values produced by the
	# complete editor suite chain. This prevents character_id, dash, light,
	# stamina, camera and future tuning fields from being deleted on Save.
	var preserved := current_record.duplicate(true)
	var edited := super._get_player_tuning_form_record()
	for key in edited.keys():
		preserved[key] = edited[key]
	if field_controls.has(PLAYER_CHARACTER_FIELD):
		preserved["character_id"] = _get_option_button_metadata(PLAYER_CHARACTER_FIELD)
	preserved["id"] = "default"
	return preserved


func _build_character_form() -> void:
	super._build_character_form()
	var runtime_name := str(current_record.get("visual_runtime", "sprite_sheet"))
	if runtime_name != "alabaster":
		return
	_add_subsection_title("Bone Rig Character")
	_add_read_only_value("Visual Runtime", "Alabaster bone rig")
	_add_read_only_value("Rig Profile", str(current_record.get("rig_profile_id", "juno")))
	var animation_map = current_record.get("rig_animation_map", {})
	if animation_map is Dictionary:
		var pairs := []
		for action_name in ["idle", "walk", "run", "attack", "block", "hurt", "death", "dash"]:
			if animation_map.has(action_name):
				pairs.append("%s → %s" % [action_name, str(animation_map[action_name])])
		_add_read_only_value("Gameplay Animation Map", ", ".join(pairs))


func _refresh_live_players() -> void:
	super._refresh_live_players()
	if _runtime_shutting_down or get_tree() == null:
		return
	for player in get_tree().get_nodes_in_group("player"):
		if player != null and is_instance_valid(player) and player.has_method("refresh_alabaster_character_visual"):
			player.call_deferred("refresh_alabaster_character_visual")
