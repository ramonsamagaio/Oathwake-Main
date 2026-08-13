@tool
class_name DylearnStyleGrassOnlyField2D
extends Node2D

const GRASS_SHADER: Shader = preload(
	"res://shaders/terrain/dylearn_style_grass_2d.gdshader"
)

const CLUMP_SPRITE_SIZE := Vector2i(32, 24)
const CLUMP_SPRITE_COUNT := 8

@export_category("Dense carpet")
@export var field_size_pixels := Vector2(3200.0, 2200.0)
@export var spacing_pixels := Vector2(18.0, 11.0)
@export var jitter_pixels := Vector2(5.0, 3.0)
@export var world_seed := 91373
@export var min_scale := 0.90
@export var max_scale := 1.16
@export var rotation_variation_radians := 0.022
@export var grass_quad_size_pixels := Vector2(40.0, 28.0)
@export var accent_a_frequency := 0.022
@export var accent_b_frequency := 0.007
@export var rebuild_on_ready := true
@export var ground_path := NodePath("../Ground")

@export_category("Colour / shared toon field")
@export var grass_color_base := Color(0.195, 0.355, 0.082, 1.0)
@export var grass_color_patch_a := Color(0.285, 0.455, 0.105, 1.0)
@export var grass_color_patch_b := Color(0.115, 0.255, 0.060, 1.0)
@export var accent_color_a := Color(0.355, 0.510, 0.105, 1.0)
@export var accent_color_b := Color(0.285, 0.420, 0.082, 1.0)
@export_range(0.0001, 0.01, 0.0001) var patch_scale_a := 0.00065
@export_range(0.0001, 0.01, 0.0001) var patch_scale_b := 0.00165
@export_range(0.0, 1.0, 0.001) var patch_threshold_a := 0.60
@export_range(0.0, 1.0, 0.001) var patch_threshold_b := 0.73
@export_range(0.0001, 0.01, 0.0001) var toon_field_scale := 0.00072
@export_range(0.0, 1.0, 0.001) var toon_shadow_threshold := 0.38
@export_range(0.0, 1.0, 0.001) var toon_highlight_threshold := 0.64
@export_range(0.001, 0.2, 0.001) var toon_transition := 0.028
@export_range(0.1, 2.0, 0.01) var toon_shadow_factor := 0.68
@export_range(0.1, 2.0, 0.01) var toon_mid_factor := 0.92
@export_range(0.1, 2.0, 0.01) var toon_highlight_factor := 1.14

@export_category("Coherent stepped wind")
@export_range(1.0, 16.0, 1.0) var stepped_framerate := 6.0
@export var wind_direction := Vector2(0.92, 0.38)
@export_range(0.0, 12.0, 0.1) var wind_strength_pixels := 3.6
@export_range(0.0001, 0.02, 0.0001) var wind_noise_scale := 0.00155
@export_range(0.0, 0.25, 0.001) var wind_noise_speed := 0.050
@export_range(0.0, 1.0, 0.001) var wind_noise_threshold := 0.34
@export_range(0.001, 0.5, 0.001) var wind_gust_width := 0.19
@export_range(0.0, 1.2, 0.01) var noise_diverge_angle := 0.23
@export_range(-0.5, 0.75, 0.01) var fake_perspective_scale := 0.16

@export_category("Interaction")
@export var displacer_group := &"grass_displacer"
@export_range(0.0, 128.0, 1.0) var displacement_radius_pixels := 42.0
@export_range(0.0, 20.0, 0.1) var displacement_strength_pixels := 7.0
@export_range(0.1, 6.0, 0.1) var displacement_radius_exponent := 1.55
@export_range(0.01, 0.5, 0.01) var interaction_update_interval := 0.05

var _grass_material: ShaderMaterial
var _grass_node: MultiMeshInstance2D
var _quad_mesh: QuadMesh
var _patch_noise_texture: Texture2D
var _wind_noise_texture: Texture2D
var _resolved_displacer: Node2D
var _interaction_accumulator := 0.0
var _step_accumulator := 0.0
var _stepped_time := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	set_process(true)
	if rebuild_on_ready:
		call_deferred("rebuild")


