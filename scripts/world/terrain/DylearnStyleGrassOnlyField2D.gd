@tool
class_name DylearnStyleGrassOnlyField2D
extends Node2D

const GRASS_SHADER: Shader = preload(
	"res://shaders/terrain/dylearn_style_grass_2d.gdshader"
)

const GRASS_SPRITE_SIZE := Vector2i(40, 28)
const GRASS_SPRITE_COUNT := 14

@export_category("Reference V6 meadow")
@export var field_size_pixels := Vector2(3200.0, 2200.0)
@export var spacing_pixels := Vector2(18.0, 12.0)
@export var jitter_pixels := Vector2(3.0, 2.0)
@export var world_seed := 91373
@export var grass_quad_size_pixels := Vector2(40.0, 28.0)
@export_range(0.0002, 0.02, 0.0001) var density_frequency := 0.0022
@export_range(0.0002, 0.03, 0.0001) var density_detail_frequency := 0.0065
@export_range(0.0, 1.0, 0.01) var minimum_spawn_chance := 0.12
@export_range(0.0, 1.0, 0.01) var maximum_spawn_chance := 0.62
@export_range(0.0, 1.0, 0.01) var tall_cluster_threshold := 0.58
@export_range(0.0, 1.0, 0.01) var lush_cluster_threshold := 0.74
@export_range(0.0, 0.2, 0.001) var rare_weed_frequency := 0.018
@export var rebuild_on_ready := true
@export var ground_path := NodePath("../Ground")

@export_category("Reference palette: four greens")
@export var palette_shadow := Color(0.392157, 0.474510, 0.176471, 1.0)
@export var palette_dark_mid := Color(0.537255, 0.682353, 0.227451, 1.0)
@export var palette_mid_light := Color(0.650980, 0.756863, 0.294118, 1.0)
@export var palette_highlight := Color(0.768627, 0.827451, 0.349020, 1.0)
@export_range(0.00005, 0.01, 0.00005) var palette_field_scale_a := 0.00024
@export_range(0.00005, 0.01, 0.00005) var palette_field_scale_b := 0.00072
@export_range(0.0, 1.0, 0.001) var palette_threshold_1 := 0.24
@export_range(0.0, 1.0, 0.001) var palette_threshold_2 := 0.43
@export_range(0.0, 1.0, 0.001) var palette_threshold_3 := 0.68

@export_category("Coherent stepped wind")
@export_range(1.0, 16.0, 1.0) var stepped_framerate := 6.0
@export var wind_direction := Vector2(0.92, 0.38)
@export_range(0.0, 12.0, 0.1) var wind_strength_pixels := 3.0
@export_range(0.0001, 0.02, 0.0001) var wind_noise_scale := 0.00135
@export_range(0.0, 0.25, 0.001) var wind_noise_speed := 0.044
@export_range(0.0, 1.0, 0.001) var wind_noise_threshold := 0.36
@export_range(0.001, 0.5, 0.001) var wind_gust_width := 0.21
@export_range(0.0, 1.2, 0.01) var noise_diverge_angle := 0.23
@export_range(-0.5, 0.75, 0.01) var fake_perspective_scale := 0.05

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
	_build_meadow()
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
	_patch_noise_texture = _create_noise_texture(256, world_seed + 401, 0.012, 3)
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


func _build_meadow() -> void:
	var safe_spacing := Vector2(maxf(spacing_pixels.x, 4.0), maxf(spacing_pixels.y, 4.0))
	var columns := ceili(field_size_pixels.x / safe_spacing.x) + 2
	var rows := ceili(field_size_pixels.y / safe_spacing.y) + 2
	var start := -field_size_pixels * 0.5 - safe_spacing
	var density_noise := _create_cpu_noise(world_seed + 171, density_frequency, 3)
	var detail_noise := _create_cpu_noise(world_seed + 811, density_detail_frequency, 2)
	var instances: Array = []
	for y in range(rows):
		for x in range(columns):
			var cell := Vector2i(x, y)
			var rng := RandomNumberGenerator.new()
			rng.seed = _cell_seed(cell)
			var position := start + Vector2((float(x) + 0.5) * safe_spacing.x, (float(y) + 0.5) * safe_spacing.y)
			position += Vector2(float(rng.randi_range(-int(jitter_pixels.x), int(jitter_pixels.x))), float(rng.randi_range(-int(jitter_pixels.y), int(jitter_pixels.y))))
			position = position.round()
			var broad := (density_noise.get_noise_2d(position.x, position.y) + 1.0) * 0.5
			var detail := (detail_noise.get_noise_2d(position.x, position.y) + 1.0) * 0.5
			var density := clampf(broad * 0.82 + detail * 0.18, 0.0, 1.0)
			var density01 := clampf((density - 0.18) / 0.62, 0.0, 1.0)
			var spawn_chance := lerpf(minimum_spawn_chance, maximum_spawn_chance, density01)
			if rng.randf() > spawn_chance:
				continue
			instances.append({"position": position, "sprite": _pick_sprite_index_for_density(rng, density), "random": rng.randf()})
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_custom_data = true
	multimesh.mesh = _quad_mesh
	multimesh.instance_count = instances.size()
	for index in range(instances.size()):
		var entry: Dictionary = instances[index]
		var position: Vector2 = entry["position"]
		var sprite_index: int = entry["sprite"]
		var random_value: float = entry["random"]
		var flip_x := -1.0 if random_value < 0.5 else 1.0
		var root_anchor_offset := Vector2(0.0, -grass_quad_size_pixels.y * 0.5)
		var transform := Transform2D(0.0, Vector2(flip_x, 1.0), 0.0, position + root_anchor_offset)
		multimesh.set_instance_transform_2d(index, transform)
		multimesh.set_instance_custom_data(index, Color(random_value, float(sprite_index) / float(GRASS_SPRITE_COUNT - 1), _cell_random(index, 37), _cell_random(index, 101)))
	_grass_node = MultiMeshInstance2D.new()
	_grass_node.name = "ReferenceMeadowGrass"
	_grass_node.multimesh = multimesh
	_grass_node.material = _grass_material
	_grass_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_grass_node.z_index = 2
	add_child(_grass_node)


