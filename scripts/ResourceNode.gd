extends Area2D

signal collected(resource_id: String, item_id: String, amount: int)

const GatheringCalculatorScript := preload("res://scripts/systems/GatheringCalculator.gd")
const FloatingCombatTextSpawner := preload("res://scripts/ui/FloatingCombatTextSpawner.gd")
const WorldItemSpawner := preload("res://scripts/systems/WorldItemSpawner.gd")
const TreeWindShader := preload("res://shaders/tree_wind.gdshader")
const WorldDepthRuntime := preload("res://scripts/world/WorldDepthRuntime.gd")
const DirectionalShadowRuntime := preload("res://scripts/effects/DirectionalShadowRuntime.gd")

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
var _runtime_culled := false
var content_sprite: Sprite2D
var layered_visual_root: Node2D
var layered_trunk_sprite: Sprite2D
var layered_canopy_sprite: Sprite2D
var layered_canopy_wind_pivot: Node2D
var gathering_calculator := GatheringCalculatorScript.new()
var _romestead_wind_value := 0.0
var _romestead_wind_timer := 0.0
var _romestead_hit_timer := 2.0
var _romestead_hit_direction := 1.0
var _romestead_hit_intensity := 1.0
var _romestead_wind_target: Node2D
var _romestead_reaction_target: Node2D
var _romestead_reaction_base_position := Vector2.ZERO
var _romestead_occlusion_target: CanvasItem
var _romestead_occlusion_size := Vector2.ZERO
var _romestead_occlusion_enabled := false
var _tree_falling := false
var _tree_stump_visible := false
var _tree_fall_direction := 1.0
var _last_gather_actor_position := Vector2.ZERO
var _romestead_brush_timer := 1.0
var _romestead_brush_direction := 1.0


func _ready() -> void:
	add_to_group("resource_node")
	health = max_health

	if resource_id.is_empty():
		resource_id = _generate_fallback_resource_id()
		print("ResourceNode missing resource_id. Generated fallback id: %s" % resource_id)

	_load_resource_data()
	_apply_resource_sprite()
	_configure_resource_collision()
	_connect_pass_through_rustle()
	_configure_romestead_motion()
	_configure_romestead_occlusion()
	_refresh_world_presentation()
	_connect_content_reload()
	health = max_health
	# Procedural Romestead resources are animated in one culled world pass. Keeping
	# one idle callback per prop made hundreds of invisible nodes run every frame.
	if is_romestead_managed_resource():
		set_process(false)


func _process(delta: float) -> void:
	_update_romestead_motion(delta)
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
	if _tree_falling:
		return
	if _uses_romestead_tree_fall():
		_start_romestead_tree_fall()
		return

	_finish_collection()


func _finish_collection() -> void:
	print("Collected resource: %s" % resource_id)
	_show_xp_reward()
	set_collected(true, respawn_time_seconds)
	emit_signal("collected", resource_id, drop_item_id, drop_amount)
	_emit_resource_drops()


func take_damage(amount: int) -> void:
	if collected_state or _tree_falling:
		return

	if amount <= 0:
		return

	health = max(health - amount, 0)
	_start_romestead_hit_reaction()

	if health == 0:
		_collect()


func apply_gather_hit(tool_data: Dictionary, actor_data: Dictionary = {}, skill_data: Dictionary = {}, show_blocked_feedback := true) -> Dictionary:
	if collected_state or _tree_falling:
		return {}
	var actor_position_value: Variant = actor_data.get("world_position", actor_data.get("global_position", null))
	if actor_position_value is Vector2:
		_last_gather_actor_position = actor_position_value

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
		if show_blocked_feedback:
			_show_gather_feedback(str(gather_result.get("reason", "No Effect")), false, false)
		return gather_result

	var damage: int = int(gather_result.get("damage", 0))
	if damage <= 0:
		return gather_result

	health = max(health - damage, 0)
	_start_romestead_hit_reaction()
	_show_gather_feedback(str(damage), bool(gather_result.get("is_critical", false)), true)

	if health == 0:
		_collect()
	return gather_result


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
	var available := (not collected_state or _tree_stump_visible) and not _runtime_culled
	visible = available
	monitoring = available and not collected_state
	monitorable = available and not collected_state
	_set_collision_shapes_disabled(self, not available or collected_state)
	_apply_pass_through_body_state(available and not collected_state)
	if _tree_stump_visible and available:
		_set_tree_stump_body_enabled(true)
	if is_romestead_managed_resource():
		set_process(collected_state)


