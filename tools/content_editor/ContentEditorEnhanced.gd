extends "res://tools/content_editor/ContentEditor.gd"

const SFX_DATA_PATH := "res://data/sfx_profiles.json"

var sfx_profiles: Dictionary = {}
var sfx_window: Window
var sfx_profile_list: ItemList
var sfx_fields: Dictionary = {}
var sfx_selected_id := ""
var sfx_audio_dialog: FileDialog
var sfx_preview_player: AudioStreamPlayer
var sfx_status_label: Label


func _ready() -> void:
	super._ready()
	call_deferred("_install_sfx_editor")


func _build_item_form() -> void:
	super._build_item_form()
	var item_type := str(current_record.get("item_type", "material"))
	if item_type not in ["weapon", "tool", "armor", "accessory"]:
		return
	_add_subsection_title("Combat Substats")
	_add_float_spin_box("Attack Speed Bonus", "substat_attack_speed_bonus", float(current_record.get("attack_speed_bonus", 0.0)), -0.95, 10.0, 0.01)
	_add_float_spin_box("Invulnerability Duration Bonus", "substat_invulnerability_bonus", float(current_record.get("invulnerability_duration_bonus", 0.0)), -10.0, 10.0, 0.05)


func _get_item_form_record() -> Dictionary:
	var record := super._get_item_form_record()
	if field_controls.has("substat_attack_speed_bonus"):
		record["attack_speed_bonus"] = _get_spin_box_value("substat_attack_speed_bonus")
		record["invulnerability_duration_bonus"] = _get_spin_box_value("substat_invulnerability_bonus")
	return record


func _build_player_tuning_form() -> void:
	super._build_player_tuning_form()
	_add_subsection_title("Fast Combat")
	_add_float_spin_box("Dash Speed", "dash_speed", float(current_record.get("dash_speed", 430.0)), 0.0, 2000.0, 1.0)
	_add_float_spin_box("Dash Duration", "dash_duration", float(current_record.get("dash_duration", 0.14)), 0.01, 2.0, 0.01)
	_add_float_spin_box("Dash Cooldown", "dash_cooldown", float(current_record.get("dash_cooldown", 0.34)), 0.0, 5.0, 0.01)
	_add_float_spin_box("Attack Buffer Window", "attack_buffer_window", float(current_record.get("attack_buffer_window", 0.32)), 0.0, 2.0, 0.01)
	_add_float_spin_box("Invulnerability Blink Interval", "invulnerability_blink_interval", float(current_record.get("invulnerability_blink_interval", 0.09)), 0.02, 1.0, 0.01)


func _get_player_tuning_form_record() -> Dictionary:
	var record := super._get_player_tuning_form_record()
	record["dash_speed"] = _get_spin_box_value("dash_speed")
	record["dash_duration"] = _get_spin_box_value("dash_duration")
	record["dash_cooldown"] = _get_spin_box_value("dash_cooldown")
	record["attack_buffer_window"] = _get_spin_box_value("attack_buffer_window")
	record["invulnerability_blink_interval"] = _get_spin_box_value("invulnerability_blink_interval")
	return record


func _build_character_form() -> void:
	super._build_character_form()
	_add_subsection_title("Combat Timing & Substats")
	var base_combat := _get_record_dictionary(current_record, "base_combat")
	_add_check_box("Attack Timing Enabled", "character_attack_timing_enabled", bool(current_record.get("attack_timing_enabled", true)))
	_add_float_spin_box("Attack Windup", "character_attack_windup", float(current_record.get("attack_windup_time", 0.04)), 0.0, 5.0, 0.01)
	_add_float_spin_box("Attack Hit Delay", "character_attack_hit_time", float(current_record.get("attack_hit_time", 0.02)), 0.0, 5.0, 0.01)
	_add_float_spin_box("Attack Recovery", "character_attack_recovery", float(current_record.get("attack_recovery_time", 0.14)), 0.0, 5.0, 0.01)
	_add_float_spin_box("Base Attack Cooldown", "character_attack_cooldown", float(base_combat.get("attack_cooldown", 0.7)), 0.06, 10.0, 0.01)
	_add_float_spin_box("Base Attack Speed Bonus", "character_attack_speed_bonus", float(base_combat.get("attack_speed_bonus", 0.0)), -0.95, 10.0, 0.01)
	_add_float_spin_box("Base Invulnerability Duration", "character_invulnerability_duration", float(base_combat.get("base_invulnerability_duration", 2.0)), 0.0, 10.0, 0.05)


