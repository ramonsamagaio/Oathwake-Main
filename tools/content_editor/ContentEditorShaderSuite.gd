extends "res://tools/content_editor/ContentEditorEnhanced.gd"

const ShaderContentEditorData := preload("res://tools/content_editor/ContentEditorData.gd")
const EffectPreviewPanelScript := preload("res://tools/content_editor/EffectPreviewPanel.gd")

const SECTION_SOUND_EFFECTS := "__sound_effects"
const SECTION_SCENE_EFFECTS := "__scene_shader_effects"
const AUDIO_MIX_RECORD_ID := "__audio_mix"
const AUDIO_MIX_PATH := "res://data/audio_mix.json"
const OUTLINE_SETTINGS_PATH := "res://scenes/effects/settings/WorldItemOutlineSettings.tscn"
const FOLIAGE_SETTINGS_PATH := "res://scenes/effects/settings/FoliageWindSettings.tscn"
const SCREEN_SETTINGS_PATH := "res://scenes/effects/settings/ScreenEffectsSettings.tscn"
const FOG_SETTINGS_PATH := "res://scenes/effects/MapFogOverlay.tscn"
const OVERWORLD_THEME_PATH := "res://assets/audio/themes/OVERWORLD THEME 01.mp3"
const FOREST_AMBIENCE_PATH := "res://assets/audio/ambience/Forest Day.wav"
const DEFAULT_AUDIO_MIX := {
	"master_volume_db": 0.0,
	"sfx_volume_db": 0.0,
	"overworld_volume_db": -8.0,
	"ambience_volume_db": -22.0,
	"ambience_inactive_volume_db": -80.0,
}
const EFFECT_RECORDS := [
	{"id": "outline", "label": "World Item Outline"},
	{"id": "foliage", "label": "Foliage Wind"},
	{"id": "glow", "label": "Gaussian Glow"},
	{"id": "fog", "label": "Map Fog"},
]

var shader_fields: Dictionary = {}
var shader_status_label: Label
var effect_preview: EffectPreviewPanel
var foliage_resource_picker: OptionButton
var foliage_large_list: ItemList
var foliage_small_list: ItemList
var foliage_large_ids: Array[String] = []
var foliage_small_ids: Array[String] = []
var outline_settings_node: Node
var foliage_settings_node: Node
var screen_settings_node: Node
var fog_settings_node: Node
var audio_mix: Dictionary = DEFAULT_AUDIO_MIX.duplicate(true)
var audio_mix_fields: Dictionary = {}


func _ready() -> void:
	super._ready()
	call_deferred("_install_integrated_sections")


# ContentEditorEnhanced calls this after installing its sidebar button. Keeping it
# intentionally empty prevents the former floating Sound FX window from existing.
func _build_sfx_window() -> void:
	pass


func _install_integrated_sections() -> void:
	var sidebar := get_node_or_null("MarginContainer/MainLayout/Sidebar") as VBoxContainer
	if sidebar == null:
		push_warning("ContentEditorShaderSuite could not find the main sidebar.")
		return

	var sound_button := sidebar.get_node_or_null("SoundEffectsButton") as Button
	if sound_button != null:
		sound_button.toggle_mode = true
		sound_button.tooltip_text = "Edit the global mixer and gameplay sound events inside the main Content Editor."
		sidebar_buttons[SECTION_SOUND_EFFECTS] = sound_button

	var shader_button := sidebar.get_node_or_null("SceneShaderEffectsButton") as Button
	if shader_button == null:
		shader_button = Button.new()
		shader_button.name = "SceneShaderEffectsButton"
		shader_button.text = "Scene Shader Effects"
		shader_button.toggle_mode = true
		shader_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shader_button.tooltip_text = "Edit outline, vegetation wind, Gaussian glow and map fog with live previews."
		shader_button.pressed.connect(_open_scene_shader_editor)
		sidebar.add_child(shader_button)
	else:
		shader_button.toggle_mode = true
	sidebar_buttons[SECTION_SCENE_EFFECTS] = shader_button

	_ensure_integrated_audio_nodes()
	_sync_sidebar_buttons()


func _ensure_integrated_audio_nodes() -> void:
	if sfx_audio_dialog == null:
		sfx_audio_dialog = FileDialog.new()
		sfx_audio_dialog.name = "IntegratedSFXAudioDialog"
		sfx_audio_dialog.access = FileDialog.ACCESS_RESOURCES
		sfx_audio_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
		sfx_audio_dialog.filters = PackedStringArray([
			"*.wav ; WAV Audio",
			"*.ogg ; OGG Audio",
			"*.mp3 ; MP3 Audio",
		])
		sfx_audio_dialog.files_selected.connect(_on_sfx_files_selected)
		add_child(sfx_audio_dialog)
	if sfx_preview_player == null:
		sfx_preview_player = AudioStreamPlayer.new()
		sfx_preview_player.name = "IntegratedAudioPreviewPlayer"
		sfx_preview_player.bus = "Master"
		add_child(sfx_preview_player)


func _open_sfx_editor() -> void:
	_select_integrated_section(SECTION_SOUND_EFFECTS)


func _open_scene_shader_editor() -> void:
	_select_integrated_section(SECTION_SCENE_EFFECTS)


func _select_integrated_section(section_id: String) -> void:
	if current_section != section_id and has_unsaved_changes:
		_set_status("Save or Revert before changing section.", true)
		_sync_sidebar_buttons()
		return

	current_section = section_id
	current_id = ""
	current_original_id = ""
	current_record = {}
	has_unsaved_changes = false
	is_refreshing_list = true
	search_line_edit.text = ""
	is_refreshing_list = false
	sprite_category_filter_button.visible = false
	_sync_sidebar_buttons()

	if section_id == SECTION_SOUND_EFFECTS:
		section_title_label.text = "Sound Effects"
		current_file_label.text = "Files: %s + %s" % [SFX_DATA_PATH, AUDIO_MIX_PATH]
		sfx_profile_list = record_list
		_load_audio_mix()
		_load_sfx_profiles()
	else:
		section_title_label.text = "Scene Shader Effects"
		current_file_label.text = "Files: real .tscn scene settings"
		_load_scene_shader_settings()
		_refresh_effect_record_list()

	_select_first_integrated_record()
	_update_action_buttons()
	_set_status("Selected %s." % section_title_label.text)


