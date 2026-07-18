@tool
class_name EffectPreviewPanel
extends SubViewportContainer

const PREVIEW_SIZE := Vector2i(520, 280)
const ITEM_TEXTURE: Texture2D = preload("res://assets/generated/previews/content_editor_item_preview.svg")
const TREE_CROWN_TEXTURE: Texture2D = preload("res://assets/generated/previews/content_editor_tree_crown.svg")
const TREE_TRUNK_TEXTURE: Texture2D = preload("res://assets/generated/previews/content_editor_tree_trunk.svg")
const PLAYER_TEXTURE: Texture2D = preload("res://assets/generated/previews/content_editor_player_preview.svg")
const MAP_TEXTURE: Texture2D = preload("res://assets/generated/previews/content_editor_map_preview.svg")
const OUTLINE_SHADER: Shader = preload("res://shaders/world_item_outline.gdshader")
const FOLIAGE_SHADER: Shader = preload("res://shaders/foliage_wind_2d.gdshader")
const GLOW_SHADER: Shader = preload("res://shaders/gaussian_glow_screen.gdshader")
const FOG_SHADER: Shader = preload("res://shaders/map_fog_overlay_2d.gdshader")

var _viewport: SubViewport
var _preview_root: Node2D
var _mode := ""
var _outline_material: ShaderMaterial
var _foliage_material: ShaderMaterial
var _glow_material: ShaderMaterial
var _fog_material: ShaderMaterial


func _init() -> void:
	custom_minimum_size = Vector2(PREVIEW_SIZE)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_viewport()


func setup_mode(mode_name: String) -> void:
	_ensure_viewport()
	_mode = mode_name
	_rebuild_preview()


func apply_outline(enabled: bool, outline_color: Color, outline_size: float, alpha_threshold: float, samples: int) -> void:
	if _outline_material == null:
		return
	_outline_material.set_shader_parameter("enabled", enabled)
	_outline_material.set_shader_parameter("outline_color", outline_color)
	_outline_material.set_shader_parameter("outline_size", outline_size)
	_outline_material.set_shader_parameter("alpha_threshold", alpha_threshold)
	_outline_material.set_shader_parameter("samples", samples)


func apply_wind(enabled: bool, render_noise: bool, amplitude: float, time_scale: float, noise_scale: float, rotation_strength: float, rotation_pivot: Vector2) -> void:
	if _foliage_material == null:
		return
	_foliage_material.set_shader_parameter("enabled", enabled)
	_foliage_material.set_shader_parameter("render_noise", render_noise)
	_foliage_material.set_shader_parameter("amplitude", amplitude)
	_foliage_material.set_shader_parameter("time_scale", time_scale)
	_foliage_material.set_shader_parameter("noise_scale", noise_scale)
	_foliage_material.set_shader_parameter("rotation_strength", rotation_strength)
	_foliage_material.set_shader_parameter("rotation_pivot", rotation_pivot)


func apply_glow(enabled: bool, threshold: float, intensity: float, iterations: int, blur_size: float, subdivisions: int, mix_amount: float) -> void:
	if _glow_material == null:
		return
	_glow_material.set_shader_parameter("enabled", enabled)
	_glow_material.set_shader_parameter("bloom_threshold", threshold)
	_glow_material.set_shader_parameter("bloom_intensity", intensity)
	_glow_material.set_shader_parameter("blur_iterations", iterations)
	_glow_material.set_shader_parameter("blur_size", blur_size)
	_glow_material.set_shader_parameter("blur_subdivisions", subdivisions)
	_glow_material.set_shader_parameter("mix_amount", mix_amount)


func apply_fog(enabled: bool, density: float, speed: Vector2, fog_color: Color, fog_scale: float, coverage: float, softness: float, detail_mix: float) -> void:
	if _fog_material == null:
		return
	_fog_material.set_shader_parameter("enabled", enabled)
	_fog_material.set_shader_parameter("density", density)
	_fog_material.set_shader_parameter("speed", speed)
	_fog_material.set_shader_parameter("fog_color", fog_color)
	_fog_material.set_shader_parameter("fog_scale", fog_scale)
	_fog_material.set_shader_parameter("coverage", coverage)
	_fog_material.set_shader_parameter("softness", softness)
	_fog_material.set_shader_parameter("detail_mix", detail_mix)


func _ensure_viewport() -> void:
	if _viewport != null:
		return
	_viewport = SubViewport.new()
	_viewport.name = "EffectPreviewViewport"
	_viewport.size = PREVIEW_SIZE
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(_viewport)


func _rebuild_preview() -> void:
	if _preview_root != null and is_instance_valid(_preview_root):
		_preview_root.queue_free()
	_preview_root = Node2D.new()
	_preview_root.name = "PreviewRoot"
	_viewport.add_child(_preview_root)
	_outline_material = null
	_foliage_material = null
	_glow_material = null
	_fog_material = null

	match _mode:
		"outline":
			_build_outline_preview()
		"foliage":
			_build_foliage_preview()
		"glow":
			_build_glow_preview()
		"fog":
			_build_fog_preview()
		_:
			_build_empty_preview()


func _build_empty_preview() -> void:
	_add_background(Color(0.055, 0.06, 0.075, 1.0))