func _get_character_form_record() -> Dictionary:
	var record := super._get_character_form_record()
	if not field_controls.has("character_attack_timing_enabled"):
		return record
	record["attack_timing_enabled"] = _get_check_box_pressed("character_attack_timing_enabled")
	record["attack_windup_time"] = _get_spin_box_value("character_attack_windup")
	record["attack_hit_time"] = _get_spin_box_value("character_attack_hit_time")
	record["attack_recovery_time"] = _get_spin_box_value("character_attack_recovery")
	var base_combat := _get_record_dictionary(record, "base_combat")
	base_combat["attack_cooldown"] = _get_spin_box_value("character_attack_cooldown")
	base_combat["attack_speed_bonus"] = _get_spin_box_value("character_attack_speed_bonus")
	base_combat["base_invulnerability_duration"] = _get_spin_box_value("character_invulnerability_duration")
	record["base_combat"] = base_combat
	return record


func _build_vfx_profile_form() -> void:
	super._build_vfx_profile_form()
	if str(current_record.get("id", "default")) != "default":
		return
	_add_subsection_title("Fast Combat Feedback")
	_add_float_spin_box("White Hit Flash Duration", "white_hit_flash_duration", float(current_record.get("white_hit_flash_duration", 0.08)), 0.01, 1.0, 0.01)
	_add_float_spin_box("Critical White Flash Duration", "critical_white_hit_flash_duration", float(current_record.get("critical_white_hit_flash_duration", 0.10)), 0.01, 1.0, 0.01)
	_add_spin_box("Dash Glint Count", "dash_glint_count", int(current_record.get("dash_glint_count", 3)), 0, 32, 1)
	_add_float_spin_box("Dash Glint Alpha", "dash_glint_alpha", float(current_record.get("dash_glint_alpha", 0.24)), 0.0, 1.0, 0.01)
	_add_float_spin_box("Dash Glint Lifetime", "dash_glint_lifetime", float(current_record.get("dash_glint_lifetime", 0.12)), 0.01, 2.0, 0.01)
	_add_float_spin_box("Dash Glint Spread", "dash_glint_spread", float(current_record.get("dash_glint_spread", 7.0)), 0.0, 128.0, 0.5)


func _get_vfx_profile_form_record() -> Dictionary:
	var record := super._get_vfx_profile_form_record()
	if str(current_record.get("id", "default")) != "default":
		return record
	record["white_hit_flash_duration"] = _get_spin_box_value("white_hit_flash_duration")
	record["critical_white_hit_flash_duration"] = _get_spin_box_value("critical_white_hit_flash_duration")
	record["dash_glint_count"] = _get_spin_box_int("dash_glint_count")
	record["dash_glint_alpha"] = _get_spin_box_value("dash_glint_alpha")
	record["dash_glint_lifetime"] = _get_spin_box_value("dash_glint_lifetime")
	record["dash_glint_spread"] = _get_spin_box_value("dash_glint_spread")
	return record


func _add_subsection_title(text_value: String) -> void:
	var title := Label.new()
	title.text = text_value
	form_container.add_child(title)


func _install_sfx_editor() -> void:
	var sidebar := get_node_or_null("MarginContainer/MainLayout/Sidebar") as VBoxContainer
	if sidebar == null:
		push_warning("ContentEditorEnhanced could not find the sidebar.")
		return
	var button := Button.new()
	button.name = "SoundEffectsButton"
	button.text = "Sound Effects"
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(_open_sfx_editor)
	sidebar.add_child(button)
	_build_sfx_window()