func _select_first_integrated_record() -> void:
	if record_list.item_count <= 0:
		_show_integrated_empty_form()
		return
	var target_index := 0
	if not current_id.is_empty():
		for index in range(record_list.item_count):
			if str(record_list.get_item_metadata(index)) == current_id:
				target_index = index
				break
	record_list.select(target_index)
	_load_integrated_record(str(record_list.get_item_metadata(target_index)))


func _on_search_text_changed(new_text: String) -> void:
	if is_refreshing_list:
		return
	if _is_integrated_section():
		if current_section == SECTION_SOUND_EFFECTS:
			_refresh_sfx_profile_list()
		else:
			_refresh_effect_record_list()
		return
	super._on_search_text_changed(new_text)


func _refresh_record_list() -> void:
	if current_section == SECTION_SOUND_EFFECTS:
		_refresh_sfx_profile_list()
		return
	if current_section == SECTION_SCENE_EFFECTS:
		_refresh_effect_record_list()
		return
	super._refresh_record_list()


func _on_record_selected(index: int) -> void:
	if not _is_integrated_section():
		super._on_record_selected(index)
		return
	if is_refreshing_list or index < 0 or index >= record_list.item_count:
		return
	var selected_id := str(record_list.get_item_metadata(index))
	if has_unsaved_changes and selected_id != current_id:
		_set_status("Save or Revert before changing record.", true)
		_select_current_record_in_list()
		return
	_load_integrated_record(selected_id)


func _load_integrated_record(record_id: String) -> void:
	current_id = record_id
	current_original_id = record_id
	has_unsaved_changes = false
	if current_section == SECTION_SOUND_EFFECTS:
		sfx_selected_id = record_id
		_build_integrated_sound_form()
	else:
		_build_integrated_effect_form(record_id)
	current_record = {"id": record_id}
	_update_action_buttons()
	_select_current_record_in_list()


func _build_form_for_current_record() -> void:
	if current_section == SECTION_SOUND_EFFECTS:
		_build_integrated_sound_form()
		return
	if current_section == SECTION_SCENE_EFFECTS:
		_build_integrated_effect_form(current_id)
		return
	super._build_form_for_current_record()


func _show_empty_form() -> void:
	if _is_integrated_section():
		_show_integrated_empty_form()
		return
	super._show_empty_form()


func _show_integrated_empty_form() -> void:
	_clear_form()
	form_title_label.text = "No settings selected"
	var note := Label.new()
	note.text = "Choose a section entry from the list."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(note)


func _is_integrated_section() -> bool:
	return current_section == SECTION_SOUND_EFFECTS or current_section == SECTION_SCENE_EFFECTS


func _refresh_sfx_profile_list() -> void:
	if record_list == null:
		return
	is_refreshing_list = true
	record_list.clear()
	var query := search_line_edit.text.strip_edges().to_lower()
	if query.is_empty() or "global audio mixer master music ambience volumes".contains(query):
		var mix_index := record_list.item_count
		record_list.add_item("Global Audio Mixer")
		record_list.set_item_metadata(mix_index, AUDIO_MIX_RECORD_ID)

	var ids := sfx_profiles.keys()
	ids.sort()
	for profile_id_value in ids:
		var profile_id := str(profile_id_value)
		var profile: Dictionary = sfx_profiles[profile_id] if sfx_profiles[profile_id] is Dictionary else {}
		var display_name := str(profile.get("display_name", ""))
		var searchable := "%s %s" % [profile_id, display_name]
		if not query.is_empty() and not searchable.to_lower().contains(query):
			continue
		var index := record_list.item_count
		record_list.add_item("%s%s" % [profile_id, "  ·  %s" % display_name if not display_name.is_empty() else ""])
		record_list.set_item_metadata(index, profile_id)
		if profile_id == sfx_selected_id:
			record_list.select(index)
	is_refreshing_list = false
	_select_current_record_in_list()


func _refresh_effect_record_list() -> void:
	is_refreshing_list = true
	record_list.clear()
	var query := search_line_edit.text.strip_edges().to_lower()
	for entry in EFFECT_RECORDS:
		var record_id := str(entry.get("id", ""))
		var label := str(entry.get("label", record_id))
		if not query.is_empty() and not (record_id + " " + label).to_lower().contains(query):
			continue
		var index := record_list.item_count
		record_list.add_item(label)
		record_list.set_item_metadata(index, record_id)
	is_refreshing_list = false
	_select_current_record_in_list()


func _build_integrated_sound_form() -> void:
	_clear_form()
	sfx_fields.clear()
	audio_mix_fields.clear()
	effect_preview = null
	if sfx_selected_id == AUDIO_MIX_RECORD_ID:
		_build_audio_mix_form()
	else:
		_build_gameplay_sfx_form()


func _build_audio_mix_form() -> void:
	form_title_label.text = "Sound Effects: Global Audio Mixer"
	current_file_label.text = "File: %s" % AUDIO_MIX_PATH
	_add_section_heading(form_container, "Global Volume Controls")
	_add_note(form_container, "These values affect the actual runtime music, ambience and gameplay SFX. Event-specific volume remains editable in each sound event below.")

	audio_mix_fields["master_volume_db"] = _add_integrated_spin(form_container, "Master Volume dB", -80.0, 24.0, 0.5, float(audio_mix.get("master_volume_db", 0.0)), _on_audio_mix_field_changed)
	audio_mix_fields["sfx_volume_db"] = _add_integrated_spin(form_container, "All Gameplay SFX dB", -80.0, 24.0, 0.5, float(audio_mix.get("sfx_volume_db", 0.0)), _on_audio_mix_field_changed)
	audio_mix_fields["overworld_volume_db"] = _add_integrated_spin(form_container, "Overworld Theme dB", -80.0, 24.0, 0.5, float(audio_mix.get("overworld_volume_db", -8.0)), _on_audio_mix_field_changed)
	audio_mix_fields["ambience_volume_db"] = _add_integrated_spin(form_container, "Forest Ambience Active dB", -80.0, 24.0, 0.5, float(audio_mix.get("ambience_volume_db", -22.0)), _on_audio_mix_field_changed)
	audio_mix_fields["ambience_inactive_volume_db"] = _add_integrated_spin(form_container, "Ambience Inactive dB", -80.0, 24.0, 0.5, float(audio_mix.get("ambience_inactive_volume_db", -80.0)), _on_audio_mix_field_changed)

	_add_section_heading(form_container, "Preview")
	var preview_row := HBoxContainer.new()
	form_container.add_child(preview_row)
	_add_button(preview_row, "Preview Overworld Theme", Callable(self, "_preview_mix_stream").bind(OVERWORLD_THEME_PATH, "overworld_volume_db"))
	_add_button(preview_row, "Preview Forest Ambience", Callable(self, "_preview_mix_stream").bind(FOREST_AMBIENCE_PATH, "ambience_volume_db"))
	_add_button(preview_row, "Stop Preview", _stop_audio_preview)
	_add_note(form_container, "The preview uses the current unsaved values. Save commits them to data/audio_mix.json.")
	_create_sfx_status_label("Adjust the mixer or select a gameplay event from the list.")


