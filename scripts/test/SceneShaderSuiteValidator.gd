extends SceneTree

const GameScene := preload("res://scenes/game/Game.tscn")
const LegacyScene := preload("res://scenes/Main.tscn")
const PlayerScene := preload("res://scenes/Player.tscn")
const WorldItemScene := preload("res://scenes/items/WorldItem.tscn")
const TreeScene := preload("res://scenes/Tree.tscn")
const BushScene := preload("res://scenes/ResourceBush.tscn")
const StartAreaScene := preload("res://scenes/maps/StartArea.tscn")
const ContentEditorScene := preload("res://tools/content_editor/ContentEditor.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	_validate_world_item_outline()
	_validate_foliage_scenes()
	_validate_map_fog()
	_validate_player_screen_effects()
	_validate_canvas_order()
	await _validate_content_editor()

	if failures.is_empty():
		print("SCENE_SHADER_SUITE_VALIDATION: PASS")
		quit(0)
	else:
		push_error("SCENE_SHADER_SUITE_VALIDATION failures: %s" % "; ".join(failures))
		quit(1)


func _validate_world_item_outline() -> void:
	var world_item := WorldItemScene.instantiate()
	root.add_child(world_item)
	var settings := world_item.get_node_or_null("OutlineSettings")
	var outline_sprite := world_item.get_node_or_null("OutlineSprite") as Sprite2D
	_check(settings != null, "WorldItem has visible OutlineSettings scene node")
	_check(outline_sprite != null, "WorldItem has dedicated OutlineSprite node")
	if settings != null:
		_check(_has_property(settings, "effect_enabled"), "Outline settings expose enable toggle")
		_check(_has_property(settings, "outline_color"), "Outline settings expose color")
		_check(_has_property(settings, "outline_size"), "Outline settings expose thickness")
	if outline_sprite != null:
		_check(_shader_path(outline_sprite.material) == "res://shaders/world_item_outline.gdshader", "OutlineSprite uses the outline shader")
	world_item.queue_free()


func _validate_foliage_scenes() -> void:
	for entry in [
		{"label": "Tree", "scene": TreeScene},
		{"label": "ResourceBush", "scene": BushScene},
	]:
		var resource_node: Node = entry["scene"].instantiate()
		root.add_child(resource_node)
		var settings := resource_node.get_node_or_null("FoliageWindSettings")
		_check(settings != null, "%s has visible FoliageWindSettings node" % str(entry["label"]))
		_check(resource_node.has_method("_get_foliage_size_class"), "%s uses the foliage shader suite controller" % str(entry["label"]))
		if settings != null:
			_check(_has_property(settings, "large_resource_ids"), "Foliage settings expose large vegetation list")
			_check(_has_property(settings, "small_resource_ids"), "Foliage settings expose small vegetation list")
			var large_ids: PackedStringArray = settings.get("large_resource_ids")
			var small_ids: PackedStringArray = settings.get("small_resource_ids")
			_check(large_ids.has("tree") and large_ids.has("oak_tree"), "Large vegetation defaults include trees")
			_check(small_ids.has("fiber_bush") and small_ids.has("herb_bush") and small_ids.has("berry_bush"), "Small vegetation defaults include fiber, herb and berry")
		resource_node.queue_free()


func _validate_map_fog() -> void:
	var start_area := StartAreaScene.instantiate()
	root.add_child(start_area)
	var start_fog := start_area.get_node_or_null("MapFogOverlay")
	_check(start_fog != null, "StartArea contains a visible MapFogOverlay node")
	if start_fog != null:
		_check(_has_property(start_fog, "effect_enabled"), "Map fog exposes per-map enable toggle")
		_check(_has_property(start_fog, "density"), "Map fog exposes density")
		_check(_has_property(start_fog, "speed"), "Map fog exposes speed")
	start_area.queue_free()

	var legacy := LegacyScene.instantiate()
	root.add_child(legacy)
	_check(legacy.get_node_or_null("World/MapFogOverlay") != null, "Legacy authored map contains MapFogOverlay")
	legacy.queue_free()


func _validate_player_screen_effects() -> void:
	var player := PlayerScene.instantiate()
	root.add_child(player)
	var screen_effects := player.get_node_or_null("ScreenEffects")
	var settings := player.get_node_or_null("ScreenEffects/Settings")
	var glow := player.get_node_or_null("ScreenEffects/GaussianGlow") as ColorRect
	var lines := player.get_node_or_null("ScreenEffects/SpeedLines") as ColorRect
	_check(screen_effects != null, "Player scene visibly contains ScreenEffects")
	_check(settings != null, "ScreenEffects contains visible Settings scene")
	_check(screen_effects != null and screen_effects.has_method("play_dash_lines"), "ScreenEffects exposes dash trigger")
	if settings != null:
		_check(_has_property(settings, "dash_lines_enabled"), "Dash speed lines expose enable toggle")
		_check(_has_property(settings, "glow_enabled"), "Gaussian glow exposes enable toggle")
	if glow != null:
		_check(_shader_path(glow.material) == "res://shaders/gaussian_glow_screen.gdshader", "GaussianGlow uses screen shader")
	else:
		_check(false, "GaussianGlow node exists")
	if lines != null:
		_check(_shader_path(lines.material) == "res://shaders/dash_speed_lines.gdshader", "SpeedLines uses dash shader")
	else:
		_check(false, "SpeedLines node exists")
	player.queue_free()


func _validate_canvas_order() -> void:
	var game := GameScene.instantiate()
	root.add_child(game)
	var ui := game.get_node_or_null("UI") as CanvasLayer
	var screen_effects := game.get_node_or_null("RuntimeEntities/Player/ScreenEffects") as CanvasLayer
	_check(ui != null and ui.layer == 10, "Game HUD renders above shader overlays")
	_check(screen_effects != null and screen_effects.layer == 5, "Screen effects render above fog and below HUD")
	game.queue_free()


func _validate_content_editor() -> void:
	var editor := ContentEditorScene.instantiate()
	root.add_child(editor)
	await process_frame
	await process_frame
	var sidebar_button := editor.get_node_or_null("MarginContainer/MainLayout/Sidebar/SceneShaderEffectsButton")
	_check(sidebar_button != null, "Content Editor exposes Scene Shader Effects button")
	_check(editor.has_method("_save_scene_shader_settings"), "Content Editor saves settings back into scene files")
	editor.queue_free()


func _shader_path(material: Material) -> String:
	var shader_material := material as ShaderMaterial
	if shader_material == null or shader_material.shader == null:
		return ""
	return shader_material.shader.resource_path


func _has_property(object: Object, property_name: String) -> bool:
	for property_info in object.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return true
	return false


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		failures.append(label)
		print("FAIL: %s" % label)