func _build_sfx_window() -> void:
	if sfx_window != null:
		return
	sfx_window = Window.new()
	sfx_window.title = "Oathwake Sound Effects"
	sfx_window.size = Vector2i(1040, 720)
	sfx_window.min_size = Vector2i(860, 620)
	sfx_window.close_requested.connect(sfx_window.hide)
	add_child(sfx_window)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	sfx_window.add_child(margin)

	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 320
	margin.add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	split.add_child(left)
	var heading := Label.new()
	heading.text = "Gameplay Sound Events"
	left.add_child(heading)
	sfx_profile_list = ItemList.new()
	sfx_profile_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sfx_profile_list.item_selected.connect(_on_sfx_profile_selected)
	left.add_child(sfx_profile_list)
	var left_actions := HBoxContainer.new()
	left.add_child(left_actions)
	_add_sfx_button(left_actions, "New", _new_sfx_profile)
	_add_sfx_button(left_actions, "Duplicate", _duplicate_sfx_profile)
	_add_sfx_button(left_actions, "Delete", _delete_sfx_profile)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(form)

	sfx_fields["id"] = _add_sfx_line_field(form, "Event ID")
	sfx_fields["display_name"] = _add_sfx_line_field(form, "Display Name")
	var paths_edit := TextEdit.new()
	paths_edit.custom_minimum_size = Vector2(0, 180)
	paths_edit.placeholder_text = "One res:// audio path per line"
	_add_sfx_form_row(form, "Audio Variants", paths_edit)
	sfx_fields["stream_paths"] = paths_edit
	var browse_button := Button.new()
	browse_button.text = "Choose Audio Files"
	browse_button.pressed.connect(_browse_sfx_files)
	form.add_child(browse_button)
	sfx_fields["volume_db"] = _add_sfx_spin_field(form, "Volume dB", -80.0, 24.0, 0.5)
	sfx_fields["pitch_min"] = _add_sfx_spin_field(form, "Pitch Min", 0.1, 4.0, 0.01)
	sfx_fields["pitch_max"] = _add_sfx_spin_field(form, "Pitch Max", 0.1, 4.0, 0.01)
	sfx_fields["max_distance"] = _add_sfx_spin_field(form, "Max Distance", 0.0, 10000.0, 10.0)

	var action_row := HBoxContainer.new()
	right.add_child(action_row)
	_add_sfx_button(action_row, "Preview", _preview_sfx_profile)
	_add_sfx_button(action_row, "Save Sound Effects", _save_sfx_profiles)
	sfx_status_label = Label.new()
	sfx_status_label.text = "Choose an event. Empty variants are allowed until audio is assigned."
	sfx_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(sfx_status_label)

	sfx_audio_dialog = FileDialog.new()
	sfx_audio_dialog.access = FileDialog.ACCESS_RESOURCES
	sfx_audio_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	sfx_audio_dialog.filters = PackedStringArray([
		"*.wav ; WAV Audio",
		"*.ogg ; OGG Audio",
		"*.mp3 ; MP3 Audio",
	])
	sfx_audio_dialog.files_selected.connect(_on_sfx_files_selected)
	sfx_window.add_child(sfx_audio_dialog)
	sfx_preview_player = AudioStreamPlayer.new()
	sfx_preview_player.bus = "Master"
	sfx_window.add_child(sfx_preview_player)


func _open_sfx_editor() -> void:
	_load_sfx_profiles()
	sfx_window.popup_centered()


func _load_sfx_profiles() -> void:
	sfx_profiles = {}
	if FileAccess.file_exists(SFX_DATA_PATH):
		var file := FileAccess.open(SFX_DATA_PATH, FileAccess.READ)
		if file != null:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
				sfx_profiles = json.data
	_refresh_sfx_profile_list()


func _refresh_sfx_profile_list() -> void:
	sfx_profile_list.clear()
	var ids := sfx_profiles.keys()
	ids.sort()
	for profile_id in ids:
		var profile: Dictionary = sfx_profiles[profile_id] if sfx_profiles[profile_id] is Dictionary else {}
		var display_name := str(profile.get("display_name", ""))
		var index := sfx_profile_list.item_count
		sfx_profile_list.add_item("%s%s" % [str(profile_id), "  ·  %s" % display_name if not display_name.is_empty() else ""])
		sfx_profile_list.set_item_metadata(index, str(profile_id))
		if str(profile_id) == sfx_selected_id:
			sfx_profile_list.select(index)
	if sfx_selected_id.is_empty() and sfx_profile_list.item_count > 0:
		sfx_profile_list.select(0)
		_on_sfx_profile_selected(0)