func _process(delta: float) -> void:
	if _grass_material == null:
		return

	_step_accumulator += delta
	var step_interval := 1.0 / maxf(stepped_framerate, 1.0)
	if _step_accumulator >= step_interval:
		var step_count := floori(_step_accumulator / step_interval)
		_step_accumulator -= float(step_count) * step_interval
		_stepped_time += float(step_count) * step_interval
		_grass_material.set_shader_parameter("stepped_time", _stepped_time)

	_interaction_accumulator += delta
	if _interaction_accumulator >= interaction_update_interval:
		_interaction_accumulator = 0.0
		_update_displacer()


func rebuild() -> void:
	if Engine.is_editor_hint():
		return

	_clear_grass()
	_prepare_resources()
	_build_dense_carpet()
	_update_displacer()


func get_total_tuft_count() -> int:
	if _grass_node == null or _grass_node.multimesh == null:
		return 0
	return _grass_node.multimesh.instance_count


func get_visible_tuft_count() -> int:
	return get_total_tuft_count()


func set_wind_direction(new_direction: Vector2) -> void:
	if new_direction.length_squared() < 0.0001:
		return
	wind_direction = new_direction.normalized()
	if _grass_material != null:
		_grass_material.set_shader_parameter("wind_direction", wind_direction)


func _prepare_resources() -> void:
	var grass_atlas := _create_grass_atlas()
	_patch_noise_texture = _create_noise_texture(256, world_seed + 401, 0.018, 4)
	_wind_noise_texture = _create_noise_texture(128, world_seed + 977, 0.027, 3)

	_grass_material = ShaderMaterial.new()
	_grass_material.shader = GRASS_SHADER
	_grass_material.set_shader_parameter("grass_atlas", grass_atlas)
	_grass_material.set_shader_parameter("patch_noise", _patch_noise_texture)
	_grass_material.set_shader_parameter("wind_noise", _wind_noise_texture)
	_grass_material.set_shader_parameter("grass_color_base", grass_color_base)
	_grass_material.set_shader_parameter("grass_color_patch_a", grass_color_patch_a)
	_grass_material.set_shader_parameter("grass_color_patch_b", grass_color_patch_b)
	_grass_material.set_shader_parameter("accent_color_a", accent_color_a)
	_grass_material.set_shader_parameter("accent_color_b", accent_color_b)
	_grass_material.set_shader_parameter("patch_scale_a", patch_scale_a)
	_grass_material.set_shader_parameter("patch_scale_b", patch_scale_b)
	_grass_material.set_shader_parameter("patch_threshold_a", patch_threshold_a)
	_grass_material.set_shader_parameter("patch_threshold_b", patch_threshold_b)
	_grass_material.set_shader_parameter("toon_field_scale", toon_field_scale)
	_grass_material.set_shader_parameter("toon_shadow_threshold", toon_shadow_threshold)
	_grass_material.set_shader_parameter("toon_highlight_threshold", toon_highlight_threshold)
	_grass_material.set_shader_parameter("toon_transition", toon_transition)
	_grass_material.set_shader_parameter("toon_shadow_factor", toon_shadow_factor)
	_grass_material.set_shader_parameter("toon_mid_factor", toon_mid_factor)
	_grass_material.set_shader_parameter("toon_highlight_factor", toon_highlight_factor)
	_grass_material.set_shader_parameter("stepped_time", _stepped_time)
	_grass_material.set_shader_parameter("wind_direction", wind_direction.normalized())
	_grass_material.set_shader_parameter("wind_strength_pixels", wind_strength_pixels)
	_grass_material.set_shader_parameter("wind_noise_scale", wind_noise_scale)
	_grass_material.set_shader_parameter("wind_noise_speed", wind_noise_speed)
	_grass_material.set_shader_parameter("wind_noise_threshold", wind_noise_threshold)
	_grass_material.set_shader_parameter("wind_gust_width", wind_gust_width)
	_grass_material.set_shader_parameter("noise_diverge_angle", noise_diverge_angle)
	_grass_material.set_shader_parameter("fake_perspective_scale", fake_perspective_scale)
	_grass_material.set_shader_parameter("displacement_strength_pixels", displacement_strength_pixels)
	_grass_material.set_shader_parameter("radius_exponent", displacement_radius_exponent)
	_grass_material.set_shader_parameter("quad_size_pixels", grass_quad_size_pixels)

	_quad_mesh = QuadMesh.new()
	_quad_mesh.size = grass_quad_size_pixels
	_apply_ground_shared_parameters()


