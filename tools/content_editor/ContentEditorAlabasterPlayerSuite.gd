extends "res://tools/content_editor/ContentEditorPetSaveDashSideSuite.gd"

const BoneAnimationLibrary := preload("res://scripts/labs/alabaster/AlabasterBoneAnimationLibrary.gd")
const PLAYER_CHARACTER_FIELD := "character_id"
const PLAYER_WEAPON_VISIBILITY_FIELD := "alabaster_weapon_visibility_mode"
const ALABASTER_ACTIONS := ["idle", "walk", "run", "attack", "block", "hurt", "death", "dash"]
const ALABASTER_MASTER_DIRECTIONS := [
	["N", "n"],
	["NE / NW", "ne"],
	["E / W", "e"],
	["SE / SW", "se"],
	["S", "s"],
]
const DEFAULT_ALABASTER_ACTIONS := {
	"idle": "idle",
	"walk": "walk",
	"run": "run",
	"attack": "atkSwordN1",
	"block": "guard",
	"hurt": "damage",
	"death": "dead",
	"dash": "dash",
}

var _alabaster_animation_names: Array[String] = []


func _ready() -> void:
	super._ready()
	_install_exact_save_handler()


func _install_exact_save_handler() -> void:
	# ContentEditor.gd creates/connects SaveButton in the base class. This top
	# suite is the script actually attached to ContentEditor.tscn, so own the
	# signal explicitly instead of relying on a long inheritance chain to route
	# Player Tuning through the right _save_player_tuning override.
	if save_button == null:
		return
	var connections := save_button.pressed.get_connections()
	for connection_value in connections:
		if not connection_value is Dictionary:
			continue
		var callback: Callable = (connection_value as Dictionary).get("callable", Callable())
		if callback.is_valid() and save_button.pressed.is_connected(callback):
			save_button.pressed.disconnect(callback)
	if not save_button.pressed.is_connected(_on_bones_content_save_pressed):
		save_button.pressed.connect(_on_bones_content_save_pressed)


func _on_bones_content_save_pressed() -> void:
	if current_section == ContentEditorData.SECTION_PLAYER_TUNING:
		_save_player_tuning_exact()
		return
	super._on_save_pressed()


func _build_player_tuning_form() -> void:
	super._build_player_tuning_form()
	_add_subsection_title("Player Character")
	var note := Label.new()
	note.text = "Chooses which Characters record drives the player visual. This is saved directly as player_tuning.default.character_id."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)
	_add_player_character_picker(str(current_record.get("character_id", "player")))

	_add_subsection_title("Bone Weapon Visibility")
	var weapon_note := Label.new()
	weapon_note.text = "Attack Only shows a bone-attached weapon only while attacking. Always When Supported keeps an authored rest/back figure visible when the item provides one."
	weapon_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(weapon_note)
	var mode := str(current_record.get("alabaster_weapon_visibility", "attack_only"))
	_add_string_option_button(
		"Weapon Display",
		PLAYER_WEAPON_VISIBILITY_FIELD,
		["attack_only", "always_when_supported"],
		mode
	)


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
	option.item_selected.connect(_on_player_character_selected.bind(option))
	option.tooltip_text = "Saved directly as res://data/player_tuning.json -> default.character_id."
	_add_form_row("Active Player Character", option)
	field_controls[PLAYER_CHARACTER_FIELD] = option


func _on_player_character_selected(index: int, option: OptionButton) -> void:
	if option == null or index < 0 or index >= option.item_count:
		return
	var selected_character_id := str(option.get_item_metadata(index)).strip_edges()
	if selected_character_id.is_empty():
		return
	current_record["character_id"] = selected_character_id
	_mark_dirty()
	_set_status("Selected player character: %s (press Save to persist)" % selected_character_id)


func _save_player_tuning() -> void:
	# Keep this override for callers other than the Save button. The Save button
	# itself is rewired explicitly in _ready() to avoid ambiguous base callbacks.
	_save_player_tuning_exact()