func _build_gameplay_sfx_form() -> void:
	var profile: Dictionary = sfx_profiles.get(sfx_selected_id, {})
	form_title_label.text = "Sound Event: %s" % sfx_selected_id
	current_file_label.text = "File: %s" % SFX_DATA_PATH
	sfx_fields["id"] = _add_sfx_line_field(form_container, "Event ID")
	sfx_fields["display_name"] = _add_sfx_line_field(form_container, "Display Name")
	var paths_edit := TextEdit.new()
	paths_edit.custom_minimum_size = Vector2(0, 150)
	paths_edit.placeholder_text = "One res:// audio path per line"
	_add_sfx_form_row(form_container, "Audio Variants", paths_edit)
	sfx_fields["stream_paths"] = paths_edit
	var browse_button := Button.new()
	browse_button.text = "Choose Audio Files"
	browse_button.pressed.connect(_browse_sfx_files)
	form_container.add_child(browse_button)
	sfx_fields["volume_db"] = _add_sfx_spin_field(form_container, "Event Volume dB", -80.0, 24.0, 0.5)
	sfx_fields["pitch_min"] = _add_sfx_spin_field(form_container, "Pitch Min", 0.1, 4.0, 0.01)
	sfx_fields["pitch_max"] = _add_sfx_spin_field(form_container, "Pitch Max", 0.1, 4.0, 0.01)
	sfx_fields["max_distance"] = _add_sfx_spin_field(form_container, "Max Distance", 0.0, 10000.0, 10.0)

	(sfx_fields["id"] as LineEdit).text = sfx_selected_id
	(sfx_fields["display_name"] as LineEdit).text = str(profile.get("display_name", ""))
	(sfx_fields["stream_paths"] as TextEdit).text = "\n".join(_get_sfx_paths(profile))
	(sfx_fields["volume_db"] as SpinBox).value = float(profile.get("volume_db", 0.0))
	(sfx_fields["pitch_min"] as SpinBox).value = float(profile.get("pitch_min", 0.96))
	(sfx_fields["pitch_max"] as SpinBox).value = float(profile.get("pitch_max", 1.04))
	(sfx_fields["max_distance"] as SpinBox).value = float(profile.get("max_distance", 640.0))
	_connect_sfx_form_dirty_signals()

	var action_row := HBoxContainer.new()
	form_container.add_child(action_row)
	_add_button(action_row, "Preview Event", _preview_sfx_profile)
	_add_button(action_row, "Stop Preview", _stop_audio_preview)
	_add_note(form_container, "Final event volume = Event Volume dB + All Gameplay SFX dB. Master Volume is then applied by the Master bus.")
	_create_sfx_status_label("Edit the event and use the main Save button below.")


func _create_sfx_status_label(initial_text: String) -> void:
	sfx_status_label = Label.new()
	sfx_status_label.text = initial_text
	sfx_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(sfx_status_label)


func _on_sfx_profile_selected(index: int) -> void:
	if index < 0 or index >= record_list.item_count:
		return
	_load_integrated_record(str(record_list.get_item_metadata(index)))


func _capture_sfx_form() -> bool:
	if sfx_selected_id == AUDIO_MIX_RECORD_ID:
		_capture_audio_mix_fields()
		return true
	return super._capture_sfx_form()


func _capture_audio_mix_fields() -> void:
	for key in DEFAULT_AUDIO_MIX.keys():
		if audio_mix_fields.has(key):
			audio_mix[key] = (audio_mix_fields[key] as SpinBox).value


