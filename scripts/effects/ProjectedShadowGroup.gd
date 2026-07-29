class_name ProjectedShadowGroup
extends CanvasGroup

const GROUP_SHADER := preload("res://shaders/projected_shadow_group.gdshader")

var _config: Dictionary = {}
var _group_material: ShaderMaterial


func _ready() -> void:
	name = "ProjectedShadowGroup"
	add_to_group("projected_shadow_group")
	z_as_relative = false
	z_index = 480
	fit_margin = 128.0
	clear_margin = 128.0
	use_mipmaps = false
	# Run after the individual shadow nodes have synchronized their render proxies.
	# This final visibility gate keeps a proxy hidden while its resource owner is
	# collected, then allows the normal shadow runtime to reveal it on respawn.
	process_priority = 1000
	_ensure_material()
	_reload_from_content()
	_connect_content_reload()
	set_process(true)


func _process(_delta: float) -> void:
	_sync_proxy_owner_visibility()


func configure(config: Dictionary) -> void:
	_config = config.duplicate(true)
	_apply_configuration()


func _ensure_material() -> void:
	_group_material = material as ShaderMaterial
	if _group_material == null or _group_material.shader != GROUP_SHADER:
		_group_material = ShaderMaterial.new()
		_group_material.resource_local_to_scene = true
		_group_material.shader = GROUP_SHADER
		material = _group_material


func _reload_from_content() -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_vfx_profile") or not content_db.has_vfx_profile("default"):
		_apply_configuration()
		return
	var profile: Dictionary = content_db.get_vfx_profile("default")
	var value: Variant = profile.get("directional_shadow", {})
	_config = (value as Dictionary).duplicate(true) if value is Dictionary else {}
	_apply_configuration()


func _connect_content_reload() -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_signal("content_reloaded"):
		return
	var callback := Callable(self, "_reload_from_content")
	if not content_db.content_reloaded.is_connected(callback):
		content_db.content_reloaded.connect(callback)


func _apply_configuration() -> void:
	_ensure_material()
	var enabled := bool(_config.get("enabled", true))
	var opacity := clampf(float(_config.get("opacity", 0.30)), 0.0, 1.0)
	var softness := maxf(float(_config.get("softness", 0.0)), 0.0)
	var shadow_color := _color_from_value(_config.get("color", "#050609FF"), Color(0.02, 0.024, 0.035, 1.0))
	visible = enabled and opacity > 0.001
	_group_material.set_shader_parameter("shadow_color", shadow_color)
	_group_material.set_shader_parameter("shadow_opacity", opacity)
	_group_material.set_shader_parameter("softness", softness)
	set_meta("shadow_group_opacity", opacity)
	set_meta("shadow_group_softness", softness)
	set_meta("shadow_group_color", shadow_color)


func _sync_proxy_owner_visibility() -> void:
	for child in get_children():
		if not (child is CanvasItem):
			continue
		var proxy := child as CanvasItem
		if not proxy.has_meta("shadow_owner_id"):
			continue
		var owner := instance_from_id(int(proxy.get_meta("shadow_owner_id", 0))) as CanvasItem
		var source := instance_from_id(int(proxy.get_meta("shadow_source_id", 0))) as CanvasItem
		if owner == null or source == null or not is_instance_valid(owner) or not is_instance_valid(source):
			proxy.visible = false
			continue
		if not owner.is_visible_in_tree() or not source.is_visible_in_tree():
			proxy.visible = false


func _color_from_value(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	var text := str(value).strip_edges()
	return Color.from_string(text, fallback) if not text.is_empty() else fallback