func _save_player_tuning_exact() -> void:
	var selected_character_id := str(current_record.get("character_id", "")).strip_edges()
	var character_option := field_controls.get(PLAYER_CHARACTER_FIELD) as OptionButton
	if character_option != null and character_option.selected >= 0:
		selected_character_id = str(character_option.get_item_metadata(character_option.selected)).strip_edges()

	if selected_character_id.is_empty():
		_set_status("Active Player Character cannot be empty.", true)
		return
	if not data_store.has_record(ContentEditorData.SECTION_CHARACTERS, selected_character_id):
		_set_status("Active Player Character does not exist: %s" % selected_character_id, true)
		return

	# Preserve the complete singleton record. Lower suites edit their fields,
	# while character_id and bone weapon visibility are owned here explicitly.
	var record := current_record.duplicate(true)
	var edited := super._get_player_tuning_form_record()
	for key in edited.keys():
		record[key] = edited[key]
	record["id"] = "default"
	record["character_id"] = selected_character_id
	if field_controls.has(PLAYER_WEAPON_VISIBILITY_FIELD):
		record["alabaster_weapon_visibility"] = _get_option_button_metadata(PLAYER_WEAPON_VISIBILITY_FIELD)

	var validation_error := data_store.validate_player_tuning("default", current_original_id, record)
	if not validation_error.is_empty():
		_set_status(validation_error, true)
		return

	# Write exactly once, then re-read the physical JSON through ContentEditorData.
	# Do not rebuild the form or reload ContentDB until persistence is verified.
	data_store.set_record(ContentEditorData.SECTION_PLAYER_TUNING, "default", "default", record)
	var save_error := data_store.save_section(ContentEditorData.SECTION_PLAYER_TUNING)
	if not save_error.is_empty():
		_set_status(save_error, true)
		return

	var reload_error := data_store.load_section(ContentEditorData.SECTION_PLAYER_TUNING)
	if not reload_error.is_empty():
		_set_status(reload_error, true)
		return
	var persisted := data_store.get_record(ContentEditorData.SECTION_PLAYER_TUNING, "default")
	var persisted_character := str(persisted.get("character_id", "")).strip_edges()
	if persisted_character != selected_character_id:
		_set_status(
			"PLAYER CHARACTER SAVE FAILED: selected=%s persisted=%s" % [selected_character_id, persisted_character],
			true
		)
		push_error("PLAYER_CHARACTER_SAVE_MISMATCH selected=%s persisted=%s" % [selected_character_id, persisted_character])
		return

	_reload_content_db()
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("get_player_tuning"):
		var runtime_tuning: Dictionary = content_db.call("get_player_tuning", "default")
		var runtime_character := str(runtime_tuning.get("character_id", "")).strip_edges()
		if runtime_character != selected_character_id:
			_set_status(
				"PLAYER CHARACTER RUNTIME RELOAD FAILED: persisted=%s ContentDB=%s" % [selected_character_id, runtime_character],
				true
			)
			push_error("PLAYER_CHARACTER_CONTENTDB_MISMATCH persisted=%s runtime=%s" % [selected_character_id, runtime_character])
			return

	current_id = "default"
	current_original_id = "default"
	current_record = persisted
	has_unsaved_changes = false
	_build_form_for_current_record()
	_refresh_record_list()
	_update_action_buttons()
	_refresh_live_players()
	_set_status("Saved Player Tuning. Active character: %s" % selected_character_id)
	print("PLAYER_CHARACTER_SAVE_OK selected=%s persisted=%s" % [selected_character_id, persisted_character])


func _get_player_tuning_form_record() -> Dictionary:
	# Preserve every tuning field that older/lower editor suites do not expose.
	# Player Tuning is an extensible singleton and must never be rebuilt from a
	# tiny whitelist of visible controls.
	var preserved := current_record.duplicate(true)
	var edited := super._get_player_tuning_form_record()
	for key in edited.keys():
		preserved[key] = edited[key]
	if field_controls.has(PLAYER_CHARACTER_FIELD):
		var selected_character_id := _get_option_button_metadata(PLAYER_CHARACTER_FIELD).strip_edges()
		if not selected_character_id.is_empty():
			preserved["character_id"] = selected_character_id
	if field_controls.has(PLAYER_WEAPON_VISIBILITY_FIELD):
		preserved["alabaster_weapon_visibility"] = _get_option_button_metadata(PLAYER_WEAPON_VISIBILITY_FIELD)
	preserved["id"] = "default"
	return preserved