func _load_audio_mix() -> void:
	audio_mix = DEFAULT_AUDIO_MIX.duplicate(true)
	if not FileAccess.file_exists(AUDIO_MIX_PATH):
		return
	var file := FileAccess.open(AUDIO_MIX_PATH, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return
	for key in DEFAULT_AUDIO_MIX.keys():
		if json.data.has(key):
			audio_mix[key] = float(json.data[key])
	_apply_live_master_volume()


func _save_sfx_profiles() -> void:
	if not sfx_selected_id.is_empty() and not _capture_sfx_form():
		return
	var profiles_file := FileAccess.open(SFX_DATA_PATH, FileAccess.WRITE)
	if profiles_file == null:
		_set_sfx_status("Could not write %s" % SFX_DATA_PATH, true)
		return
	profiles_file.store_string(JSON.stringify(sfx_profiles, "\t") + "\n")
	var mix_file := FileAccess.open(AUDIO_MIX_PATH, FileAccess.WRITE)
	if mix_file == null:
		_set_sfx_status("Could not write %s" % AUDIO_MIX_PATH, true)
		return
	mix_file.store_string(JSON.stringify(audio_mix, "\t") + "\n")
	var manager := get_node_or_null("/root/SFXManager")
	if manager != null and manager.has_method("reload_profiles"):
		manager.reload_profiles()
	has_unsaved_changes = false
	_refresh_sfx_profile_list()
	_update_action_buttons()
	_set_sfx_status("Saved gameplay events and the global audio mixer.")
	_set_status("Saved Sound Effects settings.")


func _preview_sfx_profile() -> void:
	if not _capture_sfx_form() or sfx_selected_id == AUDIO_MIX_RECORD_ID:
		return
	var profile: Dictionary = sfx_profiles.get(sfx_selected_id, {})
	var paths := _get_sfx_paths(profile)
	var valid_paths := []
	for path_value in paths:
		if ResourceLoader.exists(str(path_value)):
			valid_paths.append(str(path_value))
	if valid_paths.is_empty():
		_set_sfx_status("Assign at least one valid audio file before previewing.", true)
		return
	var stream := load(str(valid_paths[randi() % valid_paths.size()])) as AudioStream
	if stream == null:
		return
	var pitch_min := float(profile.get("pitch_min", 0.96))
	var pitch_max := float(profile.get("pitch_max", 1.04))
	if pitch_max < pitch_min:
		var swap := pitch_min
		pitch_min = pitch_max
		pitch_max = swap
	sfx_preview_player.stop()
	sfx_preview_player.stream = stream
	sfx_preview_player.volume_db = float(profile.get("volume_db", 0.0)) + float(audio_mix.get("sfx_volume_db", 0.0))
	sfx_preview_player.pitch_scale = randf_range(pitch_min, pitch_max)
	sfx_preview_player.play()


func _preview_mix_stream(path: String, volume_key: String) -> void:
	_capture_audio_mix_fields()
	if not ResourceLoader.exists(path):
		_set_sfx_status("Audio preview file not found: %s" % path, true)
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	sfx_preview_player.stop()
	sfx_preview_player.stream = stream
	sfx_preview_player.pitch_scale = 1.0
	sfx_preview_player.volume_db = float(audio_mix.get(volume_key, 0.0))
	sfx_preview_player.play()


func _stop_audio_preview() -> void:
	if sfx_preview_player != null:
		sfx_preview_player.stop()


func _on_audio_mix_field_changed(_value: float) -> void:
	_capture_audio_mix_fields()
	_apply_live_master_volume()
	_mark_integrated_dirty()


func _apply_live_master_volume() -> void:
	var bus_index := AudioServer.get_bus_index("Master")
	if bus_index >= 0:
		AudioServer.set_bus_volume_db(bus_index, float(audio_mix.get("master_volume_db", 0.0)))


func _connect_sfx_form_dirty_signals() -> void:
	for control in sfx_fields.values():
		if control is LineEdit:
			(control as LineEdit).text_changed.connect(func(_text: String) -> void: _mark_integrated_dirty())
		elif control is TextEdit:
			(control as TextEdit).text_changed.connect(_mark_integrated_dirty)
		elif control is SpinBox:
			(control as SpinBox).value_changed.connect(func(_value: float) -> void: _mark_integrated_dirty())


func _load_scene_shader_settings() -> void:
	_free_loaded_settings_nodes()
	outline_settings_node = _instantiate_settings_scene(OUTLINE_SETTINGS_PATH)
	foliage_settings_node = _instantiate_settings_scene(FOLIAGE_SETTINGS_PATH)
	screen_settings_node = _instantiate_settings_scene(SCREEN_SETTINGS_PATH)
	fog_settings_node = _instantiate_settings_scene(FOG_SETTINGS_PATH)
	if outline_settings_node == null or foliage_settings_node == null or screen_settings_node == null or fog_settings_node == null:
		_set_status("Could not load one or more shader settings scenes.", true)
		return
	foliage_large_ids = _packed_string_array_to_array(foliage_settings_node.get("large_resource_ids"))
	foliage_small_ids = _packed_string_array_to_array(foliage_settings_node.get("small_resource_ids"))


func _instantiate_settings_scene(path: String) -> Node:
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not resource is PackedScene:
		return null
	return (resource as PackedScene).instantiate()


func _build_integrated_effect_form(effect_id: String) -> void:
	_clear_form()
	shader_fields.clear()
	effect_preview = null
	shader_status_label = null
	foliage_resource_picker = null
	foliage_large_list = null
	foliage_small_list = null
	current_file_label.text = "Scene settings: %s" % _get_effect_settings_path(effect_id)
	match effect_id:
		"outline":
			_build_outline_form()
		"foliage":
			_build_foliage_form()
		"glow":
			_build_glow_form()
		"fog":
			_build_fog_form()
		_:
			_show_integrated_empty_form()


func _build_outline_form() -> void:
	form_title_label.text = "Scene Shader Effects: World Item Outline"
	_add_effect_preview("outline", "Live Preview · Dropped Item")
	_add_note(form_container, "Uses the real world_item_outline.gdshader. The preview also includes the ground shadow used by world drops.")
	shader_fields["outline_enabled"] = _add_shader_check(form_container, "Enabled", bool(outline_settings_node.get("effect_enabled")))
	shader_fields["outline_color"] = _add_shader_color(form_container, "Line Color", outline_settings_node.get("outline_color"))
	shader_fields["outline_size"] = _add_shader_spin(form_container, "Line Thickness", 0.0, 0.2, 0.001, float(outline_settings_node.get("outline_size")))
	shader_fields["outline_alpha_threshold"] = _add_shader_spin(form_container, "Alpha Threshold", 0.0, 1.0, 0.05, float(outline_settings_node.get("alpha_threshold")))
	shader_fields["outline_samples"] = _add_shader_spin(form_container, "Corner Samples", 4.0, 32.0, 1.0, int(outline_settings_node.get("samples")))
	_connect_shader_fields()
	_update_effect_preview()
	_create_shader_status_label("Changes update the item preview immediately.")


func _build_foliage_form() -> void:
	form_title_label.text = "Scene Shader Effects: Foliage Wind"
	_add_effect_preview("foliage", "Live Preview · Large Tree")
	_add_note(form_container, "The tree crown uses the real foliage_wind_2d.gdshader. The trunk remains fixed so the pivot behavior is easy to judge.")
	shader_fields["foliage_enabled"] = _add_shader_check(form_container, "Enabled", bool(foliage_settings_node.get("effect_enabled")))
	_add_section_heading(form_container, "Shared Wind")
	shader_fields["foliage_time_scale"] = _add_shader_spin(form_container, "Wind Speed", 0.0, 5.0, 0.01, float(foliage_settings_node.get("time_scale")))
	shader_fields["foliage_noise_scale"] = _add_shader_spin(form_container, "World Noise Scale", 0.0001, 2.0, 0.0001, float(foliage_settings_node.get("noise_scale")))
	shader_fields["foliage_render_noise"] = _add_shader_check(form_container, "Render Noise Debug", bool(foliage_settings_node.get("render_noise_debug")))
	_add_section_heading(form_container, "Large Vegetation")
	shader_fields["foliage_large_amplitude"] = _add_shader_spin(form_container, "Large Intensity", 0.0, 0.5, 0.005, float(foliage_settings_node.get("large_amplitude")))
	shader_fields["foliage_large_rotation"] = _add_shader_spin(form_container, "Large Rotation Strength", 0.0, 5.0, 0.05, float(foliage_settings_node.get("large_rotation_strength")))
	var large_pivot: Vector2 = foliage_settings_node.get("large_rotation_pivot")
	shader_fields["foliage_large_pivot_x"] = _add_shader_spin(form_container, "Large Pivot X", 0.0, 1.0, 0.01, large_pivot.x)
	shader_fields["foliage_large_pivot_y"] = _add_shader_spin(form_container, "Large Pivot Y", 0.0, 1.0, 0.01, large_pivot.y)
	_add_section_heading(form_container, "Small Vegetation")
	shader_fields["foliage_small_amplitude"] = _add_shader_spin(form_container, "Small Intensity", 0.0, 0.5, 0.005, float(foliage_settings_node.get("small_amplitude")))
	shader_fields["foliage_small_rotation"] = _add_shader_spin(form_container, "Small Rotation Strength", 0.0, 5.0, 0.05, float(foliage_settings_node.get("small_rotation_strength")))
	var small_pivot: Vector2 = foliage_settings_node.get("small_rotation_pivot")
	shader_fields["foliage_small_pivot_x"] = _add_shader_spin(form_container, "Small Pivot X", 0.0, 1.0, 0.01, small_pivot.x)
	shader_fields["foliage_small_pivot_y"] = _add_shader_spin(form_container, "Small Pivot Y", 0.0, 1.0, 0.01, small_pivot.y)
	_build_foliage_assignment_editor()
	_connect_shader_fields()
	_update_effect_preview()
	_create_shader_status_label("The preview uses the Large Vegetation values.")


func _build_glow_form() -> void:
	form_title_label.text = "Scene Shader Effects: Gaussian Glow"
	_add_effect_preview("glow", "Live Preview · Player Bloom")
	_add_note(form_container, "The player and chest rune are rendered first, then the real Gaussian screen shader reads that viewport. This exposes halo radius without washing the whole scene.")
	shader_fields["glow_enabled"] = _add_shader_check(form_container, "Enabled", bool(screen_settings_node.get("glow_enabled")))
	shader_fields["glow_threshold"] = _add_shader_spin(form_container, "Bloom Threshold", 0.0, 2.0, 0.01, float(screen_settings_node.get("bloom_threshold")))
	shader_fields["glow_intensity"] = _add_shader_spin(form_container, "Bloom Intensity", 0.0, 5.0, 0.01, float(screen_settings_node.get("bloom_intensity")))
	shader_fields["glow_iterations"] = _add_shader_spin(form_container, "Blur Iterations", 1.0, 4.0, 1.0, int(screen_settings_node.get("blur_iterations")))
	shader_fields["glow_size"] = _add_shader_spin(form_container, "Blur Size", 0.0, 0.03, 0.0001, float(screen_settings_node.get("blur_size")))
	shader_fields["glow_subdivisions"] = _add_shader_spin(form_container, "Blur Subdivisions", 4.0, 16.0, 1.0, int(screen_settings_node.get("blur_subdivisions")))
	shader_fields["glow_mix"] = _add_shader_spin(form_container, "Glow Mix", 0.0, 1.0, 0.01, float(screen_settings_node.get("glow_mix_amount")))
	_connect_shader_fields()
	_update_effect_preview()
	_create_shader_status_label("Changes update the player bloom preview immediately.")


func _build_fog_form() -> void:
	form_title_label.text = "Scene Shader Effects: Map Fog"
	_add_effect_preview("fog", "Live Preview · Map Fog")
	_add_note(form_container, "Edits the base MapFogOverlay.tscn used by maps. Individual map scenes may still override these values in their Inspector.")
	shader_fields["fog_enabled"] = _add_shader_check(form_container, "Enabled", bool(fog_settings_node.get("effect_enabled")))
	shader_fields["fog_density"] = _add_shader_spin(form_container, "Density", 0.0, 1.0, 0.01, float(fog_settings_node.get("density")))
	shader_fields["fog_speed_x"] = _add_shader_spin(form_container, "Speed X", -1.0, 1.0, 0.001, (fog_settings_node.get("speed") as Vector2).x)
	shader_fields["fog_speed_y"] = _add_shader_spin(form_container, "Speed Y", -1.0, 1.0, 0.001, (fog_settings_node.get("speed") as Vector2).y)
	shader_fields["fog_color"] = _add_shader_color(form_container, "Fog Color", fog_settings_node.get("fog_color"))
	shader_fields["fog_scale"] = _add_shader_spin(form_container, "Fog Scale", 0.25, 12.0, 0.05, float(fog_settings_node.get("fog_scale")))
	shader_fields["fog_coverage"] = _add_shader_spin(form_container, "Coverage", 0.0, 1.0, 0.01, float(fog_settings_node.get("coverage")))
	shader_fields["fog_softness"] = _add_shader_spin(form_container, "Softness", 0.01, 0.75, 0.01, float(fog_settings_node.get("softness")))
	shader_fields["fog_detail_mix"] = _add_shader_spin(form_container, "Detail Mix", 0.0, 1.0, 0.01, float(fog_settings_node.get("detail_mix")))
	_connect_shader_fields()
	_update_effect_preview()
	_create_shader_status_label("Changes update the map fog preview immediately.")


func _build_foliage_assignment_editor() -> void:
	_add_section_heading(form_container, "Resource Assignment")
	foliage_resource_picker = OptionButton.new()
	_populate_foliage_resource_picker()
	_add_shader_row(form_container, "Map Resource", foliage_resource_picker)
	var add_actions := HBoxContainer.new()
	form_container.add_child(add_actions)
	_add_button(add_actions, "Add to Large", Callable(self, "_add_selected_foliage_resource").bind("large"))
	_add_button(add_actions, "Add to Small", Callable(self, "_add_selected_foliage_resource").bind("small"))
	var lists := HSplitContainer.new()
	lists.custom_minimum_size = Vector2(0, 240)
	lists.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_container.add_child(lists)
	var large_box := VBoxContainer.new()
	large_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lists.add_child(large_box)
	_add_section_heading(large_box, "Large Vegetation IDs")
	foliage_large_list = ItemList.new()
	foliage_large_list.select_mode = ItemList.SELECT_MULTI
	foliage_large_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	large_box.add_child(foliage_large_list)
	_add_button(large_box, "Remove Selected", Callable(self, "_remove_selected_foliage_resources").bind("large"))
	var small_box := VBoxContainer.new()
	small_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lists.add_child(small_box)
	_add_section_heading(small_box, "Small Vegetation IDs")
	foliage_small_list = ItemList.new()
	foliage_small_list.select_mode = ItemList.SELECT_MULTI
	foliage_small_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	small_box.add_child(foliage_small_list)
	_add_button(small_box, "Remove Selected", Callable(self, "_remove_selected_foliage_resources").bind("small"))
	_refresh_foliage_lists()


func _add_effect_preview(mode_name: String, title_text: String) -> void:
	_add_section_heading(form_container, title_text)
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_container.add_child(frame)
	effect_preview = EffectPreviewPanelScript.new() as EffectPreviewPanel
	frame.add_child(effect_preview)
	effect_preview.setup_mode(mode_name)


func _connect_shader_fields() -> void:
	for control in shader_fields.values():
		if control is CheckBox:
			(control as CheckBox).toggled.connect(func(_pressed: bool) -> void: _on_shader_field_changed())
		elif control is SpinBox:
			(control as SpinBox).value_changed.connect(func(_value: float) -> void: _on_shader_field_changed())
		elif control is ColorPickerButton:
			(control as ColorPickerButton).color_changed.connect(func(_color: Color) -> void: _on_shader_field_changed())


func _on_shader_field_changed() -> void:
	_update_effect_preview()
	_mark_integrated_dirty()


func _update_effect_preview() -> void:
	if effect_preview == null:
		return
	match current_id:
		"outline":
			effect_preview.apply_outline(_get_check("outline_enabled"), _get_color("outline_color"), _get_spin("outline_size"), _get_spin("outline_alpha_threshold"), int(_get_spin("outline_samples")))
		"foliage":
			effect_preview.apply_wind(_get_check("foliage_enabled"), _get_check("foliage_render_noise"), _get_spin("foliage_large_amplitude"), _get_spin("foliage_time_scale"), _get_spin("foliage_noise_scale"), _get_spin("foliage_large_rotation"), Vector2(_get_spin("foliage_large_pivot_x"), _get_spin("foliage_large_pivot_y")))
		"glow":
			effect_preview.apply_glow(_get_check("glow_enabled"), _get_spin("glow_threshold"), _get_spin("glow_intensity"), int(_get_spin("glow_iterations")), _get_spin("glow_size"), int(_get_spin("glow_subdivisions")), _get_spin("glow_mix"))
		"fog":
			effect_preview.apply_fog(_get_check("fog_enabled"), _get_spin("fog_density"), Vector2(_get_spin("fog_speed_x"), _get_spin("fog_speed_y")), _get_color("fog_color"), _get_spin("fog_scale"), _get_spin("fog_coverage"), _get_spin("fog_softness"), _get_spin("fog_detail_mix"))


func _save_scene_shader_settings() -> void:
	if outline_settings_node == null or foliage_settings_node == null or screen_settings_node == null or fog_settings_node == null:
		_load_scene_shader_settings()
	if outline_settings_node == null or foliage_settings_node == null or screen_settings_node == null or fog_settings_node == null:
		return
	_capture_current_effect_fields()
	var errors: Array[String] = []
	for entry in [
		{"path": OUTLINE_SETTINGS_PATH, "node": outline_settings_node},
		{"path": FOLIAGE_SETTINGS_PATH, "node": foliage_settings_node},
		{"path": SCREEN_SETTINGS_PATH, "node": screen_settings_node},
		{"path": FOG_SETTINGS_PATH, "node": fog_settings_node},
	]:
		var error := _save_settings_scene(str(entry["path"]), entry["node"])
		if not error.is_empty():
			errors.append(error)
	if not errors.is_empty():
		_set_shader_status("\n".join(errors), true)
		return
	has_unsaved_changes = false
	_update_action_buttons()
	_set_shader_status("Saved the real .tscn settings scenes.")
	_set_status("Saved Scene Shader Effects settings.")


func _capture_current_effect_fields() -> void:
	match current_id:
		"outline":
			outline_settings_node.set("effect_enabled", _get_check("outline_enabled"))
			outline_settings_node.set("outline_color", _get_color("outline_color"))
			outline_settings_node.set("outline_size", _get_spin("outline_size"))
			outline_settings_node.set("alpha_threshold", _get_spin("outline_alpha_threshold"))
			outline_settings_node.set("samples", int(_get_spin("outline_samples")))
		"foliage":
			foliage_settings_node.set("effect_enabled", _get_check("foliage_enabled"))
			foliage_settings_node.set("time_scale", _get_spin("foliage_time_scale"))
			foliage_settings_node.set("noise_scale", _get_spin("foliage_noise_scale"))
			foliage_settings_node.set("render_noise_debug", _get_check("foliage_render_noise"))
			foliage_settings_node.set("large_amplitude", _get_spin("foliage_large_amplitude"))
			foliage_settings_node.set("large_rotation_strength", _get_spin("foliage_large_rotation"))
			foliage_settings_node.set("large_rotation_pivot", Vector2(_get_spin("foliage_large_pivot_x"), _get_spin("foliage_large_pivot_y")))
			foliage_settings_node.set("small_amplitude", _get_spin("foliage_small_amplitude"))
			foliage_settings_node.set("small_rotation_strength", _get_spin("foliage_small_rotation"))
			foliage_settings_node.set("small_rotation_pivot", Vector2(_get_spin("foliage_small_pivot_x"), _get_spin("foliage_small_pivot_y")))
			foliage_settings_node.set("large_resource_ids", PackedStringArray(foliage_large_ids))
			foliage_settings_node.set("small_resource_ids", PackedStringArray(foliage_small_ids))
		"glow":
			screen_settings_node.set("glow_enabled", _get_check("glow_enabled"))
			screen_settings_node.set("bloom_threshold", _get_spin("glow_threshold"))
			screen_settings_node.set("bloom_intensity", _get_spin("glow_intensity"))
			screen_settings_node.set("blur_iterations", int(_get_spin("glow_iterations")))
			screen_settings_node.set("blur_size", _get_spin("glow_size"))
			screen_settings_node.set("blur_subdivisions", int(_get_spin("glow_subdivisions")))
			screen_settings_node.set("glow_mix_amount", _get_spin("glow_mix"))
		"fog":
			fog_settings_node.set("effect_enabled", _get_check("fog_enabled"))
			fog_settings_node.set("density", _get_spin("fog_density"))
			fog_settings_node.set("speed", Vector2(_get_spin("fog_speed_x"), _get_spin("fog_speed_y")))
			fog_settings_node.set("fog_color", _get_color("fog_color"))
			fog_settings_node.set("fog_scale", _get_spin("fog_scale"))
			fog_settings_node.set("coverage", _get_spin("fog_coverage"))
			fog_settings_node.set("softness", _get_spin("fog_softness"))
			fog_settings_node.set("detail_mix", _get_spin("fog_detail_mix"))


func _save_settings_scene(path: String, settings_node: Node) -> String:
	var packed_scene := PackedScene.new()
	var pack_error := packed_scene.pack(settings_node)
	if pack_error != OK:
		return "Could not pack %s (error %d)." % [path, pack_error]
	var save_error := ResourceSaver.save(packed_scene, path)
	if save_error != OK:
		return "Could not save %s (error %d)." % [path, save_error]
	return ""


func _get_effect_settings_path(effect_id: String) -> String:
	match effect_id:
		"outline":
			return OUTLINE_SETTINGS_PATH
		"foliage":
			return FOLIAGE_SETTINGS_PATH
		"glow":
			return SCREEN_SETTINGS_PATH
		"fog":
			return FOG_SETTINGS_PATH
	return "-"


func _populate_foliage_resource_picker() -> void:
	if foliage_resource_picker == null:
		return
	foliage_resource_picker.clear()
	var records := data_store.get_records(ShaderContentEditorData.SECTION_RESOURCES)
	var sorted_records: Array = records.duplicate()
	sorted_records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("id", "")) < str(b.get("id", "")))
	for record in sorted_records:
		var resource_id := str(record.get("id", ""))
		if resource_id.is_empty():
			continue
		var display_name := str(record.get("display_name", resource_id))
		var index := foliage_resource_picker.item_count
		foliage_resource_picker.add_item("%s - %s" % [resource_id, display_name])
		foliage_resource_picker.set_item_metadata(index, resource_id)