func set_runtime_culled(culled: bool) -> void:
	if _runtime_culled == culled:
		return
	_runtime_culled = culled
	var available := (not collected_state or _tree_stump_visible) and not _runtime_culled
	visible = available
	monitoring = available
	monitorable = available
	_set_collision_shapes_disabled(self, not available)
	_apply_pass_through_body_state(available)


func _respawn() -> void:
	if _tree_stump_visible:
		_create_persistent_stump_remnant()
		_tree_stump_visible = false
	if bool(resource_data.get("respawn_randomly", false)):
		var procedural_world := get_tree().get_first_node_in_group("procedural_resource_world")
		if procedural_world != null and procedural_world.has_method("get_random_respawn_position"):
			global_position = procedural_world.call("get_random_respawn_position", resource_type_id, global_position)
	set_collected(false)
	_restore_living_tree_visual()
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
	_configure_resource_collision()
	_connect_pass_through_rustle()
	_configure_romestead_motion()
	_configure_romestead_occlusion()
	_refresh_world_presentation()
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
	if _apply_layered_resource_visual():
		_set_placeholder_visuals_visible(false)
		return
	_hide_layered_resource_visual()
	if sprite_id.is_empty():
		return

	var sprite_record := _get_sprite_record(sprite_id)
	if sprite_record.is_empty():
		push_warning("ResourceNode %s could not find sprite_id: %s" % [resource_id, sprite_id])
		return

	var content_sprite_target := _get_content_sprite_target()
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

	if not _apply_sprite_record_to_node(content_sprite, sprite_record):
		return
	_apply_content_sprite_material(content_sprite)
	_set_placeholder_visuals_visible(false)


func _apply_layered_resource_visual() -> bool:
	var layered_value: Variant = resource_data.get("layered_visual", {})
	if not (layered_value is Dictionary):
		return false
	var layered := layered_value as Dictionary
	if not bool(layered.get("enabled", false)):
		return false
	var trunk_sprite_id := _get_living_trunk_sprite_id(layered)
	var canopy_sprite_id := str(layered.get("canopy_sprite_id", ""))
	if trunk_sprite_id.is_empty() or canopy_sprite_id.is_empty():
		push_warning("ResourceNode %s layered visual needs trunk and canopy sprite ids." % resource_id)
		return false
	var trunk_record := _get_sprite_record(trunk_sprite_id)
	var canopy_record := _get_sprite_record(canopy_sprite_id)
	if trunk_record.is_empty() or canopy_record.is_empty():
		push_warning("ResourceNode %s layered visual references a missing sprite." % resource_id)
		return false

	_ensure_layered_resource_nodes()
	if not _apply_sprite_record_to_node(layered_trunk_sprite, trunk_record):
		return false
	if not _apply_sprite_record_to_node(layered_canopy_sprite, canopy_record):
		return false
	layered_visual_root.visible = true
	layered_trunk_sprite.position = _vector_from_value(layered.get("trunk_offset", {}), Vector2.ZERO)
	var canopy_offset := _vector_from_value(layered.get("canopy_offset", {}), Vector2.ZERO)
	# Romestead's living tree sheets include foliage that reaches the authored
	# ground line, while the separate stump/root sheet sits underneath it. A small
	# lift exposes one clean grounded base instead of hiding it inside the crown.
	canopy_offset.y += float(layered.get("canopy_ground_lift", -8.0))
	layered_canopy_sprite.position = canopy_offset
	layered_trunk_sprite.z_index = 0
	layered_canopy_sprite.z_index = int(layered.get("canopy_z_offset", 2))
	layered_trunk_sprite.material = null
	if bool(layered.get("canopy_wind_enabled", true)):
		_apply_content_sprite_material(layered_canopy_sprite)
	else:
		layered_canopy_sprite.material = null
	var old_single := _get_content_sprite_target().get_node_or_null("ContentSprite") as Sprite2D
	if old_single != null and old_single != layered_trunk_sprite:
		old_single.visible = false
	content_sprite = layered_trunk_sprite
	return true


