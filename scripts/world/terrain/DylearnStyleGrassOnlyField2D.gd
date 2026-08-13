@tool
class_name DylearnStyleGrassOnlyField2D
extends Node2D

const GRASS_SHADER: Shader = preload("res://shaders/terrain/dylearn_style_grass_2d.gdshader")
const GRASS_ATLAS: Texture2D = preload("res://assets/sprites/terrain/procedural_grass/grass_families_atlas_40x28.svg")
const EDGE_ATLAS: Texture2D = preload("res://assets/sprites/terrain/procedural_grass/grass_edges_atlas_40x28.svg")

const GRASS_SPRITE_COUNT := 14
const V6_PALETTE_SHADOW := Color(0.392157, 0.474510, 0.176471, 1.0)
const V6_PALETTE_DARK_MID := Color(0.537255, 0.682353, 0.227451, 1.0)
const V6_PALETTE_MID_LIGHT := Color(0.650980, 0.756863, 0.294118, 1.0)
const V6_PALETTE_HIGHLIGHT := Color(0.768627, 0.827451, 0.349020, 1.0)
const V6_FIELD_SCALE_A := 0.00024
const V6_FIELD_SCALE_B := 0.00072
const V6_THRESHOLD_1 := 0.24
const V6_THRESHOLD_2 := 0.43
const V6_THRESHOLD_3 := 0.68

@export_category("Reference V7 meadow")
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
@export_range(0.0, 1.0, 0.01) var edge_sprite_chance := 0.72
@export_range(2.0, 32.0, 1.0) var edge_probe_pixels := 10.0
@export var rebuild_on_ready := true
@export var ground_path := NodePath("../Ground")

@export_category("V5/V6 compatibility")
@export var ground_leaf_frequency := 0.11
@export var tall_grass_frequency := 0.08
@export var tall_weed_frequency := 0.025
@export var palette_shadow := V6_PALETTE_SHADOW
@export var palette_dark_mid := V6_PALETTE_DARK_MID
@export var palette_mid_light := V6_PALETTE_MID_LIGHT
@export var palette_highlight := V6_PALETTE_HIGHLIGHT
@export var palette_field_scale_a := V6_FIELD_SCALE_A
@export var palette_field_scale_b := V6_FIELD_SCALE_B
@export var palette_threshold_1 := V6_THRESHOLD_1
@export var palette_threshold_2 := V6_THRESHOLD_2
@export var palette_threshold_3 := V6_THRESHOLD_3

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
var _edge_material: ShaderMaterial
var _grass_node: MultiMeshInstance2D
var _edge_node: MultiMeshInstance2D
var _quad_mesh: QuadMesh
var _patch_noise_texture: Texture2D
var _patch_noise_image: Image
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
		if _edge_material != null:
			_edge_material.set_shader_parameter("stepped_time", _stepped_time)
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
	var total := 0
	if _grass_node != null and _grass_node.multimesh != null:
		total += _grass_node.multimesh.instance_count
	if _edge_node != null and _edge_node.multimesh != null:
		total += _edge_node.multimesh.instance_count
	return total

func get_visible_tuft_count() -> int:
	return get_total_tuft_count()

func set_wind_direction(new_direction: Vector2) -> void:
	if new_direction.length_squared() < 0.0001:
		return
	wind_direction = new_direction.normalized()
	for material in [_grass_material, _edge_material]:
		if material != null:
			material.set_shader_parameter("wind_direction", wind_direction)

func _prepare_resources() -> void:
	_patch_noise_image = _create_noise_image(256, world_seed + 401, 0.012, 3)
	_patch_noise_texture = ImageTexture.create_from_image(_patch_noise_image)
	_wind_noise_texture = ImageTexture.create_from_image(_create_noise_image(128, world_seed + 977, 0.027, 3))
	_quad_mesh = QuadMesh.new()
	_quad_mesh.size = grass_quad_size_pixels
	_grass_material = _create_grass_material(GRASS_ATLAS, 1.0)
	_edge_material = _create_grass_material(EDGE_ATLAS, 0.42)
	_apply_ground_shared_parameters()

