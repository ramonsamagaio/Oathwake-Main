extends SceneTree

const CONTENT_EDITOR_SCENE := "res://tools/content_editor/ContentEditor.tscn"
const ARTIFACT_DIR := "res://test_artifacts/content_editor"
const SOUND_SECTION := "__sound_effects"
const EFFECT_SECTION := "__scene_shader_effects"
const AUDIO_MIX_RECORD := "__audio_mix"
const SAMPLE_SOUND_EVENT := "player_dash"
const EFFECT_IDS := ["outline", "foliage", "glow", "fog"]

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene := load(CONTENT_EDITOR_SCENE) as PackedScene
	if packed_scene == null:
		_fail("Could not load ContentEditor.tscn")
		_finish()
		return
	var editor := packed_scene.instantiate()
	root.add_child(editor)
	for _frame in range(12):
		await process_frame

	_validate_no_visible_popup_windows(editor, "initial")
	editor.call("_open_sfx_editor")
	for _frame in range(8):
		await process_frame
	_expect(str(editor.get("current_section")) == SOUND_SECTION, "Sound Effects did not select the integrated main section.")
	_validate_no_visible_popup_windows(editor, "sound effects")
	editor.call("_load_integrated_record", AUDIO_MIX_RECORD)
	for _frame in range(4):
		await process_frame
	var mix_fields: Dictionary = editor.get("audio_mix_fields")
	_expect(mix_fields.size() >= 5, "Global Audio Mixer did not expose all expected volume controls.")
	_expect(mix_fields.has("overworld_volume_db"), "Overworld volume control is missing.")
	_expect(mix_fields.has("ambience_volume_db"), "Ambience volume control is missing.")
	_capture_root("sound_audio_mixer")

	editor.call("_load_integrated_record", SAMPLE_SOUND_EVENT)
	for _frame in range(4):
		await process_frame
	var sfx_fields: Dictionary = editor.get("sfx_fields")
	_expect(sfx_fields.has("volume_db"), "Gameplay sound event volume control is missing.")
	_expect(sfx_fields.has("pitch_min") and sfx_fields.has("pitch_max"), "Gameplay sound event pitch controls are missing.")
	_expect(sfx_fields.has("max_distance"), "Gameplay sound event distance control is missing.")
	_capture_root("sound_event_player_dash")
	_validate_no_visible_popup_windows(editor, "gameplay sound event")

	editor.call("_open_scene_shader_editor")
	for _frame in range(8):
		await process_frame
	_expect(str(editor.get("current_section")) == EFFECT_SECTION, "Scene Shader Effects did not select the integrated main section.")
	_validate_no_visible_popup_windows(editor, "scene effects")

	for effect_id in EFFECT_IDS:
		editor.call("_load_integrated_record", effect_id)
		for _frame in range(24):
			await process_frame
		var preview = editor.get("effect_preview")
		_expect(preview != null, "%s did not create a live preview." % effect_id)
		if preview != null:
			_expect(str(preview.get("_mode")) == effect_id, "%s preview opened with the wrong mode." % effect_id)
			var preview_viewport := preview.get("_viewport") as SubViewport
			if preview_viewport == null:
				_fail("%s preview has no SubViewport." % effect_id)
			else:
				var preview_image := preview_viewport.get_texture().get_image()
				_validate_preview_image(effect_id, preview_image)
				_save_image(preview_image, "%s_preview" % effect_id)
		_capture_root("scene_effect_%s" % effect_id)
		_validate_no_visible_popup_windows(editor, effect_id)

	_finish()


func _validate_no_visible_popup_windows(editor: Node, context: String) -> void:
	for node in editor.find_children("*", "Window", true, false):
		if node is Window and (node as Window).visible:
			_fail("Visible floating Window '%s' found during %s." % [node.name, context])


func _validate_preview_image(effect_id: String, image: Image) -> void:
	if image == null or image.is_empty() or image.get_width() <= 0 or image.get_height() <= 0:
		_fail("%s preview image is empty." % effect_id)
		return
	var minimum_luma := 1.0
	var maximum_luma := 0.0
	var opaque_pixels := 0
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var color := image.get_pixel(x, y)
			var luma := color.get_luminance()
			minimum_luma = minf(minimum_luma, luma)
			maximum_luma = maxf(maximum_luma, luma)
			if color.a > 0.05:
				opaque_pixels += 1
	_expect(opaque_pixels > 100, "%s preview rendered too few visible pixels." % effect_id)
	_expect(maximum_luma - minimum_luma > 0.08, "%s preview appears visually flat or blank." % effect_id)


func _capture_root(file_name: String) -> void:
	var image := root.get_texture().get_image()
	_save_image(image, file_name)


func _save_image(image: Image, file_name: String) -> void:
	if image == null or image.is_empty():
		return
	var absolute_dir := ProjectSettings.globalize_path(ARTIFACT_DIR)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	image.save_png("%s/%s.png" % [ARTIFACT_DIR, file_name])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("INTEGRATED_CONTENT_EDITOR_FAILURE: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("INTEGRATED_CONTENT_EDITOR_PASS")
		quit(0)
		return
	for failure in _failures:
		print("INTEGRATED_CONTENT_EDITOR_FAILURE: %s" % failure)
	quit(1)