func _build_dense_carpet() -> void:
	var safe_spacing := Vector2(
		maxf(spacing_pixels.x, 4.0),
		maxf(spacing_pixels.y, 4.0)
	)
	var columns := ceili(field_size_pixels.x / safe_spacing.x) + 2
	var rows := ceili(field_size_pixels.y / safe_spacing.y) + 2
	var instance_count := columns * rows
	var start := -field_size_pixels * 0.5 - safe_spacing

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_custom_data = true
	multimesh.mesh = _quad_mesh
	multimesh.instance_count = instance_count

	var index := 0
	for y in range(rows):
		for x in range(columns):
			var cell := Vector2i(x, y)
			var rng := RandomNumberGenerator.new()
			rng.seed = _cell_seed(cell)

			var position := start + Vector2(
				(float(x) + 0.5) * safe_spacing.x,
				(float(y) + 0.5) * safe_spacing.y
			)
			position += Vector2(
				rng.randf_range(-jitter_pixels.x, jitter_pixels.x),
				rng.randf_range(-jitter_pixels.y, jitter_pixels.y)
			)

			var scale_value := rng.randf_range(min_scale, max_scale)
			var flip_x := -1.0 if rng.randf() < 0.5 else 1.0
			var scale := Vector2(scale_value * flip_x, scale_value)
			var rotation := rng.randf_range(
				-rotation_variation_radians,
				rotation_variation_radians
			)
			var root_anchor_offset := Vector2(
				0.0,
				-grass_quad_size_pixels.y * absf(scale.y) * 0.5
			)
			var transform := Transform2D(
				rotation,
				scale,
				0.0,
				position + root_anchor_offset
			)

			var sprite_index := _pick_sprite_index(rng)
			multimesh.set_instance_transform_2d(index, transform)
			multimesh.set_instance_custom_data(
				index,
				Color(
					rng.randf(),
					float(sprite_index) / float(CLUMP_SPRITE_COUNT - 1),
					rng.randf_range(0.72, 1.0),
					rng.randf()
				)
			)
			index += 1

	_grass_node = MultiMeshInstance2D.new()
	_grass_node.name = "DenseGrassCarpet"
	_grass_node.multimesh = multimesh
	_grass_node.material = _grass_material
	_grass_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_grass_node.z_index = 2
	add_child(_grass_node)


func _create_grass_atlas() -> Texture2D:
	var atlas_width := CLUMP_SPRITE_SIZE.x * CLUMP_SPRITE_COUNT
	var image := Image.create(
		atlas_width,
		CLUMP_SPRITE_SIZE.y,
		false,
		Image.FORMAT_RGBA8
	)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))

	for sprite_index in range(CLUMP_SPRITE_COUNT):
		_paint_clump(image, sprite_index)

	return ImageTexture.create_from_image(image)


