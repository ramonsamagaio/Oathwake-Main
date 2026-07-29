class_name LocalLightShadowGroup
extends CanvasGroup

const GROUP_SHADER := preload("res://shaders/projected_shadow_group.gdshader")

var _config: Dictionary = {}
var _group_material: ShaderMaterial


func _ready() -> void:
	name = "LocalLightShadowGroup"
	add_to_group("local_light_shadow_group")
	z_as_relative = false
	z_index = 481
	fit_margin = 128.0
	clear_margin = 128.0
	use_mipmaps = false
	_ensure_material()
	_reload_from_content()
	_connect_content_reload()
	set_process(true)


func _process(_delta: float) -> void:
	_apply_dynamic_opacity()


func _ensure_material() -> void:
	_group_material = material as ShaderMaterial
	if _group_material == null or _group_material.shader != GROUP_SHADER:
		_group_material = ShaderMaterial.new()
		_group_material.resource_local_to_scene = true
		_group_material.shader = GROUP_SHADER
		material = _group_material


func _reload_from_content() -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("has_vfx_profile") and content_db.has_vfx_profile("default"):
		var profile: Dictionary = content_db.get_vfx_profile("default")
		var value: Variant = profile.get("directional_shadow", {})
		_config = (value as Dictionary).duplicate(true) if value is Dictionary else {}
	_apply_static_configuration()


func _connect_content_reload() -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_signal("content_reloaded"):
		return
	var callback := Callable(self, "_reload_from_content")
	if not content_db.content_reloaded.is_connected(callback):
		content_db.content_reloaded.connect(callback)


func _apply_static_configuration() -> void:
	_ensure_material()
	var shadow_color := _color_from_value(_config.get("color", "#050609FF"), Color(0.02, 0.024, 0.035, 1.0))
	var softness := maxf(float(_config.get("local_light_shadow_softness", 1.5)), 0.0)
	_group_material.set_shader_parameter("shadow_color", shadow_color)
	_group_material.set_shader_parameter("softness", softness)
	set_meta("shadow_group_softness", softness)
	set_meta("shadow_group_color", shadow_color)
	_apply_dynamic_opacity()


func _apply_dynamic_opacity() -> void:
	if _group_material == null:
		return
	var enabled := bool(_config.get("local_light_shadows_enabled", true))
	var night_strength := 0.0
	var cycle := get_tree().get_first_node_in_group("day_night_cycle")
	if cycle != null and cycle.has_method("get_night_strength"):
		night_strength = clampf(float(cycle.call("get_night_strength")), 0.0, 1.0)
	# Local shadows begin only after the solar shadow is already fading, avoiding
	# a dark double layer during ordinary daytime.
	var night_factor := smoothstep(0.18, 0.82, night_strength)
	var base_opacity := clampf(float(_config.get("local_light_shadow_opacity", 0.12)), 0.0, 1.0)
	var final_opacity := base_opacity * night_factor
	visible = enabled and final_opacity > 0.001
	_group_material.set_shader_parameter("shadow_opacity", final_opacity)
	set_meta("shadow_group_opacity", final_opacity)
	set_meta("night_shadow_strength", night_factor)


func _color_from_value(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	var text := str(value).strip_edges()
	return Color.from_string(text, fallback) if not text.is_empty() else fallback
