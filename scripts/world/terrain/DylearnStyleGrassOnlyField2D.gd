@tool
class_name DylearnStyleGrassOnlyField2D
extends Node2D

const GRASS_SHADER: Shader = preload(
	"res://shaders/terrain/dylearn_style_grass_2d.gdshader"
)

const CLUMP_SPRITE_SIZE := Vector2i(40, 28)
const CLUMP_SPRITE_COUNT := 12

@export_category("Reference V5 pixel carpet")
@export var field_size_pixels := Vector2(3200.0, 2200.0)
@export var spacing_pixels := Vector2(20.0, 12.0)
@export var jitter_pixels := Vector2(4.0, 2.0)
@export var world_seed := 91373
@export var grass_quad_size_pixels := Vector2(40.0, 28.0)
@export_range(0.0, 0.5, 0.001) var ground_leaf_frequency := 0.11
@export_range(0.0, 0.5, 0.001) var tall_grass_frequency := 0.08
@export_range(0.0, 0.2, 0.001) var tall_weed_frequency := 0.025
@export var rebuild_on_ready := true
@export var ground_path := NodePath("../Ground")

@export_category("Reference palette: exactly four greens")
# Sampled from the supplied image-3 reference. These are the only greens that
# the ground/grass shaders are allowed to output.
@export var palette_shadow := Color(0.278431, 0.364706, 0.117647, 1.0) # #475D1E
@export var palette_dark_mid := Color(0.513725, 0.643137, 0.211765, 1.0) # #83A436
@export var palette_mid_light := Color(0.650980, 0.749020, 0.294118, 1.0) # #A6BF4B
@export var palette_highlight := Color(0.764706, 0.827451, 0.356863, 1.0) # #C3D35B
@export_range(0.0001, 0.01, 0.0001) var palette_field_scale_a := 0.00058
@export_range(0.0001, 0.01, 0.0001) var palette_field_scale_b := 0.00145
@export_range(0.0, 1.0, 0.001) var palette_threshold_1 := 0.30
@export_range(0.0, 1.0, 0.001) var palette_threshold_2 := 0.50
@export_range(0.0, 1.0, 0.001) var palette_threshold_3 := 0.68

@export_category("Coherent stepped wind")
@export_range(1.0, 16.0, 1.0) var stepped_framerate := 6.0
@export var wind_direction := Vector2(0.92, 0.38)
@export_range(0.0, 12.0, 0.1) var wind_strength_pixels := 3.2
@export_range(0.0001, 0.02, 0.0001) var wind_noise_scale := 0.00145
@export_range(0.0, 0.25, 0.001) var wind_noise_speed := 0.046
@export_range(0.0, 1.0, 0.001) var wind_noise_threshold := 0.35
@export_range(0.001, 0.5, 0.001) var wind_gust_width := 0.20
@export_range(0.0, 1.2, 0.01) var noise_diverge_angle := 0.23
@export_range(-0.5, 0.75, 0.01) var fake_perspective_scale := 0.08

@export_category("Interaction")
@export var displacer_group := &"grass_displacer"
@export_range(0.0, 128.0, 1.0) var displacement_radius_pixels := 42.0
@export_range(0.0, 20.0, 0.1) var displacement_strength_pixels := 6.0
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
	_patch_noise_texture = _create_noise_texture(256, world_seed + 401, 0.017, 4)
	_wind_noise_texture = _create_noise_texture(128, world_seed + 977, 0.027, 3)

	_grass_material = ShaderMaterial.new()
	_grass_material.shader = GRASS_SHADER
	_grass_material.set_shader_parameter("grass_atlas", grass_atlas)
	_grass_material.set_shader_parameter("patch_noise", _patch_noise_texture)
	_grass_material.set_shader_parameter("wind_noise", _wind_noise_texture)
	_grass_material.set_shader_parameter("palette_shadow", palette_shadow)
	_grass_material.set_shader_parameter("palette_dark_mid", palette_dark_mid)
	_grass_material.set_shader_parameter("palette_mid_light", palette_mid_light)
	_grass_material.set_shader_parameter("palette_highlight", palette_highlight)
	_grass_material.set_shader_parameter("palette_field_scale_a", palette_field_scale_a)
	_grass_material.set_shader_parameter("palette_field_scale_b", palette_field_scale_b)
	_grass_material.set_shader_parameter("palette_threshold_1", palette_threshold_1)
	_grass_material.set_shader_parameter("palette_threshold_2", palette_threshold_2)
	_grass_material.set_shader_parameter("palette_threshold_3", palette_threshold_3)
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
				float(rng.randi_range(-int(jitter_pixels.x), int(jitter_pixels.x))),
				float(rng.randi_range(-int(jitter_pixels.y), int(jitter_pixels.y)))
			)
			position = position.round()

			# Pixel-perfect rule: no fractional scale and no rotation. Horizontal
			# mirroring gives variation without changing source-pixel size.
			var flip_x := -1.0 if rng.randf() < 0.5 else 1.0
			var scale := Vector2(flip_x, 1.0)
			var root_anchor_offset := Vector2(0.0, -grass_quad_size_pixels.y * 0.5)
			var transform := Transform2D(0.0, scale, 0.0, position + root_anchor_offset)

			var sprite_index := _pick_sprite_index(rng)
			multimesh.set_instance_transform_2d(index, transform)
			multimesh.set_instance_custom_data(
				index,
				Color(
					rng.randf_range(0.78, 1.0),
					float(sprite_index) / float(CLUMP_SPRITE_COUNT - 1),
					rng.randf(),
					rng.randf()
				)
			)
			index += 1

	_grass_node = MultiMeshInstance2D.new()
	_grass_node.name = "ReferenceGrassCarpet"
	_grass_node.multimesh = multimesh
	_grass_node.material = _grass_material
	_grass_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_grass_node.z_index = 2
	add_child(_grass_node)