func _paint_clump(image: Image, sprite_index: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 12011 + sprite_index * 7919
	var width := CLUMP_SPRITE_SIZE.x
	var height := CLUMP_SPRITE_SIZE.y
	var x_offset := sprite_index * width
	var center := (float(width) - 1.0) * 0.5
	var accent := sprite_index >= 6

	# A broad opaque body is intentional. Heavy overlap plus the matching floor
	# palette makes neighbouring cards fuse into one carpet instead of reading as
	# hundreds of independent Y-shaped stamps.
	for x in range(width):
		var edge := absf(float(x) - center) / center
		var top := 11 + roundi(edge * 4.0) + rng.randi_range(-2, 2)
		var bottom := 22 - roundi(maxf(edge - 0.72, 0.0) * 9.0)
		bottom += rng.randi_range(-1, 1)
		top = clampi(top, 8, 17)
		bottom = clampi(bottom, top + 2, height - 1)
		for y in range(top, bottom + 1):
			image.set_pixel(x_offset + x, y, Color.WHITE)

	var blade_count := 13 + sprite_index % 4
	if accent:
		blade_count += 4
	for blade_index in range(blade_count):
		var base_x := rng.randi_range(3, width - 4)
		var base_y := rng.randi_range(13, 19)
		var tip_x := clampi(base_x + rng.randi_range(-6, 6), 1, width - 2)
		var min_tip_y := 0 if accent and blade_index < 5 else 3
		var tip_y := rng.randi_range(min_tip_y, 10)
		_paint_pixel_blade(image, x_offset, base_x, base_y, tip_x, tip_y)

	# Tiny side leaves break the rectangular silhouette and make the cards knit
	# together at their boundaries.
	for leaf_index in range(7):
		var side := -1 if leaf_index % 2 == 0 else 1
		var base_x := rng.randi_range(7, width - 8)
		var base_y := rng.randi_range(11, 18)
		var tip_x := clampi(base_x + side * rng.randi_range(4, 8), 1, width - 2)
		var tip_y := clampi(base_y - rng.randi_range(2, 6), 3, height - 2)
		_paint_pixel_blade(image, x_offset, base_x, base_y, tip_x, tip_y)


func _paint_pixel_blade(
	image: Image,
	x_offset: int,
	base_x: int,
	base_y: int,
	tip_x: int,
	tip_y: int
) -> void:
	var dx := float(tip_x - base_x)
	var dy := float(tip_y - base_y)
	var steps := maxi(abs(tip_x - base_x), abs(tip_y - base_y))
	steps = maxi(steps, 1)

	for step in range(steps + 1):
		var t := float(step) / float(steps)
		var x := roundi(float(base_x) + dx * t)
		var y := roundi(float(base_y) + dy * t)
		var radius := 1 if t < 0.42 else 0
		for ox in range(-radius, radius + 1):
			var px := clampi(x + ox, 0, CLUMP_SPRITE_SIZE.x - 1)
			var py := clampi(y, 0, CLUMP_SPRITE_SIZE.y - 1)
			image.set_pixel(x_offset + px, py, Color.WHITE)


func _create_noise_texture(
	size: int,
	noise_seed: int,
	frequency: float,
	octaves: int
) -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.fractal_gain = 0.5
	noise.fractal_lacunarity = 2.0
	var image := noise.get_seamless_image(size, size, false, false, 0.15, true)
	return ImageTexture.create_from_image(image)


func _apply_ground_shared_parameters() -> void:
	var ground := get_node_or_null(ground_path) as MeshInstance2D
	if ground == null or not (ground.material is ShaderMaterial):
		return
	var material := ground.material as ShaderMaterial
	material.set_shader_parameter("patch_noise", _patch_noise_texture)
	material.set_shader_parameter("patch_scale_a", patch_scale_a)
	material.set_shader_parameter("patch_scale_b", patch_scale_b)
	material.set_shader_parameter("patch_threshold_a", patch_threshold_a)
	material.set_shader_parameter("patch_threshold_b", patch_threshold_b)
	material.set_shader_parameter("toon_field_scale", toon_field_scale)
	material.set_shader_parameter("toon_shadow_threshold", toon_shadow_threshold)
	material.set_shader_parameter("toon_highlight_threshold", toon_highlight_threshold)
	material.set_shader_parameter("toon_transition", toon_transition)
	material.set_shader_parameter("toon_shadow_factor", toon_shadow_factor)
	material.set_shader_parameter("toon_mid_factor", toon_mid_factor)
	material.set_shader_parameter("toon_highlight_factor", toon_highlight_factor)


func _update_displacer() -> void:
	if _grass_material == null:
		return
	if _resolved_displacer == null or not is_instance_valid(_resolved_displacer):
		_resolved_displacer = get_tree().get_first_node_in_group(
			displacer_group
		) as Node2D

	var displacer_value := Vector3(-100000.0, -100000.0, 1.0)
	if _resolved_displacer != null:
		displacer_value = Vector3(
			_resolved_displacer.global_position.x,
			_resolved_displacer.global_position.y,
			displacement_radius_pixels
		)
	_grass_material.set_shader_parameter("displacer", displacer_value)


func _pick_sprite_index(rng: RandomNumberGenerator) -> int:
	var roll := rng.randf()
	if roll < accent_b_frequency:
		return 7
	if roll < accent_b_frequency + accent_a_frequency:
		return 6
	return rng.randi_range(0, 5)


func _cell_seed(cell: Vector2i) -> int:
	var seed_value := int(world_seed)
	seed_value ^= cell.x * 73856093
	seed_value ^= cell.y * 19349663
	seed_value ^= (cell.x + cell.y) * 83492791
	return absi(seed_value)


func _clear_grass() -> void:
	if _grass_node != null and is_instance_valid(_grass_node):
		_grass_node.queue_free()
	_grass_node = null
	_grass_material = null
	_quad_mesh = null
	_patch_noise_texture = null
	_wind_noise_texture = null
