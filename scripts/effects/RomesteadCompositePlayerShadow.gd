class_name RomesteadCompositePlayerShadow
extends CanvasGroup

var _owner: Node2D
var _visual_root: Node2D
var _sources: Array[Sprite2D] = []
var _shadows: Array[Sprite2D] = []
const NIGHT_SHADOW_STRENGTH := 0.28


func configure(owner: Node2D, visual_root: Node2D) -> void:
	_owner = owner
	_visual_root = visual_root
	name = "RomesteadPlayerShadow"
	show_behind_parent = true
	z_index = -2
	z_as_relative = true
	# Render every rig part into one off-screen silhouette. Applying the tint and
	# opacity to the flattened CanvasGroup prevents overlapping limbs from making
	# dark seams in the projected shadow.
	fit_margin = 96.0
	clear_margin = 96.0
	modulate = Color.WHITE
	_rebuild_sources()
	sync_projection()


func sync_projection() -> void:
	if _owner == null or _visual_root == null or not is_instance_valid(_visual_root):
		return
	if _sources.is_empty():
		_rebuild_sources()
	var environment := get_tree().get_first_node_in_group("romestead_environment_controller")
	var hour := 16.0
	var daylight := 1.0
	if environment != null:
		hour = float(environment.get("time_of_day"))
		if environment.has_method("get_daylight_strength"):
			daylight = float(environment.call("get_daylight_strength"))
	var solar_angle := clampf((hour - 6.0) / 12.0, 0.0, 1.0) * PI
	var horizontal := clampf(-cos(solar_angle), -1.0, 1.0) * 0.42
	var vertical_scale := 0.18 + absf(cos(solar_angle)) * 0.12
	var projection := Transform2D(Vector2(1.0, 0.0), Vector2(-horizontal, vertical_scale), Vector2.ZERO)
	var owner_inverse := _owner.global_transform.affine_inverse()
	var light_strength := lerpf(NIGHT_SHADOW_STRENGTH, 1.0, clampf(daylight * 1.15, 0.0, 1.0))
	var resolved_alpha := 0.18 * light_strength
	self_modulate = Color(0.11, 0.12, 0.075, resolved_alpha)
	visible = resolved_alpha > 0.001
	for index in range(_sources.size()):
		var source := _sources[index]
		var shadow := _shadows[index]
		if not is_instance_valid(source) or not is_instance_valid(shadow):
			continue
		_sync_sprite_frame(source, shadow)
		shadow.visible = source.is_visible_in_tree()
		shadow.transform = projection * (owner_inverse * source.global_transform)
		shadow.modulate = Color.WHITE
		shadow.self_modulate = Color(1.0, 1.0, 1.0, source.modulate.a * source.self_modulate.a)


func _rebuild_sources() -> void:
	for shadow in _shadows:
		if is_instance_valid(shadow):
			shadow.queue_free()
	_sources.clear()
	_shadows.clear()
	if _visual_root == null:
		return
	_collect_sources(_visual_root)
	for source in _sources:
		var shadow := Sprite2D.new()
		shadow.name = "PartShadow_%d" % _shadows.size()
		shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		shadow.show_behind_parent = true
		shadow.z_index = 0
		shadow.z_as_relative = true
		add_child(shadow)
		_shadows.append(shadow)
		_sync_sprite_frame(source, shadow)


func _collect_sources(node: Node) -> void:
	for child in node.get_children():
		if child is Sprite2D:
			var sprite := child as Sprite2D
			if sprite.texture != null and not str(sprite.name).to_lower().contains("shadow"):
				_sources.append(sprite)
		_collect_sources(child)


func _sync_sprite_frame(source: Sprite2D, shadow: Sprite2D) -> void:
	shadow.texture = source.texture
	shadow.region_enabled = source.region_enabled
	shadow.region_rect = source.region_rect
	shadow.hframes = source.hframes
	shadow.vframes = source.vframes
	shadow.frame = source.frame
	shadow.centered = source.centered
	shadow.offset = source.offset
	shadow.flip_h = source.flip_h
	shadow.flip_v = source.flip_v
