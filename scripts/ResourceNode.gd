extends Area2D

signal collected(resource_id: String, item_id: String, amount: int)

const GatheringCalculatorScript := preload("res://scripts/systems/GatheringCalculator.gd")
const FloatingCombatTextSpawner := preload("res://scripts/ui/FloatingCombatTextSpawner.gd")
const WorldItemSpawner := preload("res://scripts/systems/WorldItemSpawner.gd")
const TreeWindShader := preload("res://shaders/tree_wind.gdshader")

@export var resource_id: String = ""
@export var resource_type_id: String = ""
@export var resource_name: String = "Resource"
@export var collect_amount: int = 1
@export var max_health: int = 30
@export var respawn_time_seconds: float = 60.0
@export var debug_gathering := false

var display_name := "Resource"
var sprite_id := ""
var drop_item_id := ""
var drop_amount := 1
var resource_data := {}
var health: int = 30
var collected_state := false
var respawn_time_left := 0.0
var content_sprite: Sprite2D
var gathering_calculator := GatheringCalculatorScript.new()


func _ready() -> void:
	add_to_group("resource_node")
	health = max_health

	if resource_id.is_empty():
		resource_id = _generate_fallback_resource_id()
		print("ResourceNode missing resource_id. Generated fallback id: %s" % resource_id)

	_load_resource_data()
	_apply_resource_sprite()
	_connect_content_reload()
	health = max_health


func _process(delta: float) -> void:
	if not collected_state:
		return

	if respawn_time_left <= 0.0:
		_respawn()
		return

	respawn_time_left = max(respawn_time_left - delta, 0.0)
	if respawn_time_left == 0.0:
		_respawn()


func _collect() -> void:
	if collected_state:
		return

	print("Collected resource: %s" % resource_id)
	_show_xp_reward()
	set_collected(true, respawn_time_seconds)
	emit_signal("collected", resource_id, drop_item_id, drop_amount)
	_emit_resource_drops()


func take_damage(amount: int) -> void:
	if collected_state:
		return

	if amount <= 0:
		return

	health = max(health - amount, 0)

	if health == 0:
		_collect()


func apply_gather_hit(tool_data: Dictionary, actor_data: Dictionary = {}, skill_data: Dictionary = {}) -> void:
	if collected_state:
		return

	var gather_result: Dictionary = gathering_calculator.calculate_gather_damage(_get_resource_data(), tool_data, actor_data, skill_data)
	if debug_gathering:
		print("Gather %s with %s | resource_tier=%d tool_tier=%d modifier=%.2f damage=%d reason=%s" % [
			resource_type_id,
			str(tool_data.get("id", tool_data.get("tool_type", "unknown"))),
			int(_get_resource_data().get("resource_tier", 1)),
			int(tool_data.get("tool_tier", tool_data.get("tier", 1))),
			float(gather_result.get("tier_modifier", 0.0)),
			int(gather_result.get("damage", 0)),
			str(gather_result.get("reason", "")),
		])

	if not bool(gather_result.get("can_damage", false)):
		_show_gather_feedback(str(gather_result.get("reason", "No Effect")), false, false)
		return

	var damage: int = int(gather_result.get("damage", 0))
	if damage <= 0:
		return

	health = max(health - damage, 0)
	_show_gather_feedback(str(damage), bool(gather_result.get("is_critical", false)), true)

	if health == 0:
		_collect()


func get_resource_id() -> String:
	return resource_id


func get_resource_name() -> String:
	return resource_name


func get_resource_type_id() -> String:
	return resource_type_id


func get_drop_item_id() -> String:
	return drop_item_id


func is_collected() -> bool:
	return collected_state


func get_respawn_time_left() -> float:
	return respawn_time_left if collected_state else 0.0


func set_collected(is_resource_collected: bool, respawn_time_left_seconds := -1.0) -> void:
	collected_state = is_resource_collected
	respawn_time_left = respawn_time_seconds if collected_state else 0.0
	if collected_state and respawn_time_left_seconds >= 0.0:
		respawn_time_left = respawn_time_left_seconds

	health = 0 if collected_state else max_health
	visible = not collected_state
	monitoring = not collected_state
	monitorable = not collected_state
	_set_collision_shapes_disabled(self, collected_state)


func _respawn() -> void:
	set_collected(false)
	print("Respawned resource: %s" % resource_id)