func _on_sfx_profile_selected(index: int) -> void:
	if index < 0 or index >= sfx_profile_list.item_count:
		return
	sfx_selected_id = str(sfx_profile_list.get_item_metadata(index))
	var profile: Dictionary = sfx_profiles.get(sfx_selected_id, {})
	(sfx_fields["id"] as LineEdit).text = sfx_selected_id
	(sfx_fields["display_name"] as LineEdit).text = str(profile.get("display_name", ""))
	(sfx_fields["stream_paths"] as TextEdit).text = "\n".join(_get_sfx_paths(profile))
	(sfx_fields["volume_db"] as SpinBox).value = float(profile.get("volume_db", 0.0))
	(sfx_fields["pitch_min"] as SpinBox).value = float(profile.get("pitch_min", 0.96))
	(sfx_fields["pitch_max"] as SpinBox).value = float(profile.get("pitch_max", 1.04))
	(sfx_fields["max_distance"] as SpinBox).value = float(profile.get("max_distance", 640.0))


func _capture_sfx_form() -> bool:
	if sfx_selected_id.is_empty():
		return false
	var clean_id := data_store.sanitize_id((sfx_fields["id"] as LineEdit).text)
	if clean_id.is_empty():
		_set_sfx_status("Event ID is required.", true)
		return false
	var paths := _parse_sfx_paths((sfx_fields["stream_paths"] as TextEdit).text)
	for path in paths:
		if not _is_supported_sfx_path(str(path)):
			_set_sfx_status("Unsupported audio path: %s" % str(path), true)
			return false
	var profile := {
		"display_name": (sfx_fields["display_name"] as LineEdit).text.strip_edges(),
		"stream_paths": paths,
		"volume_db": (sfx_fields["volume_db"] as SpinBox).value,
		"pitch_min": (sfx_fields["pitch_min"] as SpinBox).value,
		"pitch_max": (sfx_fields["pitch_max"] as SpinBox).value,
		"max_distance": (sfx_fields["max_distance"] as SpinBox).value,
		"bus": "Master",
	}
	if clean_id != sfx_selected_id:
		sfx_profiles.erase(sfx_selected_id)
	sfx_selected_id = clean_id
	sfx_profiles[clean_id] = profile
	return true


func _new_sfx_profile() -> void:
	_capture_sfx_form()
	var new_id := "new_sound_event"
	var suffix := 2
	while sfx_profiles.has(new_id):
		new_id = "new_sound_event_%d" % suffix
		suffix += 1
	sfx_profiles[new_id] = _make_default_sfx_profile("New Sound Event")
	sfx_selected_id = new_id
	_refresh_sfx_profile_list()
	_select_sfx_id(new_id)


func _duplicate_sfx_profile() -> void:
	if not _capture_sfx_form():
		return
	var base_id := "%s_copy" % sfx_selected_id
	var new_id := base_id
	var suffix := 2
	while sfx_profiles.has(new_id):
		new_id = "%s_%d" % [base_id, suffix]
		suffix += 1
	sfx_profiles[new_id] = (sfx_profiles[sfx_selected_id] as Dictionary).duplicate(true)
	sfx_profiles[new_id]["display_name"] = "%s Copy" % str(sfx_profiles[new_id].get("display_name", new_id))
	sfx_selected_id = new_id
	_refresh_sfx_profile_list()
	_select_sfx_id(new_id)


func _delete_sfx_profile() -> void:
	if sfx_selected_id.is_empty():
		return
	sfx_profiles.erase(sfx_selected_id)
	sfx_selected_id = ""
	_refresh_sfx_profile_list()