func _add_selected_foliage_resource(size_class: String) -> void:
	if foliage_resource_picker == null or foliage_resource_picker.selected < 0:
		return
	var resource_id := str(foliage_resource_picker.get_item_metadata(foliage_resource_picker.selected))
	if resource_id.is_empty():
		return
	foliage_large_ids.erase(resource_id)
	foliage_small_ids.erase(resource_id)
	if size_class == "large":
		foliage_large_ids.append(resource_id)
	else:
		foliage_small_ids.append(resource_id)
	foliage_large_ids.sort()
	foliage_small_ids.sort()
	_refresh_foliage_lists()
	_mark_integrated_dirty()


func _remove_selected_foliage_resources(size_class: String) -> void:
	var list := foliage_large_list if size_class == "large" else foliage_small_list
	if list == null:
		return
	var ids_to_remove: Array[String] = []
	for index in list.get_selected_items():
		ids_to_remove.append(str(list.get_item_metadata(index)))
	for resource_id in ids_to_remove:
		if size_class == "large":
			foliage_large_ids.erase(resource_id)
		else:
			foliage_small_ids.erase(resource_id)
	_refresh_foliage_lists()
	_mark_integrated_dirty()


func _refresh_foliage_lists() -> void:
	if foliage_large_list != null:
		foliage_large_list.clear()
		for resource_id in foliage_large_ids:
			var index := foliage_large_list.item_count
			foliage_large_list.add_item(_get_resource_display_label(resource_id))
			foliage_large_list.set_item_metadata(index, resource_id)
	if foliage_small_list != null:
		foliage_small_list.clear()
		for resource_id in foliage_small_ids:
			var index := foliage_small_list.item_count
			foliage_small_list.add_item(_get_resource_display_label(resource_id))
			foliage_small_list.set_item_metadata(index, resource_id)


