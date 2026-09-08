extends SceneTree
const Studio := preload("res://scenes/labs/alabaster/AlabasterBoneStudio.tscn")
const Library := preload("res://scripts/labs/alabaster/AlabasterBoneAnimationLibrary.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var studio := Studio.instantiate()
	root.add_child(studio)
	for i in range(8):
		await process_frame
	_check(studio.get_editor_preview_profile_id() == "juno", "Default remains Juno")
	_check(studio.get_editor_preview_profiles() == ["juno","juno_base","male_dummy","default","wayfarer","mooncloak"], "All six editor profiles")
	var selector: OptionButton = studio.get("_editor_preview_option")
	_check(selector.item_count == 6 and selector.get_item_metadata(5) == "mooncloak", "Mooncloak selector item")
	selector.item_selected.emit(5)
	_check_mooncloak(studio)
	studio.rig.set_animation("run")
	studio.rig.animation_time = 0.12
	_check(studio.set_editor_preview_profile("juno_base"), "Return to JunoBase")
	_check(studio.rig.current_animation == "run", "Animation retained on return")
	_check(studio.set_editor_preview_profile("mooncloak"), "Return to Mooncloak")
	_check(studio.rig.current_animation == "run", "Animation retained on Mooncloak")
	var panel: Control = studio.get("_live_tuning_panel")
	var buttons: Dictionary = panel.get("target_buttons")
	_check(buttons.has("mooncloak"), "Live Tuning button")
	for profile in ["mooncloak", "default", "juno", "mooncloak"]:
		(buttons[profile] as Button).pressed.emit()
		_check(studio.get_editor_preview_profile_id() == profile, "Live/editor sync " + profile)
		_check(str(panel.get("target_profile")) == profile, "Live target " + profile)
		if profile == "mooncloak":
			_check_mooncloak(studio)
		elif profile == "default":
			_check(str(studio.rig.get("skin_profile_id")) == "default", "Default rig restored")
	_check(Library.VALID_PROFILES.has("mooncloak"), "Custom save namespace accepted")
	_check(Library.load_builtin_animations("mooncloak").size() == 16, "16 built-in animations")
	_check(Library.is_read_only_animation("mooncloak","idle"), "Native idle protected")
	_check(panel.call("_record_passes_filter", "mooncloak", "custom", "MOONCLOAK"), "Custom filter accepts Mooncloak")
	_check(not panel.call("_record_passes_filter", "juno", "custom", "MOONCLOAK"), "Custom filter isolates Juno")
	for i in range(5):
		await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/characters/mooncloak/bone-studio-mooncloak.png")
		var tabs := panel.get_parent() as TabContainer
		tabs.current_tab = tabs.get_tab_idx_from_control(panel)
		for i in range(5):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/characters/mooncloak/bone-studio-mooncloak-live.png")
	var report := {"failures":failures,"profiles":studio.get_editor_preview_profiles(),"selected":studio.get_editor_preview_profile_id(),"mooncloak_builtin_count":Library.load_builtin_animations("mooncloak").size()}
	FileAccess.open("res://docs/characters/mooncloak/bone-studio-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("MOONCLOAK_BONE_STUDIO_VALIDATION ", JSON.stringify(report))
	studio.queue_free()
	quit(0 if failures.is_empty() else 1)

func _check_mooncloak(studio: Node) -> void:
	var rig: Node2D = studio.get("rig")
	_check(rig.get_script().resource_path == "res://scripts/labs/alabaster/MooncloakRig.gd", "Mooncloak rig class")
	_check(rig.call("has_animation", "idle") and rig.call("has_animation", "run"), "Mooncloak animations available")
	var texture: Texture2D = rig.get("_atlas")
	var expected := Image.new()
	expected.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/sprites/characters/MOONCLOAK.png"))
	_check(texture.get_image().get_data() == expected.get_data(), "Mooncloak atlas pixels")
	_check(rig.call("get_runtime_summary").get("profile") == "mooncloak", "Mooncloak profile identity")

func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