func _ensure_layered_resource_nodes() -> void:
	var target := _get_content_sprite_target()
	layered_visual_root = target.get_node_or_null("LayeredVisualRoot") as Node2D
	if layered_visual_root == null:
		layered_visual_root = Node2D.new()
		layered_visual_root.name = "LayeredVisualRoot"
		target.add_child(layered_visual_root)
	layered_trunk_sprite = layered_visual_root.get_node_or_null("TrunkSprite") as Sprite2D
	if layered_trunk_sprite == null:
		layered_trunk_sprite = Sprite2D.new()
		layered_trunk_sprite.name = "TrunkSprite"
		layered_visual_root.add_child(layered_trunk_sprite)
	layered_canopy_wind_pivot = layered_visual_root.get_node_or_null("CanopyWindPivot") as Node2D
	if layered_canopy_wind_pivot == null:
		layered_canopy_wind_pivot = Node2D.new()
		layered_canopy_wind_pivot.name = "CanopyWindPivot"
		layered_visual_root.add_child(layered_canopy_wind_pivot)
	layered_canopy_sprite = layered_canopy_wind_pivot.get_node_or_null("CanopySprite") as Sprite2D
	if layered_canopy_sprite == null:
		layered_canopy_sprite = Sprite2D.new()
		layered_canopy_sprite.name = "CanopySprite"
		layered_canopy_wind_pivot.add_child(layered_canopy_sprite)


func _hide_layered_resource_visual() -> void:
	if layered_visual_root == null:
		var target := _get_content_sprite_target()
		layered_visual_root = target.get_node_or_null("LayeredVisualRoot") as Node2D
	if layered_visual_root != null:
		layered_visual_root.visible = false
	if content_sprite == layered_trunk_sprite:
		content_sprite = null
	layered_trunk_sprite = null
	layered_canopy_sprite = null
	layered_canopy_wind_pivot = null


func _get_content_sprite_target() -> Node:
	var target := get_node_or_null("ContentSpriteTarget") as Node
	if target == null:
		target = find_child("ContentSpriteTarget", true, false) as Node
	return target if target != null else self


func _get_sprite_record(target_sprite_id: String) -> Dictionary:
	var content_db := get_node_or_null("/root/ContentDB")
	if content_db == null or not content_db.has_method("has_sprite") or not content_db.has_sprite(target_sprite_id):
		return {}
	return content_db.get_sprite(target_sprite_id)


func _apply_sprite_record_to_node(sprite: Sprite2D, sprite_data: Dictionary) -> bool:
	if sprite == null or sprite_data.is_empty():
		return false
	var texture_path := str(sprite_data.get("texture_path", ""))
	if texture_path.is_empty() or not FileAccess.file_exists(texture_path):
		return false
	var texture = load(texture_path)
	if not (texture is Texture2D):
		return false
	sprite.texture = texture
	sprite.centered = true
	sprite.visible = true
	_apply_sprite_region(sprite, sprite_data)
	_apply_sprite_anchor(sprite, sprite_data)
	return true


