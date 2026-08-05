extends "res://scripts/player/PlayerLightPerspectiveSuite.gd"

const IDLE_SOUTH_PATHS := [
	"res://assets/sprites/characters/WIP/IdleSouthSheet_0001.png",
	"res://assets/sprites/characters/WIP/IdleSouthSheet_0002.png",
	"res://assets/sprites/characters/WIP/IdleSouthSheet_0003.png",
	"res://assets/sprites/characters/WIP/IdleSouthSheet_0004.png",
	"res://assets/sprites/characters/WIP/IdleSouthSheet_0005.png",
	"res://assets/sprites/characters/WIP/IdleSouthSheet_0006.png",
]
const RUN_SOUTH_PATHS := [
	"res://assets/sprites/characters/WIP/RunSouthSheet_0001.png",
	"res://assets/sprites/characters/WIP/RunSouthSheet_0002.png",
	"res://assets/sprites/characters/WIP/RunSouthSheet_0003.png",
	"res://assets/sprites/characters/WIP/RunSouthSheet_0004.png",
	"res://assets/sprites/characters/WIP/RunSouthSheet_0005.png",
	"res://assets/sprites/characters/WIP/RunSouthSheet_0006.png",
]

@export_range(1.0, 30.0, 0.5) var wip_idle_fps := 7.0
@export_range(1.0, 30.0, 0.5) var wip_walk_fps := 8.0
@export_range(1.0, 30.0, 0.5) var wip_run_fps := 11.0
@export_range(0.25, 4.0, 0.05) var wip_scale_multiplier := 1.0
@export var wip_position_offset := Vector2.ZERO

@onready var wip_south_sprite: AnimatedSprite2D = $WIPSouthSprite

var _wip_south_ready := false
var _wip_visual_active := false


func _setup_character_visual() -> void:
	# Keep the complete current character as fallback, then layer the new south
	# animations on top without touching the definitive Player scene.
	super._setup_character_visual()
	_configure_wip_south_animations()


func _configure_wip_south_animations() -> void:
	if wip_south_sprite == null:
		push_warning("WIPPlayer is missing WIPSouthSprite.")
		return

	var idle_textures := _load_wip_textures(IDLE_SOUTH_PATHS, "idle south")
	var run_textures := _load_wip_textures(RUN_SOUTH_PATHS, "run south")
	if idle_textures.size() != IDLE_SOUTH_PATHS.size() or run_textures.size() != RUN_SOUTH_PATHS.size():
		_wip_south_ready = false
		_set_wip_visual_active(false)
		push_warning("WIPPlayer could not find all WIP frames. The regular player remains active as fallback.")
		return

	var sprite_frames := SpriteFrames.new()
	if sprite_frames.has_animation("default"):
		sprite_frames.remove_animation("default")
	_add_wip_animation(sprite_frames, "idle_down", idle_textures, wip_idle_fps)
	_add_wip_animation(sprite_frames, "walk_down", run_textures, wip_walk_fps)
	_add_wip_animation(sprite_frames, "run_down", run_textures, wip_run_fps)
	wip_south_sprite.sprite_frames = sprite_frames
	wip_south_sprite.centered = true
	wip_south_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	wip_south_sprite.position = animated_sprite.position + wip_position_offset
	wip_south_sprite.z_index = animated_sprite.z_index
	_fit_wip_scale_to_fallback(idle_textures[0])
	_wip_south_ready = true
	_set_wip_visual_active(last_direction == "down")
	if _wip_visual_active:
		wip_south_sprite.play("idle_down")
	print("WIPPlayer loaded 6 idle south frames and 6 run south frames.")


func _load_wip_textures(paths: Array, animation_label: String) -> Array[Texture2D]:
	var textures: Array[Texture2D] = []
	for path_value in paths:
		var texture_path := str(path_value)
		if not ResourceLoader.exists(texture_path):
			push_warning("WIPPlayer missing %s frame: %s" % [animation_label, texture_path])
			textures.clear()
			return textures
		var texture := load(texture_path) as Texture2D
		if texture == null:
			push_warning("WIPPlayer could not load %s frame: %s" % [animation_label, texture_path])
			textures.clear()
			return textures
		textures.append(texture)
	return textures