func _build_outline_preview() -> void:
	_add_background(Color(0.055, 0.06, 0.075, 1.0))
	_add_grid_floor()
	var shadow := Polygon2D.new()
	shadow.position = Vector2(260, 213)
	shadow.scale = Vector2(2.2, 0.8)
	shadow.color = Color(0.0, 0.0, 0.0, 0.34)
	shadow.polygon = PackedVector2Array([
		Vector2(-18, -5), Vector2(-11, -9), Vector2(11, -9), Vector2(18, -5),
		Vector2(20, 0), Vector2(18, 5), Vector2(11, 9), Vector2(-11, 9),
		Vector2(-18, 5), Vector2(-20, 0),
	])
	_preview_root.add_child(shadow)

	_outline_material = ShaderMaterial.new()
	_outline_material.shader = OUTLINE_SHADER
	var outline_sprite := Sprite2D.new()
	outline_sprite.position = Vector2(260, 142)
	outline_sprite.texture = ITEM_TEXTURE
	outline_sprite.scale = Vector2(1.25, 1.25)
	outline_sprite.material = _outline_material
	outline_sprite.z_index = 1
	_preview_root.add_child(outline_sprite)

	var item_sprite := Sprite2D.new()
	item_sprite.position = outline_sprite.position
	item_sprite.texture = ITEM_TEXTURE
	item_sprite.scale = outline_sprite.scale
	item_sprite.z_index = 2
	_preview_root.add_child(item_sprite)


func _build_foliage_preview() -> void:
	_add_background(Color(0.06, 0.10, 0.075, 1.0))
	_add_grid_floor(Color(0.12, 0.20, 0.13, 1.0))
	var trunk := Sprite2D.new()
	trunk.position = Vector2(260, 191)
	trunk.texture = TREE_TRUNK_TEXTURE
	trunk.scale = Vector2(1.1, 1.1)
	trunk.z_index = 1
	_preview_root.add_child(trunk)

	_foliage_material = ShaderMaterial.new()
	_foliage_material.shader = FOLIAGE_SHADER
	var crown := Sprite2D.new()
	crown.position = Vector2(260, 113)
	crown.texture = TREE_CROWN_TEXTURE
	crown.scale = Vector2(1.25, 1.25)
	crown.material = _foliage_material
	crown.z_index = 2
	_preview_root.add_child(crown)


func _build_glow_preview() -> void:
	_add_background(Color(0.018, 0.02, 0.034, 1.0))
	_add_grid_floor(Color(0.055, 0.06, 0.085, 1.0))
	var player := Sprite2D.new()
	player.position = Vector2(260, 147)
	player.texture = PLAYER_TEXTURE
	player.scale = Vector2(1.15, 1.15)
	player.z_index = 2
	_preview_root.add_child(player)

	var rune := Polygon2D.new()
	rune.position = Vector2(260, 124)
	rune.color = Color(1.0, 0.82, 1.0, 1.0)
	rune.polygon = PackedVector2Array([
		Vector2(0, -11), Vector2(8, 0), Vector2(0, 11), Vector2(-8, 0),
	])
	rune.z_index = 3
	_preview_root.add_child(rune)

	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	copy.z_index = 20
	_preview_root.add_child(copy)

	_glow_material = ShaderMaterial.new()
	_glow_material.shader = GLOW_SHADER
	var overlay := ColorRect.new()
	overlay.position = Vector2.ZERO
	overlay.size = Vector2(PREVIEW_SIZE)
	overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.material = _glow_material
	overlay.z_index = 21
	_preview_root.add_child(overlay)


func _build_fog_preview() -> void:
	var map_sprite := Sprite2D.new()
	map_sprite.centered = false
	map_sprite.position = Vector2.ZERO
	map_sprite.texture = MAP_TEXTURE
	map_sprite.z_index = 0
	_preview_root.add_child(map_sprite)

	_fog_material = ShaderMaterial.new()
	_fog_material.shader = FOG_SHADER
	var fog_rect := ColorRect.new()
	fog_rect.position = Vector2.ZERO
	fog_rect.size = Vector2(PREVIEW_SIZE)
	fog_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fog_rect.material = _fog_material
	fog_rect.z_index = 5
	_preview_root.add_child(fog_rect)


func _add_background(color_value: Color) -> void:
	var background := ColorRect.new()
	background.position = Vector2.ZERO
	background.size = Vector2(PREVIEW_SIZE)
	background.color = color_value
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.z_index = -20
	_preview_root.add_child(background)


func _add_grid_floor(color_value := Color(0.09, 0.10, 0.13, 1.0)) -> void:
	var floor_rect := ColorRect.new()
	floor_rect.position = Vector2(0, 218)
	floor_rect.size = Vector2(PREVIEW_SIZE.x, 62)
	floor_rect.color = color_value
	floor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floor_rect.z_index = -10
	_preview_root.add_child(floor_rect)
	for x in range(0, PREVIEW_SIZE.x, 32):
		var line := ColorRect.new()
		line.position = Vector2(x, 218)
		line.size = Vector2(1, 62)
		line.color = Color(1.0, 1.0, 1.0, 0.035)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.z_index = -9
		_preview_root.add_child(line)