func _refresh_world_presentation() -> void:
	# Imported Romestead sprites are authored with their ground contact anchored
	# at the resource origin. Sorting from an arbitrary percentage of the trunk
	# made tall tree variants permanently cover (or stay behind) the player.
	if is_romestead_managed_resource():
		var managed_depth_value: Variant = resource_data.get("depth_sort", {})
		var managed_depth: Dictionary = managed_depth_value as Dictionary if managed_depth_value is Dictionary else {}
		WorldDepthRuntime.apply_node_depth(self, float(managed_depth.get("offset_y", 0.0)))
		_configure_romestead_projected_shadow()
		return

	var depth_sprite := layered_trunk_sprite if layered_trunk_sprite != null and is_instance_valid(layered_trunk_sprite) and layered_trunk_sprite.visible else content_sprite
	if depth_sprite != null and is_instance_valid(depth_sprite) and depth_sprite.visible:
		var depth_value: Variant = resource_data.get("depth_sort", {})
		var depth_config: Dictionary = (depth_value as Dictionary) if depth_value is Dictionary else {}
		var line_ratio := float(depth_config.get("line_ratio", _get_default_depth_line_ratio()))
		var depth_y := WorldDepthRuntime.get_sprite_depth_y(depth_sprite, line_ratio)
		WorldDepthRuntime.apply_depth(self, depth_y + float(depth_config.get("offset_y", 0.0)))
	else:
		WorldDepthRuntime.apply_node_depth(self)

	var shadow_value: Variant = resource_data.get("shadow", {})
	var shadow_config: Dictionary = (shadow_value as Dictionary).duplicate(true) if shadow_value is Dictionary else {}
	if not shadow_config.has("enabled"):
		shadow_config["enabled"] = true
	var visual_size := _get_composed_visual_size()
	var foot_offset := WorldDepthRuntime.get_sprite_foot_offset(depth_sprite) if depth_sprite != null else Vector2.ZERO
	DirectionalShadowRuntime.apply_to_target(self, shadow_config, visual_size, foot_offset)


func _configure_romestead_projected_shadow() -> void:
	var legacy_shadow := get_node_or_null("GroundShadow")
	if legacy_shadow != null:
		legacy_shadow.remove_from_group("projected_shadow_caster")
		legacy_shadow.queue_free()
	var source := layered_canopy_sprite if layered_canopy_sprite != null and is_instance_valid(layered_canopy_sprite) and layered_canopy_sprite.visible else content_sprite
	if source == null or not is_instance_valid(source) or source.texture == null:
		return
	var shadow := get_node_or_null("RomesteadShadow") as Sprite2D
	if shadow == null:
		shadow = Sprite2D.new()
		shadow.name = "RomesteadShadow"
		add_child(shadow)
	shadow.texture = source.texture
	shadow.region_enabled = source.region_enabled
	shadow.region_rect = source.region_rect
	shadow.hframes = source.hframes
	shadow.vframes = source.vframes
	shadow.frame = source.frame
	shadow.centered = source.centered
	shadow.offset = source.offset
	shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shadow.z_index = -2
	shadow.show_behind_parent = true
	var source_position := to_local(source.global_position)
	shadow.set_meta("source_position", source_position)
	var base_alpha := 0.16 if resource_type_id.begins_with("tree") else 0.13
	shadow.set_meta("base_alpha", base_alpha)
	shadow.modulate = Color(0.11, 0.12, 0.075, base_alpha)
	shadow.add_to_group("romestead_projected_shadows")
	_apply_romestead_shadow_transform(shadow, 12.0, 1.0)


func _apply_romestead_shadow_transform(shadow: Sprite2D, hour: float, daylight: float) -> void:
	var solar_angle := clampf((hour - 6.0) / 12.0, 0.0, 1.0) * PI
	var horizontal := clampf(-cos(solar_angle), -1.0, 1.0) * 0.42
	var vertical_scale := 0.18 + absf(cos(solar_angle)) * 0.12
	var source_position: Vector2 = shadow.get_meta("source_position", Vector2.ZERO)
	var y_basis := Vector2(-horizontal, vertical_scale)
	var projected_position := Vector2(source_position.x + y_basis.x * source_position.y, y_basis.y * source_position.y)
	shadow.transform = Transform2D(Vector2(1.0, 0.0), y_basis, projected_position)
	var light_strength := lerpf(0.28, 1.0, clampf(daylight * 1.15, 0.0, 1.0))
	shadow.modulate.a = float(shadow.get_meta("base_alpha", 0.14)) * light_strength