func _pick_sprite_index_for_density(rng: RandomNumberGenerator, density: float) -> int:
	var roll := rng.randf()
	if density >= lush_cluster_threshold:
		if roll < rare_weed_frequency:
			return 13
		if roll < 0.72:
			return rng.randi_range(8, 12)
		if roll < 0.88:
			return rng.randi_range(5, 7)
		return rng.randi_range(0, 4)
	if density >= tall_cluster_threshold:
		if roll < 0.46:
			return rng.randi_range(8, 12)
		if roll < 0.68:
			return rng.randi_range(5, 7)
		return rng.randi_range(0, 4)
	if roll < 0.18:
		return rng.randi_range(5, 7)
	if roll < 0.28:
		return rng.randi_range(8, 9)
	return rng.randi_range(0, 4)


func _create_grass_atlas() -> Texture2D:
	var image := Image.create(GRASS_SPRITE_SIZE.x * GRASS_SPRITE_COUNT, GRASS_SPRITE_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))
	for sprite_index in range(GRASS_SPRITE_COUNT):
		_paint_grass_sprite(image, sprite_index)
	return ImageTexture.create_from_image(image)


func _paint_grass_sprite(image: Image, sprite_index: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 12011 + sprite_index * 7919
	if sprite_index <= 4:
		_paint_low_grass(image, sprite_index, rng)
	elif sprite_index <= 7:
		_paint_ground_leaves(image, sprite_index, rng)
	elif sprite_index <= 12:
		_paint_tall_grass(image, sprite_index, rng)
	else:
		_paint_tall_weed(image, sprite_index, rng)


func _paint_low_grass(image: Image, sprite_index: int, rng: RandomNumberGenerator) -> void:
	var x_offset := sprite_index * GRASS_SPRITE_SIZE.x
	var blade_count := 4 + sprite_index % 3
	for blade_index in range(blade_count):
		var base_x := rng.randi_range(5, 34)
		var base_y := rng.randi_range(22, 26)
		var tip_x := clampi(base_x + rng.randi_range(-4, 4), 2, 37)
		var tip_y := rng.randi_range(14, 20)
		_paint_thick_line(image, x_offset, base_x, base_y, tip_x, tip_y, 2)
	for patch_index in range(2 + sprite_index % 2):
		var px := rng.randi_range(4, 34)
		var py := rng.randi_range(23, 26)
		_paint_rect(image, x_offset, px, py, rng.randi_range(3, 6), 2)


func _paint_ground_leaves(image: Image, sprite_index: int, rng: RandomNumberGenerator) -> void:
	var x_offset := sprite_index * GRASS_SPRITE_SIZE.x
	var centre_x := rng.randi_range(14, 26)
	var centre_y := rng.randi_range(22, 25)
	var leaf_count := 4 + (sprite_index - 5)
	for leaf_index in range(leaf_count):
		var side := -1 if leaf_index % 2 == 0 else 1
		var spread := 3 + leaf_index * 2
		var tip_x := clampi(centre_x + side * spread + rng.randi_range(-2, 2), 2, 37)
		var tip_y := clampi(centre_y - rng.randi_range(3, 7), 12, 23)
		_paint_thick_line(image, x_offset, centre_x, centre_y, tip_x, tip_y, 3)


func _paint_tall_grass(image: Image, sprite_index: int, rng: RandomNumberGenerator) -> void:
	var x_offset := sprite_index * GRASS_SPRITE_SIZE.x
	var density_boost := sprite_index - 8
	var blade_count := 5 + density_boost
	var cluster_centre := rng.randi_range(15, 25)
	for blade_index in range(blade_count):
		var base_x := clampi(cluster_centre + rng.randi_range(-10, 10), 4, 35)
		var base_y := rng.randi_range(23, 26)
		var tip_x := clampi(base_x + rng.randi_range(-5, 5), 2, 37)
		var min_tip := 4 if sprite_index >= 11 else 7
		var max_tip := 13 if sprite_index <= 9 else 10
		var tip_y := rng.randi_range(min_tip, max_tip)
		var width := 3 if blade_index % 3 == 0 else 2
		_paint_thick_line(image, x_offset, base_x, base_y, tip_x, tip_y, width)
	if sprite_index >= 10:
		for side_leaf in range(2):
			var side := -1 if side_leaf == 0 else 1
			var base_x := cluster_centre + rng.randi_range(-2, 2)
			var base_y := rng.randi_range(16, 21)
			_paint_thick_line(image, x_offset, base_x, base_y, clampi(base_x + side * rng.randi_range(5, 8), 2, 37), base_y - rng.randi_range(2, 5), 3)


func _paint_tall_weed(image: Image, sprite_index: int, rng: RandomNumberGenerator) -> void:
	var x_offset := sprite_index * GRASS_SPRITE_SIZE.x
	var stem_x := rng.randi_range(18, 22)
	_paint_thick_line(image, x_offset, stem_x, 26, stem_x + rng.randi_range(-2, 2), 2, 2)
	for leaf_index in range(5):
		var side := -1 if leaf_index % 2 == 0 else 1
		var base_y := 8 + leaf_index * 3
		var base_x := stem_x + rng.randi_range(-1, 1)
		_paint_thick_line(image, x_offset, base_x, base_y, clampi(base_x + side * rng.randi_range(5, 8), 2, 37), base_y - rng.randi_range(1, 4), 3)


func _paint_thick_line(image: Image, x_offset: int, base_x: int, base_y: int, tip_x: int, tip_y: int, width: int) -> void:
	var dx := float(tip_x - base_x)
	var dy := float(tip_y - base_y)
	var steps := maxi(abs(tip_x - base_x), abs(tip_y - base_y))
	steps = maxi(steps, 1)
	for step in range(steps + 1):
		var t := float(step) / float(steps)
		var x := roundi(float(base_x) + dx * t)
		var y := roundi(float(base_y) + dy * t)
		var brush_width := width
		if t > 0.78:
			brush_width = maxi(2, width - 1)
		_paint_square_brush(image, x_offset, x, y, brush_width)


func _paint_square_brush(image: Image, x_offset: int, x: int, y: int, width: int) -> void:
	var start := -floori(float(width) * 0.5)
	var finish := start + width - 1
	for oy in range(start, finish + 1):
		for ox in range(start, finish + 1):
			var px := clampi(x + ox, 0, GRASS_SPRITE_SIZE.x - 1)
			var py := clampi(y + oy, 0, GRASS_SPRITE_SIZE.y - 1)
			image.set_pixel(x_offset + px, py, Color.WHITE)


func _paint_rect(image: Image, x_offset: int, x: int, y: int, width: int, height: int) -> void:
	for oy in range(height):
		for ox in range(width):
			var px := clampi(x + ox, 0, GRASS_SPRITE_SIZE.x - 1)
			var py := clampi(y + oy, 0, GRASS_SPRITE_SIZE.y - 1)
			image.set_pixel(x_offset + px, py, Color.WHITE)


func _create_cpu_noise(noise_seed: int, frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.fractal_gain = 0.5
	noise.fractal_lacunarity = 2.0
	return noise


func _create_noise_texture(size: int, noise_seed: int, frequency: float, octaves: int) -> Texture2D:
	var noise := _create_cpu_noise(noise_seed, frequency, octaves)
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
		displacer_value = Vector3(_resolved_displacer.global_position.x, _resolved_displacer.global_position.y, displacement_radius_pixels)
	_grass_material.set_shader_parameter("displacer", displacer_value)


func _cell_seed(cell: Vector2i) -> int:
	var seed_value := int(world_seed)
	seed_value ^= cell.x * 73856093
	seed_value ^= cell.y * 19349663
	seed_value ^= (cell.x + cell.y) * 83492791
	return absi(seed_value)


func _cell_random(index: int, salt: int) -> float:
	var value := int(world_seed) ^ (index * 1103515245) ^ (salt * 12345)
	value = absi(value % 1000003)
	return float(value) / 1000003.0


func _clear_grass() -> void:
	if _grass_node != null and is_instance_valid(_grass_node):
		_grass_node.queue_free()
	_grass_node = null
	_grass_material = null
	_quad_mesh = null
	_patch_noise_texture = null
	_wind_noise_texture = null