func _get_resource_display_label(resource_id: String) -> String:
	if data_store.has_record(ShaderContentEditorData.SECTION_RESOURCES, resource_id):
		var record: Dictionary = data_store.get_record(ShaderContentEditorData.SECTION_RESOURCES, resource_id)
		return "%s - %s" % [resource_id, str(record.get("display_name", resource_id))]
	return resource_id


func _packed_string_array_to_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is PackedStringArray or value is Array:
		for entry in value:
			var text := str(entry)
			if not text.is_empty() and not result.has(text):
				result.append(text)
	result.sort()
	return result


func _free_loaded_settings_nodes() -> void:
	for node in [outline_settings_node, foliage_settings_node, screen_settings_node, fog_settings_node]:
		if node != null and is_instance_valid(node):
			node.free()
	outline_settings_node = null
	foliage_settings_node = null
	screen_settings_node = null
	fog_settings_node = null


func _on_save_pressed() -> void:
	if current_section == SECTION_SOUND_EFFECTS:
		_save_sfx_profiles()
		return
	if current_section == SECTION_SCENE_EFFECTS:
		_save_scene_shader_settings()
		return
	super._on_save_pressed()


func _on_revert_pressed() -> void:
	if current_section == SECTION_SOUND_EFFECTS:
		_load_audio_mix()
		_load_sfx_profiles()
		has_unsaved_changes = false
		_load_integrated_record(current_id if not current_id.is_empty() else AUDIO_MIX_RECORD_ID)
		_set_status("Reverted Sound Effects settings.")
		return
	if current_section == SECTION_SCENE_EFFECTS:
		var selected := current_id
		_load_scene_shader_settings()
		has_unsaved_changes = false
		_load_integrated_record(selected)
		_set_status("Reverted Scene Shader Effects settings.")
		return
	super._on_revert_pressed()