func _configure_romestead_occlusion() -> void:
	_romestead_occlusion_target = get_node_or_null("VisualRoot") as CanvasItem
	_romestead_occlusion_enabled = false
	_romestead_occlusion_size = Vector2.ZERO
	var source := layered_canopy_sprite if layered_canopy_sprite != null and is_instance_valid(layered_canopy_sprite) and layered_canopy_sprite.visible else content_sprite
	if source == null or not is_instance_valid(source):
		return
	var source_id := sprite_id
	var layered_value: Variant = resource_data.get("layered_visual", {})
	if layered_value is Dictionary and bool((layered_value as Dictionary).get("enabled", false)):
		source_id = str((layered_value as Dictionary).get("canopy_sprite_id", source_id))
	var sprite_record := _get_sprite_record(source_id)
	_romestead_occlusion_size = WorldDepthRuntime.get_sprite_visual_size(source) * Vector2(absf(source.global_scale.x), absf(source.global_scale.y))
	_romestead_occlusion_enabled = bool(sprite_record.get("fade_when_player_behind", false)) and _romestead_occlusion_size.y >= 40.0
	if _romestead_occlusion_target != null:
		_romestead_occlusion_target.modulate.a = 1.0
	set_meta("player_occlusion_enabled", _romestead_occlusion_enabled)


func uses_player_occlusion() -> bool:
	return _romestead_occlusion_enabled and _romestead_occlusion_target != null


func tick_player_occlusion(player_world_position: Vector2, delta: float) -> void:
	if not uses_player_occlusion():
		return
	var local_player := to_local(player_world_position)
	var horizontal_limit := maxf(_romestead_occlusion_size.x * 0.42, 18.0)
	var upper_limit := -_romestead_occlusion_size.y * 0.82
	var lower_limit := 6.0
	var covered := absf(local_player.x) <= horizontal_limit and local_player.y >= upper_limit and local_player.y <= lower_limit
	var target_alpha := 0.70 if covered else 1.0
	_romestead_occlusion_target.modulate.a = move_toward(_romestead_occlusion_target.modulate.a, target_alpha, 4.5 * delta)
	set_meta("player_occluded", covered)


func _get_composed_visual_size() -> Vector2:
	var size := Vector2(32.0, 32.0)
	for sprite in [content_sprite, layered_trunk_sprite, layered_canopy_sprite]:
		if sprite is Sprite2D and is_instance_valid(sprite) and sprite.visible:
			var candidate := WorldDepthRuntime.get_sprite_visual_size(sprite) * Vector2(absf(sprite.scale.x), absf(sprite.scale.y))
			size.x = maxf(size.x, candidate.x)
			size.y = maxf(size.y, candidate.y)
	return size


func _get_default_depth_line_ratio() -> float:
	var id := resource_type_id.to_lower()
	if id.contains("tree"):
		return 0.58
	if id.contains("rock") or id.contains("node") or id.contains("ore"):
		return 0.62
	return 0.60


func _vector_from_value(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2:
		return value
	if value is Dictionary:
		return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))
	return fallback


func set_romestead_environment(_wetness: float, _lightning: float, wind_strength: float, _wind_speed: float, wind_direction: Vector2, _hour: float = 15.0, _daylight: float = 1.0) -> void:
	var horizontal := wind_direction.normalized().x if wind_direction.length_squared() > 0.0001 else 1.0
	_romestead_wind_value = clampf(wind_strength, 0.0, 1.0) * 2.4 * clampf(horizontal, -1.0, 1.0)


func _configure_romestead_motion() -> void:
	remove_from_group("romestead_environment_receivers")
	_romestead_wind_target = null
	_romestead_reaction_target = null
	var motion_value: Variant = resource_data.get("romestead_motion", {})
	var motion: Dictionary = motion_value as Dictionary if motion_value is Dictionary else {}
	if bool(motion.get("wind_enabled", false)):
		if layered_canopy_wind_pivot != null:
			_romestead_wind_target = layered_canopy_wind_pivot
		else:
			_romestead_wind_target = _get_content_sprite_target() as Node2D
	_romestead_reaction_target = _romestead_wind_target
	if _romestead_reaction_target == null:
		_romestead_reaction_target = get_node_or_null("VisualRoot") as Node2D
	if _romestead_reaction_target != null:
		_romestead_reaction_base_position = _romestead_reaction_target.position
	_romestead_wind_timer = float(resource_id.hash() % 10000) * 0.017
	_romestead_hit_timer = 2.0