func _load_resource_data() -> void:
	if resource_type_id.is_empty():
		resource_type_id = _get_fallback_resource_type_id()
		print("ResourceNode %s missing resource_type_id. Using fallback: %s" % [resource_id, resource_type_id])

	drop_item_id = _normalize_item_id(resource_name)
	drop_amount = collect_amount
	display_name = resource_name

	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null:
		return

	var resource_data: Dictionary = content_db.get_resource(resource_type_id)
	if resource_data.is_empty():
		push_error("ResourceNode %s could not load resource_type_id: %s" % [resource_id, resource_type_id])
		return

	self.resource_data = resource_data
	display_name = str(resource_data.get("display_name", display_name))
	resource_name = display_name
	max_health = int(resource_data.get("resource_hp", resource_data.get("max_health", max_health)))
	drop_item_id = str(resource_data.get("drop_item_id", drop_item_id))
	drop_amount = int(resource_data.get("drop_amount", drop_amount))
	respawn_time_seconds = float(resource_data.get("respawn_time_seconds", respawn_time_seconds))
	sprite_id = str(resource_data.get("sprite_id", sprite_id))


func _connect_content_reload() -> void:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_signal("content_reloaded"):
		var callback := Callable(self, "_on_content_reloaded")
		if not content_db.content_reloaded.is_connected(callback):
			content_db.content_reloaded.connect(callback)


func _on_content_reloaded() -> void:
	_load_resource_data()
	_apply_resource_sprite()
	if not collected_state:
		health = min(health, max_health)


func _get_resource_data() -> Dictionary:
	if resource_data.is_empty():
		return {
			"id": resource_type_id,
			"resource_tier": 1,
			"resource_hp": max_health,
			"required_tool_type": "",
			"allow_hands": true,
			"skill_type": "",
			"base_drops": [
				{
					"item_id": drop_item_id,
					"min_amount": drop_amount,
					"max_amount": drop_amount,
					"chance": 1.0,
				},
			],
			"rare_drops": [],
		}

	return resource_data


func _emit_resource_drops() -> void:
	var dropped_any := false
	var drop_results := []
	for drop_entry in _roll_drop_table(_get_resource_data().get("base_drops", [])):
		drop_results.append(drop_entry)
		dropped_any = true

	for drop_entry in _roll_drop_table(_get_resource_data().get("rare_drops", [])):
		drop_results.append(drop_entry)
		dropped_any = true

	if not dropped_any:
		drop_results.append({
			"item_id": drop_item_id,
			"amount": drop_amount,
		})

	WorldItemSpawner.spawn_drops(drop_results, global_position)


func _roll_drop_table(drop_rows_value: Variant) -> Array:
	var drops := []
	if not drop_rows_value is Array:
		return drops

	for drop_entry in drop_rows_value:
		if not drop_entry is Dictionary:
			continue

		var drop_data: Dictionary = drop_entry
		var chance: float = clamp(float(drop_data.get("chance", 1.0)), 0.0, 1.0)
		if randf() > chance:
			continue

		var item_id: String = str(drop_data.get("item_id", ""))
		var min_amount: int = max(int(drop_data.get("min_amount", 1)), 1)
		var max_amount: int = max(int(drop_data.get("max_amount", min_amount)), min_amount)
		var amount: int = min_amount
		if max_amount > min_amount:
			amount += int(randi() % (max_amount - min_amount + 1))
		if not item_id.is_empty() and amount > 0:
			drops.append({
				"item_id": item_id,
				"amount": amount,
			})

	return drops


func _show_gather_feedback(text: String, is_critical: bool, is_damage: bool) -> void:
	if is_damage:
		FloatingCombatTextSpawner.show_damage(int(text), global_position + Vector2(0, -28), is_critical, "enemy")
		return

	FloatingCombatTextSpawner.show_text(text, global_position + Vector2(0, -28), Color(0.72, 0.72, 0.72, 1.0))


func _show_xp_reward() -> void:
	var xp_reward := int(_get_resource_data().get("xp_reward", 0))
	if xp_reward <= 0:
		return

	FloatingCombatTextSpawner.show_xp(xp_reward, global_position + Vector2(0, -30))


func _apply_resource_sprite() -> void:
	if sprite_id.is_empty():
		return

	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_sprite") or not content_db.has_sprite(sprite_id):
		push_warning("ResourceNode %s could not find sprite_id: %s" % [resource_id, sprite_id])
		return

	var sprite_data: Dictionary = content_db.get_sprite(sprite_id)
	var texture_path := str(sprite_data.get("texture_path", ""))
	if texture_path.is_empty() or not FileAccess.file_exists(texture_path):
		push_warning("ResourceNode %s sprite has invalid texture_path: %s" % [resource_id, texture_path])
		return

	var texture = load(texture_path)
	if not texture is Texture2D:
		push_warning("ResourceNode %s sprite texture is not Texture2D: %s" % [resource_id, texture_path])
		return

	var content_sprite_target := get_node_or_null("ContentSpriteTarget") as Node
	if content_sprite_target == null:
		content_sprite_target = find_child("ContentSpriteTarget", true, false) as Node
	if content_sprite == null and content_sprite_target != null:
		content_sprite = content_sprite_target.get_node_or_null("ContentSprite") as Sprite2D
	if content_sprite == null:
		content_sprite = get_node_or_null("ContentSprite") as Sprite2D
	if content_sprite == null:
		content_sprite = Sprite2D.new()
		content_sprite.name = "ContentSprite"
		if content_sprite_target != null:
			content_sprite_target.add_child(content_sprite)
		else:
			add_child(content_sprite)
			move_child(content_sprite, 0)

	content_sprite.texture = texture
	content_sprite.centered = true
	content_sprite.visible = true
	_apply_sprite_region(content_sprite, sprite_data)
	_apply_sprite_anchor(content_sprite, sprite_data)
	_apply_content_sprite_material(content_sprite)
	_set_placeholder_visuals_visible(false)