func _create_grass_material(atlas: Texture2D, motion_scale: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GRASS_SHADER
	material.set_shader_parameter("grass_atlas", atlas)
	material.set_shader_parameter("patch_noise", _patch_noise_texture)
	material.set_shader_parameter("wind_noise", _wind_noise_texture)
	material.set_shader_parameter("palette_shadow", V6_PALETTE_SHADOW)
	material.set_shader_parameter("palette_dark_mid", V6_PALETTE_DARK_MID)
	material.set_shader_parameter("palette_mid_light", V6_PALETTE_MID_LIGHT)
	material.set_shader_parameter("palette_highlight", V6_PALETTE_HIGHLIGHT)
	material.set_shader_parameter("palette_field_scale_a", V6_FIELD_SCALE_A)
	material.set_shader_parameter("palette_field_scale_b", V6_FIELD_SCALE_B)
	material.set_shader_parameter("palette_threshold_1", V6_THRESHOLD_1)
	material.set_shader_parameter("palette_threshold_2", V6_THRESHOLD_2)
	material.set_shader_parameter("palette_threshold_3", V6_THRESHOLD_3)
	material.set_shader_parameter("stepped_time", _stepped_time)
	material.set_shader_parameter("wind_direction", wind_direction.normalized())
	material.set_shader_parameter("wind_strength_pixels", wind_strength_pixels * motion_scale)
	material.set_shader_parameter("wind_noise_scale", wind_noise_scale)
	material.set_shader_parameter("wind_noise_speed", wind_noise_speed)
	material.set_shader_parameter("wind_noise_threshold", wind_noise_threshold)
	material.set_shader_parameter("wind_gust_width", wind_gust_width)
	material.set_shader_parameter("noise_diverge_angle", noise_diverge_angle)
	material.set_shader_parameter("fake_perspective_scale", fake_perspective_scale * motion_scale)
	material.set_shader_parameter("displacement_strength_pixels", displacement_strength_pixels * motion_scale)
	material.set_shader_parameter("radius_exponent", displacement_radius_exponent)
	material.set_shader_parameter("quad_size_pixels", grass_quad_size_pixels)
	return material

func _build_meadow() -> void:
	var safe_spacing := Vector2(maxf(spacing_pixels.x, 4.0), maxf(spacing_pixels.y, 4.0))
	var columns := ceili(field_size_pixels.x / safe_spacing.x) + 2
	var rows := ceili(field_size_pixels.y / safe_spacing.y) + 2
	var start := -field_size_pixels * 0.5 - safe_spacing
	var density_noise := _create_cpu_noise(world_seed + 171, density_frequency, 3)
	var detail_noise := _create_cpu_noise(world_seed + 811, density_detail_frequency, 2)
	var grass_instances: Array = []
	var edge_instances: Array = []
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
			if rng.randf() <= spawn_chance:
				grass_instances.append({"position": position, "sprite": _pick_sprite_index_for_density(rng, density), "random": rng.randf()})
			if _is_palette_edge(position) and rng.randf() <= edge_sprite_chance:
				edge_instances.append({"position": position + Vector2(0.0, rng.randi_range(-2, 2)), "sprite": rng.randi_range(0, 5), "random": rng.randf()})
	_grass_node = _build_multimesh_node("ReferenceMeadowGrass", grass_instances, _grass_material, 2)
	_edge_node = _build_multimesh_node("PaletteEdgeGrass", edge_instances, _edge_material, 1)

func _build_multimesh_node(node_name: String, instances: Array, material: ShaderMaterial, z: int) -> MultiMeshInstance2D:
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
	var node := MultiMeshInstance2D.new()
	node.name = node_name
	node.multimesh = multimesh
	node.material = material
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.z_index = z
	add_child(node)
	return node

func _is_palette_edge(position: Vector2) -> bool:
	var centre := _ground_palette_index(position)
	var d := edge_probe_pixels
	return _ground_palette_index(position + Vector2(d, 0.0)) != centre or _ground_palette_index(position + Vector2(-d, 0.0)) != centre or _ground_palette_index(position + Vector2(0.0, d)) != centre or _ground_palette_index(position + Vector2(0.0, -d)) != centre

func _ground_palette_index(position: Vector2) -> int:
	var field := _shared_palette_field_cpu(position)
	if field < V6_THRESHOLD_1:
		return 0
	if field < V6_THRESHOLD_2:
		return 1
	if field < V6_THRESHOLD_3:
		return 2
	return 3

func _shared_palette_field_cpu(position: Vector2) -> float:
	var broad := _sample_noise_repeat(_patch_noise_image, position * V6_FIELD_SCALE_A + Vector2(0.13, 0.31))
	var secondary := _sample_noise_repeat(_patch_noise_image, position * V6_FIELD_SCALE_B + Vector2(0.67, 0.19))
	return clampf(broad * 0.88 + secondary * 0.12 + 0.16, 0.0, 1.0)

func _sample_noise_repeat(image: Image, uv: Vector2) -> float:
	if image == null or image.is_empty():
		return 0.5
	var wrapped := Vector2(uv.x - floorf(uv.x), uv.y - floorf(uv.y))
	var px := clampi(floori(wrapped.x * float(image.get_width())), 0, image.get_width() - 1)
	var py := clampi(floori(wrapped.y * float(image.get_height())), 0, image.get_height() - 1)
	return image.get_pixel(px, py).r

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

func _create_noise_image(size: int, noise_seed: int, frequency: float, octaves: int) -> Image:
	var noise := _create_cpu_noise(noise_seed, frequency, octaves)
	return noise.get_seamless_image(size, size, false, false, 0.15, true)

func _apply_ground_shared_parameters() -> void:
	var ground := get_node_or_null(ground_path) as MeshInstance2D
	if ground == null or not (ground.material is ShaderMaterial):
		return
	var material := ground.material as ShaderMaterial
	material.set_shader_parameter("patch_noise", _patch_noise_texture)
	material.set_shader_parameter("palette_shadow", V6_PALETTE_SHADOW)
	material.set_shader_parameter("palette_dark_mid", V6_PALETTE_DARK_MID)
	material.set_shader_parameter("palette_mid_light", V6_PALETTE_MID_LIGHT)
	material.set_shader_parameter("palette_highlight", V6_PALETTE_HIGHLIGHT)
	material.set_shader_parameter("palette_field_scale_a", V6_FIELD_SCALE_A)
	material.set_shader_parameter("palette_field_scale_b", V6_FIELD_SCALE_B)
	material.set_shader_parameter("palette_threshold_1", V6_THRESHOLD_1)
	material.set_shader_parameter("palette_threshold_2", V6_THRESHOLD_2)
	material.set_shader_parameter("palette_threshold_3", V6_THRESHOLD_3)

func _update_displacer() -> void:
	if _resolved_displacer == null or not is_instance_valid(_resolved_displacer):
		_resolved_displacer = get_tree().get_first_node_in_group(displacer_group) as Node2D
	var displacer_value := Vector3(-100000.0, -100000.0, 1.0)
	if _resolved_displacer != null:
		displacer_value = Vector3(_resolved_displacer.global_position.x, _resolved_displacer.global_position.y, displacement_radius_pixels)
	for material in [_grass_material, _edge_material]:
		if material != null:
			material.set_shader_parameter("displacer", displacer_value)

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
	for node in [_grass_node, _edge_node]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_grass_node = null
	_edge_node = null
	_grass_material = null
	_edge_material = null
	_quad_mesh = null
	_patch_noise_texture = null
	_patch_noise_image = null
	_wind_noise_texture = null