func is_romestead_managed_resource() -> bool:
	return resource_data.get("romestead_motion", null) is Dictionary


func uses_romestead_wind() -> bool:
	var motion_value: Variant = resource_data.get("romestead_motion", {})
	return motion_value is Dictionary and bool((motion_value as Dictionary).get("wind_enabled", false))


func tick_romestead_motion(delta: float) -> void:
	if not collected_state and not _tree_falling:
		_update_romestead_motion(delta)


func _update_romestead_motion(delta: float) -> void:
	var motion_value: Variant = resource_data.get("romestead_motion", {})
	if not (motion_value is Dictionary):
		return
	var motion := motion_value as Dictionary
	var wind_rotation := 0.0
	if _romestead_wind_target != null and bool(motion.get("wind_enabled", false)):
		var sway_speed := float(motion.get("sway_speed", 0.3))
		_romestead_wind_timer += delta * sway_speed * _romestead_wind_value
		var base_rotation := 0.0
		if absf(_romestead_wind_value) > 1.0:
			base_rotation = (_romestead_wind_value - signf(_romestead_wind_value)) * 1.5
		var flicker := (
			sin(_romestead_wind_timer * 3.0)
			+ sin(_romestead_wind_timer * 4.7921) * 0.5
			+ sin(_romestead_wind_timer * 7.123345) * 0.25
		) * (_romestead_wind_value * 3.0 / 1.75)
		wind_rotation = deg_to_rad((base_rotation + flicker) * float(motion.get("sway_scale", 1.0)))
	_romestead_brush_timer += delta
	var brush_rotation := 0.0
	if _romestead_brush_timer <= 0.42:
		var brush_phase := _romestead_brush_timer / 0.42
		# ContentSpriteTarget is grounded at the authored sprite anchor, so this
		# bends the foliage while its bottom row remains planted.
		brush_rotation = deg_to_rad(sin(brush_phase * PI * 4.0) * (1.0 - brush_phase) * 7.0 * _romestead_brush_direction)

	_romestead_hit_timer += delta
	var hit_rotation := 0.0
	if _romestead_hit_timer <= 1.0 and bool(motion.get("tree_hit_shake", false)):
		var decay := lerpf(2.0 * _romestead_hit_intensity, 0.0, _romestead_hit_timer)
		hit_rotation = deg_to_rad(sin(_romestead_hit_timer * PI * 2.0 * 3.0) * decay * _romestead_hit_direction)
	if _romestead_wind_target != null:
		_romestead_wind_target.rotation = wind_rotation + hit_rotation + brush_rotation
	elif _romestead_reaction_target != null:
		_romestead_reaction_target.rotation = hit_rotation + brush_rotation

	if _romestead_reaction_target != null:
		_romestead_reaction_target.position = _romestead_reaction_base_position
		if _romestead_hit_timer <= 0.18 and bool(motion.get("rock_hit_jolt", false)):
			var normalized := _romestead_hit_timer / 0.18
			var offset := sin(normalized * PI * 4.0) * (1.0 - normalized) * 1.5 * _romestead_hit_direction
			_romestead_reaction_target.position.x += offset
	if is_processing() and not collected_state and not bool(motion.get("wind_enabled", false)) and _romestead_hit_timer > 0.18 and _romestead_brush_timer > 0.42:
		set_process(false)


func _start_romestead_hit_reaction() -> void:
	var motion_value: Variant = resource_data.get("romestead_motion", {})
	if not (motion_value is Dictionary):
		return
	var motion := motion_value as Dictionary
	if not bool(motion.get("tree_hit_shake", false)) and not bool(motion.get("rock_hit_jolt", false)):
		return
	_romestead_hit_timer = 0.0
	_romestead_hit_direction = -1.0 if randi() % 2 == 0 else 1.0
	var lost_health_ratio := 1.0 - float(health) / maxf(float(max_health), 1.0)
	_romestead_hit_intensity = lerpf(1.0, 3.0, clampf(lost_health_ratio, 0.0, 1.0))
	if is_romestead_managed_resource() and not uses_romestead_wind():
		set_process(true)