func _create_grass_atlas() -> Texture2D:
	var atlas_width := CLUMP_SPRITE_SIZE.x * CLUMP_SPRITE_COUNT
	var image := Image.create(atlas_width, CLUMP_SPRITE_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))

	for sprite_index in range(CLUMP_SPRITE_COUNT):
		_paint_clump(image, sprite_index)

	return ImageTexture.create_from_image(image)


func _paint_clump(image: Image, sprite_index: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 12011 + sprite_index * 7919
	_paint_low_carpet_base(image, sprite_index, rng)

	if sprite_index <= 5:
		_paint_short_grass(image, sprite_index, rng)
	elif sprite_index <= 8:
		_paint_ground_leaf_patch(image, sprite_index, rng)
	elif sprite_index <= 10:
		_paint_tall_grass(image, sprite_index, rng)
	else:
		_paint_tall_weed(image, sprite_index, rng)


func _paint_low_carpet_base(image: Image, sprite_index: int, rng: RandomNumberGenerator) -> void:
	var width := CLUMP_SPRITE_SIZE.x
	var height := CLUMP_SPRITE_SIZE.y
	var x_offset := sprite_index * width
	var center := (float(width) - 1.0) * 0.5

	# Only the bottom 6-10 pixels form a filled mass. Adjacent cards overlap this
	# band, producing the fused carpet while still leaving readable blades above.
	for x in range(width):
		var edge := absf(float(x) - center) / center
		var top := 19 + roundi(edge * 3.0) + rng.randi_range(-1, 1)
		var bottom := 27 - roundi(maxf(edge - 0.78, 0.0) * 8.0)
		top = clampi(top, 17, 23)
		bottom = clampi(bottom, top + 2, height - 1)
		for y in range(top, bottom + 1):
			image.set_pixel(x_offset + x, y, Color.WHITE)

	# Chunky 2x2 cutouts prevent the lower mass from reading as a rectangle.
	for hole_index in range(5):
		var hx := rng.randi_range(4, width - 6)
		var hy := rng.randi_range(21, 25)
		for oy in range(2):
			for ox in range(2):
				image.set_pixel(x_offset + hx + ox, hy + oy, Color(1.0, 1.0, 1.0, 0.0))


func _paint_short_grass(image: Image, sprite_index: int, rng: RandomNumberGenerator) -> void:
	var x_offset := sprite_index * CLUMP_SPRITE_SIZE.x
	var blade_count := 7 + sprite_index % 3
	for blade_index in range(blade_count):
		var base_x := rng.randi_range(4, CLUMP_SPRITE_SIZE.x - 5)
		var base_y := rng.randi_range(20, 24)
		var tip_x := clampi(base_x + rng.randi_range(-4, 4), 2, CLUMP_SPRITE_SIZE.x - 3)
		var tip_y := rng.randi_range(11, 18)
		_paint_thick_line(image, x_offset, base_x, base_y, tip_x, tip_y, 3)


func _paint_ground_leaf_patch(image: Image, sprite_index: int, rng: RandomNumberGenerator) -> void:
	var x_offset := sprite_index * CLUMP_SPRITE_SIZE.x
	var cluster_x := rng.randi_range(12, 27)
	var cluster_y := rng.randi_range(19, 23)
	var leaf_count := 4 + sprite_index % 2
	for leaf_index in range(leaf_count):
		var angle_step := leaf_index - leaf_count / 2
		var tip_x := clampi(cluster_x + angle_step * 4 + rng.randi_range(-2, 2), 3, 36)
		var tip_y := clampi(cluster_y - rng.randi_range(4, 9), 8, 21)
		_paint_thick_line(image, x_offset, cluster_x, cluster_y, tip_x, tip_y, 4)

	# A second smaller rosette keeps the pattern from becoming one repeated stamp.
	if sprite_index == 8:
		var second_x := rng.randi_range(7, 13)
		var second_y := rng.randi_range(21, 24)
		for leaf_index in range(3):
			_paint_thick_line(
				image,
				x_offset,
				second_x,
				second_y,
				second_x + rng.randi_range(-5, 5),
				second_y - rng.randi_range(4, 7),
				3
			)


func _paint_tall_grass(image: Image, sprite_index: int, rng: RandomNumberGenerator) -> void:
	var x_offset := sprite_index * CLUMP_SPRITE_SIZE.x
	var blade_count := 6 + sprite_index % 2
	for blade_index in range(blade_count):
		var base_x := rng.randi_range(8, 32)
		var base_y := rng.randi_range(21, 25)
		var tip_x := clampi(base_x + rng.randi_range(-6, 6), 2, 37)
		var tip_y := rng.randi_range(2, 11)
		_paint_thick_line(image, x_offset, base_x, base_y, tip_x, tip_y, 3)


func _paint_tall_weed(image: Image, sprite_index: int, rng: RandomNumberGenerator) -> void:
	var x_offset := sprite_index * CLUMP_SPRITE_SIZE.x
	var stem_x := rng.randi_range(17, 23)
	_paint_thick_line(image, x_offset, stem_x, 25, stem_x + rng.randi_range(-2, 2), 2, 3)

	for leaf_index in range(5):
		var side := -1 if leaf_index % 2 == 0 else 1
		var base_y := 8 + leaf_index * 3
		var base_x := stem_x + rng.randi_range(-1, 1)
		var tip_x := clampi(base_x + side * rng.randi_range(5, 8), 2, 37)
		var tip_y := clampi(base_y - rng.randi_range(1, 4), 2, 24)
		_paint_thick_line(image, x_offset, base_x, base_y, tip_x, tip_y, 4)


func _paint_thick_line(
	image: Image,
	x_offset: int,
	base_x: int,
	base_y: int,
	tip_x: int,
	tip_y: int,
	base_width: int
) -> void:
	var dx := float(tip_x - base_x)
	var dy := float(tip_y - base_y)
	var steps := maxi(abs(tip_x - base_x), abs(tip_y - base_y))
	steps = maxi(steps, 1)

	for step in range(steps + 1):
		var t := float(step) / float(steps)
		var x := roundi(float(base_x) + dx * t)
		var y := roundi(float(base_y) + dy * t)
		var width := base_width
		if t > 0.72:
			width = maxi(2, base_width - 1)
		_paint_square_brush(image, x_offset, x, y, width)


func _paint_square_brush(image: Image, x_offset: int, x: int, y: int, width: int) -> void:
	var start := -floori(float(width) * 0.5)
	var finish := start + width - 1
	for oy in range(start, finish + 1):
		for ox in range(start, finish + 1):
			var px := clampi(x + ox, 0, CLUMP_SPRITE_SIZE.x - 1)
			var py := clampi(y + oy, 0, CLUMP_SPRITE_SIZE.y - 1)
			image.set_pixel(x_offset + px, py, Color.WHITE)


func _create_noise_texture(size: int, noise_seed: int, frequency: float, octaves: int) -> Texture2D:
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
	material.set_shader_parameter("palette_shadow", palette_shadow)
	material.set_shader_parameter("palette_dark_mid", palette_dark_mid)
	material.set_shader_parameter("palette_mid_light", palette_mid_light)
	material.set_shader_parameter("palette_highlight", palette_highlight)
	material.set_shader_parameter("palette_field_scale_a", palette_field_scale_a)
	material.set_shader_parameter("palette_field_scale_b", palette_field_scale_b)
	material.set_shader_parameter("palette_threshold_1", palette_threshold_1)
	material.set_shader_parameter("palette_threshold_2", palette_threshold_2)
	material.set_shader_parameter("palette_threshold_3", palette_threshold_3)


func _update_displacer() -> void:
	if _grass_material == null:
		return
	if _resolved_displacer == null or not is_instance_valid(_resolved_displacer):
		_resolved_displacer = get_tree().get_first_node_in_group(displacer_group) as Node2D

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
	if roll < tall_weed_frequency:
		return 11
	if roll < tall_weed_frequency + tall_grass_frequency:
		return rng.randi_range(9, 10)
	if roll < tall_weed_frequency + tall_grass_frequency + ground_leaf_frequency:
		return rng.randi_range(6, 8)
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