func _add_wip_animation(sprite_frames: SpriteFrames, animation_name: StringName, textures: Array[Texture2D], fps: float) -> void:
	if sprite_frames.has_animation(animation_name):
		sprite_frames.remove_animation(animation_name)
	sprite_frames.add_animation(animation_name)
	sprite_frames.set_animation_loop(animation_name, true)
	sprite_frames.set_animation_speed(animation_name, maxf(fps, 0.01))
	for texture in textures:
		sprite_frames.add_frame(animation_name, texture)


func _fit_wip_scale_to_fallback(wip_reference_texture: Texture2D) -> void:
	if animated_sprite == null or wip_reference_texture == null:
		return
	var fallback_height := _get_fallback_reference_height()
	var wip_height := float(wip_reference_texture.get_height())
	if fallback_height <= 0.0 or wip_height <= 0.0:
		wip_south_sprite.scale = animated_sprite.scale * wip_scale_multiplier
		return
	var target_render_height := fallback_height * absf(animated_sprite.scale.y)
	var fitted_scale := target_render_height / wip_height
	wip_south_sprite.scale = Vector2.ONE * fitted_scale * wip_scale_multiplier


func _get_fallback_reference_height() -> float:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return 64.0
	for animation_name in ["idle_down", "walk_down", "run_down"]:
		if not animated_sprite.sprite_frames.has_animation(animation_name):
			continue
		if animated_sprite.sprite_frames.get_frame_count(animation_name) <= 0:
			continue
		var texture := animated_sprite.sprite_frames.get_frame_texture(animation_name, 0)
		if texture != null:
			return float(texture.get_height())
	return 64.0


func _update_movement_animation(input_direction: Vector2) -> void:
	if _is_life_animation_locked():
		_set_wip_visual_active(false)
		return

	if action_state != ActionState.FREE:
		_set_wip_visual_active(false)
		super._update_movement_animation(input_direction)
		return

	if input_direction != Vector2.ZERO:
		_update_last_direction(input_direction)

	if _wip_south_ready and last_direction == "down":
		_set_wip_visual_active(true)
		var animation_name := "idle_down"
		if input_direction != Vector2.ZERO:
			animation_name = "run_down" if is_running else "walk_down"
		_play_wip_animation(animation_name)
		return

	_set_wip_visual_active(false)
	super._update_movement_animation(input_direction)


func _play_wip_animation(animation_name: StringName) -> void:
	if wip_south_sprite == null or wip_south_sprite.sprite_frames == null:
		return
	if not wip_south_sprite.sprite_frames.has_animation(animation_name):
		return
	if wip_south_sprite.animation == animation_name and wip_south_sprite.is_playing():
		return
	wip_south_sprite.play(animation_name)


func _set_wip_visual_active(active: bool) -> void:
	active = active and _wip_south_ready
	var changed := active != _wip_visual_active
	_wip_visual_active = active
	if wip_south_sprite != null:
		wip_south_sprite.visible = active
	if active:
		if animated_sprite != null:
			animated_sprite.visible = false
		if body_visual != null:
			body_visual.visible = false
	else:
		var has_fallback := animation_controller.has_any_valid_animation()
		if animated_sprite != null:
			animated_sprite.visible = has_fallback
		if body_visual != null:
			body_visual.visible = not has_fallback
	if changed and is_inside_tree():
		call_deferred("_refresh_player_directional_shadow_source")


func _start_attack_cycle() -> void:
	_set_wip_visual_active(false)
	super._start_attack_cycle()


func _start_dash(direction: Vector2) -> void:
	_set_wip_visual_active(false)
	super._start_dash(direction)


func _start_hurt_animation() -> void:
	_set_wip_visual_active(false)
	super._start_hurt_animation()


func _die() -> void:
	_set_wip_visual_active(false)
	super._die()


func _set_player_visual_alpha(alpha: float) -> void:
	super._set_player_visual_alpha(alpha)
	if wip_south_sprite != null:
		wip_south_sprite.modulate.a = alpha


func _play_hit_flash(flash_color: Color) -> void:
	super._play_hit_flash(flash_color)
	if wip_south_sprite == null or not wip_south_sprite.visible:
		return
	var original_color := wip_south_sprite.modulate
	wip_south_sprite.modulate = flash_color
	var tween := create_tween()
	tween.tween_property(wip_south_sprite, "modulate", original_color, 0.12)


func is_wip_south_ready() -> bool:
	return _wip_south_ready


func is_wip_visual_active() -> bool:
	return _wip_visual_active