func _uses_romestead_tree_fall() -> bool:
	var layered_value: Variant = resource_data.get("layered_visual", {})
	if not layered_value is Dictionary or layered_canopy_wind_pivot == null:
		return false
	var layered := layered_value as Dictionary
	return bool(layered.get("tree_fall_enabled", resource_type_id.to_lower().begins_with("tree")))


func _start_romestead_tree_fall() -> void:
	_tree_falling = true
	_tree_fall_direction = -1.0 if _last_gather_actor_position.x > global_position.x else 1.0
	if is_equal_approx(_last_gather_actor_position.x, global_position.x):
		_tree_fall_direction = _romestead_hit_direction
	monitoring = false
	monitorable = false
	_set_collision_shapes_disabled(self, true)
	var layered := resource_data.get("layered_visual", {}) as Dictionary
	var duration := maxf(float(layered.get("fall_duration", 1.2)), 0.1)
	var pivot_start := layered_canopy_wind_pivot.position
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(layered_canopy_wind_pivot, "rotation", deg_to_rad(86.0) * _tree_fall_direction, duration)
	tween.tween_property(layered_canopy_wind_pivot, "position", pivot_start + Vector2(9.0 * _tree_fall_direction, 5.0), duration)
	tween.set_parallel(false)
	tween.tween_callback(_finish_romestead_tree_fall)


func _finish_romestead_tree_fall() -> void:
	_tree_falling = false
	_tree_stump_visible = true
	if layered_canopy_sprite != null:
		layered_canopy_sprite.visible = false
	if layered_canopy_wind_pivot != null:
		layered_canopy_wind_pivot.rotation = 0.0
		layered_canopy_wind_pivot.position = Vector2.ZERO
	_apply_destroyed_stump_sprite()
	var shadow := get_node_or_null("RomesteadShadow") as CanvasItem
	if shadow != null:
		shadow.visible = false
	_finish_collection()


func _apply_destroyed_stump_sprite() -> void:
	if layered_trunk_sprite == null:
		return
	var layered_value: Variant = resource_data.get("layered_visual", {})
	if not layered_value is Dictionary:
		return
	var layered := layered_value as Dictionary
	var stump_sprite_id := _get_destroyed_stump_sprite_id(layered)
	var stump_record := _get_sprite_record(stump_sprite_id)
	if not stump_record.is_empty():
		_apply_sprite_record_to_node(layered_trunk_sprite, stump_record)


func _restore_living_tree_visual() -> void:
	if not _uses_romestead_tree_fall():
		return
	var layered := resource_data.get("layered_visual", {}) as Dictionary
	var living_id := _get_living_trunk_sprite_id(layered)
	var living_record := _get_sprite_record(living_id)
	if layered_trunk_sprite != null and not living_record.is_empty():
		_apply_sprite_record_to_node(layered_trunk_sprite, living_record)
	if layered_canopy_sprite != null:
		layered_canopy_sprite.visible = true
	var shadow := get_node_or_null("RomesteadShadow") as CanvasItem
	if shadow != null:
		shadow.visible = true
	_configure_resource_collision()


func _get_living_trunk_sprite_id(layered: Dictionary) -> String:
	if layered.has("alive_trunk_sprite_id"):
		return str(layered.get("alive_trunk_sprite_id", ""))
	var authored_id := str(layered.get("trunk_sprite_id", ""))
	# The regular stump sheet stores the shadowed top used under an intact crown
	# in frame B, and the exposed pale cut in frame A.
	return "romestead_trunk_b" if authored_id == "romestead_trunk_a" else authored_id


func _get_destroyed_stump_sprite_id(layered: Dictionary) -> String:
	if layered.has("stump_sprite_id"):
		return str(layered.get("stump_sprite_id", ""))
	var living_id := _get_living_trunk_sprite_id(layered)
	return "romestead_trunk_a" if living_id == "romestead_trunk_b" else str(layered.get("trunk_sprite_id", living_id))