func _save_sfx_profiles() -> void:
	if not sfx_selected_id.is_empty() and not _capture_sfx_form():
		return
	var file := FileAccess.open(SFX_DATA_PATH, FileAccess.WRITE)
	if file == null:
		_set_sfx_status("Could not write %s" % SFX_DATA_PATH, true)
		return
	file.store_string(JSON.stringify(sfx_profiles, "\t") + "\n")
	var manager := get_node_or_null("/root/SFXManager")
	if manager != null and manager.has_method("reload_profiles"):
		manager.reload_profiles()
	_refresh_sfx_profile_list()
	_set_sfx_status("Saved sound effects and refreshed SFXManager.")


func _preview_sfx_profile() -> void:
	if not _capture_sfx_form():
		return
	var profile: Dictionary = sfx_profiles.get(sfx_selected_id, {})
	var paths := _get_sfx_paths(profile)
	if paths.is_empty():
		_set_sfx_status("Assign at least one audio file before previewing.", true)
		return
	var valid_paths := []
	for path in paths:
		if ResourceLoader.exists(str(path)):
			valid_paths.append(path)
	if valid_paths.is_empty():
		_set_sfx_status("None of the assigned audio files could be loaded.", true)
		return
	var stream := load(str(valid_paths[randi() % valid_paths.size()])) as AudioStream
	if stream == null:
		return
	sfx_preview_player.stop()
	sfx_preview_player.stream = stream
	sfx_preview_player.volume_db = float(profile.get("volume_db", 0.0))
	sfx_preview_player.pitch_scale = randf_range(float(profile.get("pitch_min", 0.96)), float(profile.get("pitch_max", 1.04)))
	sfx_preview_player.play()


func _browse_sfx_files() -> void:
	sfx_audio_dialog.popup_centered_ratio(0.75)


func _on_sfx_files_selected(paths: PackedStringArray) -> void:
	var clean_paths := []
	for path in paths:
		if _is_supported_sfx_path(path):
			clean_paths.append(path)
	(sfx_fields["stream_paths"] as TextEdit).text = "\n".join(clean_paths)


func _select_sfx_id(profile_id: String) -> void:
	for index in range(sfx_profile_list.item_count):
		if str(sfx_profile_list.get_item_metadata(index)) == profile_id:
			sfx_profile_list.select(index)
			_on_sfx_profile_selected(index)
			return


func _get_sfx_paths(profile: Dictionary) -> Array:
	var raw: Variant = profile.get("stream_paths", [])
	if not raw is Array:
		return []
	var result := []
	for value in raw:
		var path := str(value).strip_edges()
		if not path.is_empty():
			result.append(path)
	return result


func _parse_sfx_paths(text: String) -> Array:
	var paths := []
	for raw_line in text.split("\n", false):
		var path := str(raw_line).strip_edges()
		if not path.is_empty() and not paths.has(path):
			paths.append(path)
	return paths


func _is_supported_sfx_path(path: String) -> bool:
	var lower := path.to_lower()
	return path.begins_with("res://") and (lower.ends_with(".wav") or lower.ends_with(".ogg") or lower.ends_with(".mp3"))


func _make_default_sfx_profile(display_name: String) -> Dictionary:
	return {
		"display_name": display_name,
		"stream_paths": [],
		"volume_db": 0.0,
		"pitch_min": 0.96,
		"pitch_max": 1.04,
		"max_distance": 640.0,
		"bus": "Master",
	}


func _add_sfx_line_field(parent: VBoxContainer, label_text: String) -> LineEdit:
	var edit := LineEdit.new()
	_add_sfx_form_row(parent, label_text, edit)
	return edit


func _add_sfx_spin_field(parent: VBoxContainer, label_text: String, minimum: float, maximum: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	_add_sfx_form_row(parent, label_text, spin)
	return spin


func _add_sfx_form_row(parent: VBoxContainer, label_text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(150, 0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)


func _add_sfx_button(parent: Container, text_value: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text_value
	button.pressed.connect(callback)
	parent.add_child(button)


func _set_sfx_status(text_value: String, is_error := false) -> void:
	if sfx_status_label == null:
		return
	sfx_status_label.text = text_value
	sfx_status_label.modulate = Color(1.0, 0.45, 0.45) if is_error else Color.WHITE