func _on_reload_current_pressed() -> void:
	if _is_integrated_section():
		_on_revert_pressed()
		return
	super._on_reload_current_pressed()


func _on_new_pressed() -> void:
	if current_section == SECTION_SOUND_EFFECTS:
		_new_sfx_profile()
		_mark_integrated_dirty()
		return
	if current_section == SECTION_SCENE_EFFECTS:
		_set_status("Scene effects use fixed settings records.", true)
		return
	super._on_new_pressed()


func _on_duplicate_pressed() -> void:
	if current_section == SECTION_SOUND_EFFECTS:
		if sfx_selected_id == AUDIO_MIX_RECORD_ID:
			_set_status("The Global Audio Mixer is a singleton.", true)
			return
		_duplicate_sfx_profile()
		_mark_integrated_dirty()
		return
	if current_section == SECTION_SCENE_EFFECTS:
		_set_status("Scene effects use fixed settings records.", true)
		return
	super._on_duplicate_pressed()


func _on_delete_pressed() -> void:
	if current_section == SECTION_SOUND_EFFECTS:
		if sfx_selected_id == AUDIO_MIX_RECORD_ID:
			_set_status("The Global Audio Mixer cannot be deleted.", true)
			return
		_delete_sfx_profile()
		has_unsaved_changes = true
		if record_list.item_count > 0:
			_select_first_integrated_record()
		_update_action_buttons()
		return
	if current_section == SECTION_SCENE_EFFECTS:
		_set_status("Scene effects use fixed settings records.", true)
		return
	super._on_delete_pressed()