func _set_tree_stump_body_enabled(enabled: bool) -> void:
	var body_shape := get_node_or_null("StaticBody2D/CollisionShape2D") as CollisionShape2D
	if body_shape == null:
		return
	body_shape.disabled = not enabled
	if enabled:
		var stump_shape := CircleShape2D.new()
		stump_shape.radius = 8.0
		body_shape.shape = stump_shape
		body_shape.position = Vector2(0.0, -2.0)


func _create_persistent_stump_remnant() -> void:
	if layered_trunk_sprite == null or layered_trunk_sprite.texture == null or get_parent() == null:
		return
	var remnant := Node2D.new()
	remnant.name = "TreeStumpRemnant"
	remnant.position = position
	remnant.z_index = z_index
	remnant.add_to_group("procedural_tree_stump_remnant")
	get_parent().add_child(remnant)
	var sprite := Sprite2D.new()
	sprite.texture = layered_trunk_sprite.texture
	sprite.region_enabled = layered_trunk_sprite.region_enabled
	sprite.region_rect = layered_trunk_sprite.region_rect
	sprite.centered = layered_trunk_sprite.centered
	sprite.offset = layered_trunk_sprite.offset
	sprite.position = layered_trunk_sprite.position
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	remnant.add_child(sprite)
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 1
	remnant.add_child(body)
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 8.0
	collision.shape = shape
	collision.position = Vector2(0.0, -2.0)
	body.add_child(collision)


func _configure_resource_collision() -> void:
	var collision_value: Variant = resource_data.get("collision", {})
	if not (collision_value is Dictionary):
		return
	var collision := collision_value as Dictionary
	var body_radius := maxf(float(collision.get("body_radius", 10.0)), 1.0)
	var interaction_radius := maxf(float(collision.get("interaction_radius", body_radius + 16.0)), body_radius)
	var body_offset := _vector_from_value(collision.get("body_offset", {}), Vector2.ZERO)
	var interaction_shape := get_node_or_null("InteractionShape") as CollisionShape2D
	if interaction_shape != null:
		var area_circle := CircleShape2D.new()
		area_circle.radius = interaction_radius
		interaction_shape.shape = area_circle
		interaction_shape.position = body_offset
	var body_shape := get_node_or_null("StaticBody2D/CollisionShape2D") as CollisionShape2D
	if body_shape != null:
		var body_circle := CircleShape2D.new()
		body_circle.radius = body_radius
		body_shape.shape = body_circle
		body_shape.position = body_offset
		body_shape.disabled = bool(collision.get("player_pass_through", false))


func _connect_pass_through_rustle() -> void:
	var collision_value: Variant = resource_data.get("collision", {})
	if not collision_value is Dictionary or not bool((collision_value as Dictionary).get("player_pass_through", false)):
		return
	var entered := Callable(self, "_on_pass_through_body_entered")
	if not body_entered.is_connected(entered):
		body_entered.connect(entered)


func _on_pass_through_body_entered(body: Node2D) -> void:
	var collision_value: Variant = resource_data.get("collision", {})
	if not collision_value is Dictionary or not bool((collision_value as Dictionary).get("player_pass_through", false)):
		return
	if body == null or (not body.is_in_group("player") and not body.is_in_group("romestead_wildlife")):
		return
	_romestead_brush_timer = 0.0
	_romestead_brush_direction = signf(global_position.x - body.global_position.x)
	if is_zero_approx(_romestead_brush_direction):
		_romestead_brush_direction = 1.0
	if not uses_romestead_wind():
		set_process(true)


func _apply_pass_through_body_state(_available: bool) -> void:
	var collision_value: Variant = resource_data.get("collision", {})
	if not collision_value is Dictionary or not bool((collision_value as Dictionary).get("player_pass_through", false)):
		return
	var body_shape := get_node_or_null("StaticBody2D/CollisionShape2D") as CollisionShape2D
	if body_shape != null:
		body_shape.disabled = true


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