func _build_character_form() -> void:
	super._build_character_form()
	var runtime_name := str(current_record.get("visual_runtime", "sprite_sheet"))
	if runtime_name != "alabaster":
		return
	_alabaster_animation_names = BoneAnimationLibrary.get_all_animation_names()
	_add_subsection_title("Bone Rig Character")
	_add_read_only_value("Visual Runtime", "Hybrid 3D-bone / 2D-billboard rig")
	_add_read_only_value("Rig Profile", str(current_record.get("rig_profile_id", "juno")))
	_add_read_only_value("Bone Studio", "res://scenes/labs/alabaster/AlabasterBoneStudio.tscn")
	_add_read_only_value("Animation Bank", BoneAnimationLibrary.CUSTOM_BANK_PATH)

	var help := Label.new()
	help.text = "Base Action is the normal animation used at every facing angle. The five Master View overrides are optional. Leave an override on 'Use Base Action' unless that direction needs a different clip."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(help)

	var base_map_value: Variant = current_record.get("rig_animation_map", {})
	var base_map: Dictionary = base_map_value as Dictionary if base_map_value is Dictionary else {}
	var directional_value: Variant = current_record.get("rig_directional_animation_map", {})
	var directional_map: Dictionary = directional_value as Dictionary if directional_value is Dictionary else {}

	_add_subsection_title("Base Gameplay Actions")
	for action_name in ALABASTER_ACTIONS:
		var selected := str(base_map.get(action_name, DEFAULT_ALABASTER_ACTIONS.get(action_name, "idle")))
		_add_alabaster_animation_picker(
			"%s Animation" % action_name.capitalize(),
			"alabaster_action_%s" % action_name,
			selected,
			false
		)

	_add_subsection_title("Optional Master-View Overrides")
	for action_name in ALABASTER_ACTIONS:
		var action_title := Label.new()
		action_title.text = action_name.to_upper()
		action_title.add_theme_font_size_override("font_size", 15)
		form_container.add_child(action_title)
		var action_dirs_value: Variant = directional_map.get(action_name, {})
		var action_dirs: Dictionary = action_dirs_value as Dictionary if action_dirs_value is Dictionary else {}
		for direction_pair in ALABASTER_MASTER_DIRECTIONS:
			var display_dir := str(direction_pair[0])
			var direction_key := str(direction_pair[1])
			_add_alabaster_animation_picker(
				"%s %s" % [action_name.capitalize(), display_dir],
				"alabaster_dir_%s_%s" % [action_name, direction_key],
				str(action_dirs.get(direction_key, "")),
				true
			)


func _add_alabaster_animation_picker(label_text: String, field_name: String, selected_animation: String, allow_base: bool) -> void:
	var option := OptionButton.new()
	var selected_index := 0
	if allow_base:
		option.add_item("Use Base Action")
		option.set_item_metadata(0, "")
	var found := selected_animation.is_empty() and allow_base
	for animation_name in _alabaster_animation_names:
		var index := option.item_count
		option.add_item(animation_name)
		option.set_item_metadata(index, animation_name)
		if animation_name == selected_animation:
			selected_index = index
			found = true
	if not found and not selected_animation.is_empty():
		option.add_item(selected_animation + "  [missing from bank]")
		option.set_item_metadata(option.item_count - 1, selected_animation)
		selected_index = option.item_count - 1
	option.select(clampi(selected_index, 0, maxi(option.item_count - 1, 0)))
	option.item_selected.connect(func(_index: int) -> void: _mark_dirty())
	_add_form_row(label_text, option)
	field_controls[field_name] = option


func _get_character_form_record() -> Dictionary:
	var record := super._get_character_form_record()
	if str(record.get("visual_runtime", current_record.get("visual_runtime", "sprite_sheet"))) != "alabaster":
		return record
	var base_map := {}
	for action_name in ALABASTER_ACTIONS:
		var field_name := "alabaster_action_%s" % action_name
		if field_controls.has(field_name):
			base_map[action_name] = _get_option_button_metadata(field_name)
		else:
			base_map[action_name] = str(DEFAULT_ALABASTER_ACTIONS.get(action_name, "idle"))
	record["rig_animation_map"] = base_map

	var directional_map := {}
	for action_name in ALABASTER_ACTIONS:
		var action_dirs := {}
		for direction_pair in ALABASTER_MASTER_DIRECTIONS:
			var direction_key := str(direction_pair[1])
			var field_name := "alabaster_dir_%s_%s" % [action_name, direction_key]
			if not field_controls.has(field_name):
				continue
			var animation_name := _get_option_button_metadata(field_name)
			if not animation_name.is_empty():
				action_dirs[direction_key] = animation_name
		if not action_dirs.is_empty():
			directional_map[action_name] = action_dirs
	record["rig_directional_animation_map"] = directional_map
	return record


func _refresh_live_players() -> void:
	super._refresh_live_players()
	if _runtime_shutting_down or get_tree() == null:
		return
	for player in get_tree().get_nodes_in_group("player"):
		if player != null and is_instance_valid(player) and player.has_method("refresh_alabaster_character_visual"):
			player.call_deferred("refresh_alabaster_character_visual")