func _apply_content_sprite_material(sprite: Sprite2D) -> void:
	if resource_type_id == "tree":
		var material := ShaderMaterial.new()
		material.shader = TreeWindShader
		_apply_tree_wind_profile(material)
		sprite.material = material
	else:
		sprite.material = null


func _apply_tree_wind_profile(material: ShaderMaterial) -> void:
	if material == null:
		return

	var vfx_profile := _get_vfx_profile()
	_set_shader_parameter_if_available(material, "wind_strength", float(vfx_profile.get("tree_wind_strength", 1.5)))
	_set_shader_parameter_if_available(material, "wind_speed", float(vfx_profile.get("tree_wind_speed", 1.2)))


func _set_shader_parameter_if_available(material: ShaderMaterial, parameter_name: String, value: Variant) -> void:
	if material == null or material.shader == null:
		return

	for uniform in material.shader.get_shader_uniform_list():
		if str(uniform.get("name", "")) == parameter_name:
			material.set_shader_parameter(parameter_name, value)
			return


func _get_vfx_profile() -> Dictionary:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db != null and content_db.has_method("has_vfx_profile") and content_db.has_vfx_profile("default"):
		return content_db.get_vfx_profile("default")
	return {}


func _apply_sprite_region(sprite: Sprite2D, sprite_data: Dictionary) -> void:
	sprite.region_enabled = bool(sprite_data.get("region_enabled", false))
	if not sprite.region_enabled:
		return

	var region = sprite_data.get("region", {})
	if not region is Dictionary:
		return

	sprite.region_rect = Rect2(
		float(region.get("x", 0.0)),
		float(region.get("y", 0.0)),
		float(region.get("w", 32.0)),
		float(region.get("h", 32.0))
	)


func _apply_sprite_anchor(sprite: Sprite2D, sprite_data: Dictionary) -> void:
	var visual_size := _get_sprite_visual_size(sprite, sprite_data)
	var anchor = sprite_data.get("anchor", {})
	var anchor_position := Vector2(visual_size.x * 0.5, visual_size.y)
	if anchor is Dictionary:
		anchor_position = Vector2(
			float(anchor.get("x", anchor_position.x)),
			float(anchor.get("y", anchor_position.y))
		)

	sprite.offset = Vector2(
		(visual_size.x * 0.5) - anchor_position.x,
		(visual_size.y * 0.5) - anchor_position.y
	)


func _get_sprite_visual_size(sprite: Sprite2D, sprite_data: Dictionary) -> Vector2:
	if sprite.region_enabled:
		return sprite.region_rect.size

	var frame_size = sprite_data.get("frame_size", {})
	if frame_size is Dictionary:
		return Vector2(
			float(frame_size.get("w", sprite.texture.get_width())),
			float(frame_size.get("h", sprite.texture.get_height()))
		)

	if sprite.texture != null:
		return sprite.texture.get_size()

	return Vector2(32, 32)


func _get_fallback_resource_type_id() -> String:
	match resource_name:
		"Wood":
			return "tree"
		"Stone":
			return "rock"
		_:
			return resource_name.to_lower()


func _normalize_item_id(item_id: String) -> String:
	match item_id:
		"Wood":
			return "wood"
		"Stone":
			return "stone"
		"Gel":
			return "gel"
		_:
			return item_id.to_lower()


func _generate_fallback_resource_id() -> String:
	return str(get_path()).replace("/", "_").replace(":", "_")


func _set_collision_shapes_disabled(node: Node, is_disabled: bool) -> void:
	for child in node.get_children():
		if child is CollisionShape2D:
			child.disabled = is_disabled

		_set_collision_shapes_disabled(child, is_disabled)


func _set_placeholder_visuals_visible(is_visible: bool) -> void:
	_set_placeholder_visuals_visible_recursive(self, is_visible)


func _set_placeholder_visuals_visible_recursive(node: Node, is_visible: bool) -> void:
	for child in node.get_children():
		if child != content_sprite and child is Polygon2D:
			child.visible = is_visible

		_set_placeholder_visuals_visible_recursive(child, is_visible)