func _update_action_buttons() -> void:
	if not _is_integrated_section():
		super._update_action_buttons()
		return
	var has_selection := not current_id.is_empty()
	var is_sound := current_section == SECTION_SOUND_EFFECTS
	var is_mix := current_id == AUDIO_MIX_RECORD_ID
	new_button.disabled = not is_sound or has_unsaved_changes
	duplicate_button.disabled = not is_sound or is_mix or has_unsaved_changes or not has_selection
	delete_button.disabled = not is_sound or is_mix or not has_selection
	save_button.disabled = not has_selection
	revert_button.disabled = not has_selection
	reload_current_button.disabled = not has_selection
	refresh_content_db_button.disabled = false
	if batch_static_sprite_button != null:
		batch_static_sprite_button.visible = false


func _mark_integrated_dirty() -> void:
	if is_building_form:
		return
	has_unsaved_changes = true
	_update_action_buttons()
	_set_status("Unsaved changes.")


func _add_integrated_spin(parent: VBoxContainer, label_text: String, minimum: float, maximum: float, step: float, value: float, callback: Callable) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = value
	spin.allow_greater = false
	spin.allow_lesser = false
	spin.value_changed.connect(callback)
	_add_shader_row(parent, label_text, spin)
	return spin


func _add_shader_check(parent: VBoxContainer, label_text: String, initial_value: bool) -> CheckBox:
	var check := CheckBox.new()
	check.button_pressed = initial_value
	_add_shader_row(parent, label_text, check)
	return check


func _add_shader_color(parent: VBoxContainer, label_text: String, initial_value: Color) -> ColorPickerButton:
	var picker := ColorPickerButton.new()
	picker.color = initial_value
	picker.edit_alpha = true
	_add_shader_row(parent, label_text, picker)
	return picker


func _add_shader_spin(parent: VBoxContainer, label_text: String, minimum: float, maximum: float, step: float, initial_value: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = initial_value
	spin.allow_greater = false
	spin.allow_lesser = false
	_add_shader_row(parent, label_text, spin)
	return spin


func _add_shader_row(parent: VBoxContainer, label_text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(230, 0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)


func _add_section_heading(parent: Container, text_value: String) -> void:
	var heading := Label.new()
	heading.text = text_value
	heading.add_theme_color_override("font_color", Color(0.95, 0.86, 0.62))
	parent.add_child(heading)


func _add_note(parent: Container, text_value: String) -> void:
	var note := Label.new()
	note.text = text_value
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.82, 0.82, 0.86)
	parent.add_child(note)


func _add_button(parent: Container, text_value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _create_shader_status_label(initial_text: String) -> void:
	shader_status_label = Label.new()
	shader_status_label.text = initial_text
	shader_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form_container.add_child(shader_status_label)


func _set_check(field_name: String, value: bool) -> void:
	if shader_fields.has(field_name):
		(shader_fields[field_name] as CheckBox).button_pressed = value


func _get_check(field_name: String) -> bool:
	return shader_fields.has(field_name) and (shader_fields[field_name] as CheckBox).button_pressed


func _set_color(field_name: String, value: Color) -> void:
	if shader_fields.has(field_name):
		(shader_fields[field_name] as ColorPickerButton).color = value


func _get_color(field_name: String) -> Color:
	return (shader_fields[field_name] as ColorPickerButton).color if shader_fields.has(field_name) else Color.WHITE


func _set_spin(field_name: String, value: float) -> void:
	if shader_fields.has(field_name):
		(shader_fields[field_name] as SpinBox).value = value


func _get_spin(field_name: String) -> float:
	return (shader_fields[field_name] as SpinBox).value if shader_fields.has(field_name) else 0.0


func _set_shader_status(text_value: String, is_error := false) -> void:
	if shader_status_label != null:
		shader_status_label.text = text_value
		shader_status_label.modulate = Color(1.0, 0.45, 0.45) if is_error else Color.WHITE
	_set_status(text_value, is_error)
