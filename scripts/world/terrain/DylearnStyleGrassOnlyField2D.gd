@tool
class_name DylearnStyleGrassOnlyField2D
extends Node2D

const GRASS_SHADER: Shader = preload(
	"res://shaders/terrain/dylearn_style_grass_2d.gdshader"
)

const GRASS_SPRITE_ROWS := [
	[
		".......##.......",
		"......####......",
		".....#####......",
		"...######.......",
		"..#####...##....",
		".#####...####...",
		"...####..####...",
		"....###.#####...",
		".....#######....",
		"...########.....",
		"..########......",
		"....######......",
		".....#####......",
		"......####......",
		"......####......",
		".......##.......",
	],
	[
		".......##.......",
		"....#..##..#....",
		"...##..##..##...",
		"..###..##..###..",
		"...###.##.###...",
		"....########....",
		".....######.....",
		"...##########...",
		"..###.####.###..",
		"...##.####.##...",
		".....######.....",
		"......####......",
		"......####......",
		"......####......",
		".......##.......",
		".......##.......",
	],
	[
		".........##.....",
		"........####....",
		"......######....",
		"....#######.....",
		"..######........",
		".######.........",
		"...######.......",
		".....#####......",
		".......####.....",
		"......######....",
		"....#######.....",
		".....######.....",
		"......#####.....",
		"......####......",
		".......###......",
		".......##.......",
	],
	[
		".......##.......",
		".......##.......",
		"...##..##..##...",
		"..####.##.####..",
		".#####.##.#####.",
		"..############..",
		"...##########...",
		"....########....",
		"...##########...",
		"..####.##.####..",
		"....##.##.##....",
		".....######.....",
		"......####......",
		"......####......",
		".......##.......",
		".......##.......",
	],
	[
		".......##.......",
		".......##.......",
		"...##..##.......",
		"..####.##..##...",
		"...######.####..",
		"....########....",
		".....######.....",
		"......#####.....",
		"......####......",
		"......####......",
		".......###......",
		".......###......",
		".......##.......",
		".......##.......",
		".......##.......",
		".......##.......",
	],
	[
		".......##.......",
		"..#....##....#..",
		".###...##...###.",
		"..###..##..###..",
		"...###.##.###...",
		"....########....",
		".....######.....",
		"......####......",
		"...##..##..##...",
		"..####.##.####..",
		"...##########...",
		".....######.....",
		"......####......",
		"......####......",
		".......##.......",
		".......##.......",
	],
]

@export_category("Field")
@export var field_size_pixels := Vector2(3200.0, 2200.0)
@export var spacing_pixels := Vector2(17.0, 14.0)
@export var jitter_pixels := Vector2(5.5, 4.5)
@export var chunk_size_pixels := 320.0
@export var world_seed := 91373
@export var min_scale := 0.88
@export var max_scale := 1.28
@export var rotation_variation_radians := 0.06
@export var grass_quad_size_pixels := Vector2(22.0, 22.0)
@export var accent_a_frequency := 0.034
@export var accent_b_frequency := 0.012
@export var rebuild_on_ready := true
@export var ground_path := NodePath("../Ground")

@export_category("Colour / heterogeneity")
@export var grass_color_base := Color(0.190, 0.340, 0.100, 1.0)
@export var grass_color_patch_a := Color(0.270, 0.430, 0.120, 1.0)
@export var grass_color_patch_b := Color(0.130, 0.250, 0.075, 1.0)
@export var accent_color_a := Color(0.390, 0.520, 0.140, 1.0)
@export var accent_color_b := Color(0.310, 0.420, 0.100, 1.0)
@export var patch_scale_a := 0.0009
@export var patch_scale_b := 0.0023
@export var patch_threshold_a := 0.58
@export var patch_threshold_b := 0.72

@export_category("Animation")
@export_range(1.0, 16.0, 1.0) var stepped_framerate := 5.0
@export var quantised_animation := true
@export var wind_direction := Vector2(0.92, 0.38)
@export_range(0.0, 12.0, 0.1) var wind_strength_pixels := 5.0
@export_range(0.0001, 0.02, 0.0001) var wind_noise_scale := 0.0017
@export_range(0.0, 0.25, 0.001) var wind_noise_speed := 0.055
@export_range(0.0, 1.0, 0.001) var wind_noise_threshold := 0.34
@export_range(0.001, 0.5, 0.001) var wind_gust_width := 0.18
@export_range(0.0, 1.2, 0.01) var noise_diverge_angle := 0.22
@export_range(-0.5, 0.75, 0.01) var fake_perspective_scale := 0.22

@export_category("Interaction")
@export var displacer_group := &"grass_displacer"
@export_range(0.0, 128.0, 1.0) var displacement_radius_pixels := 40.0
@export_range(0.0, 20.0, 0.1) var displacement_strength_pixels := 8.0
@export_range(0.1, 6.0, 0.1) var displacement_radius_exponent := 1.45
@export_range(0.01, 0.5, 0.01) var interaction_update_interval := 0.05

@export_category("Chunk culling / LOD")
@export_range(64.0, 1024.0, 16.0) var chunk_visibility_margin := 192.0
@export_range(64.0, 1600.0, 16.0) var near_lod_distance := 420.0
@export_range(128.0, 2200.0, 16.0) var mid_lod_distance := 860.0
@export_range(0.1, 1.0, 0.01) var mid_visible_ratio := 0.72
@export_range(0.1, 1.0, 0.01) var far_visible_ratio := 0.46
@export_range(0.05, 1.0, 0.01) var lod_update_interval := 0.18

var _near_material: ShaderMaterial
var _mid_material: ShaderMaterial
var _far_material: ShaderMaterial
var _quad_mesh: QuadMesh
var _patch_noise_texture: Texture2D
var _wind_noise_texture: Texture2D
var _resolved_displacer: Node2D
var _chunks: Array[Dictionary] = []
var _interaction_accumulator := 0.0
var _lod_accumulator := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	set_process(true)
	if rebuild_on_ready:
		call_deferred("rebuild")


func _process(delta: float) -> void:
	if _near_material == null:
		return

	_interaction_accumulator += delta
	_lod_accumulator += delta

	if _interaction_accumulator >= interaction_update_interval:
		_interaction_accumulator = 0.0
		_update_displacer()

	if _lod_accumulator >= lod_update_interval:
		_lod_accumulator = 0.0
		_update_chunk_lod()


func rebuild() -> void:
	if Engine.is_editor_hint():
		return

	_clear_chunks()
	_prepare_resources()

	var groups: Dictionary = {}
	var safe_spacing := Vector2(
		maxf(spacing_pixels.x, 4.0),
		maxf(spacing_pixels.y, 4.0)
	)
	var safe_chunk_size := maxf(chunk_size_pixels, 64.0)
	var columns := ceili(field_size_pixels.x / safe_spacing.x)
	var rows := ceili(field_size_pixels.y / safe_spacing.y)
	var start := -field_size_pixels * 0.5

	for y in range(rows):
		for x in range(columns):
			var grid_index := Vector2i(x, y)
			var rng := RandomNumberGenerator.new()
			rng.seed = _cell_seed(grid_index)

			var local_position := start + Vector2(
				(float(x) + 0.5) * safe_spacing.x,
				(float(y) + 0.5) * safe_spacing.y
			)
			local_position += Vector2(
				rng.randf_range(-jitter_pixels.x, jitter_pixels.x),
				rng.randf_range(-jitter_pixels.y, jitter_pixels.y)
			)

			var chunk := Vector2i(
				floori(local_position.x / safe_chunk_size),
				floori(local_position.y / safe_chunk_size)
			)
			if not groups.has(chunk):
				groups[chunk] = []

			var scale := rng.randf_range(min_scale, max_scale)
			var flip_x := -1.0 if rng.randf() < 0.5 else 1.0
			var rotation := rng.randf_range(
				-rotation_variation_radians,
				rotation_variation_radians
			)

			(groups[chunk] as Array).append({
				"position": local_position,
				"scale": Vector2(scale * flip_x, scale),
				"rotation": rotation,
				"phase": rng.randf(),
				"variation": rng.randf(),
				"sprite": _pick_sprite_index(rng),
				"susceptibility": rng.randf(),
			})

	for chunk_variant in groups.keys():
		var chunk: Vector2i = chunk_variant
		var entries: Array = groups[chunk]
		_shuffle_entries(entries, _chunk_seed(chunk))
		_create_chunk(chunk, entries, safe_chunk_size)

	_update_displacer()
	_update_chunk_lod()


func get_total_tuft_count() -> int:
	var total := 0
	for chunk_data in _chunks:
		total += int(chunk_data["count"])
	return total


func get_visible_tuft_count() -> int:
	var total := 0
	for chunk_data in _chunks:
		var node: MultiMeshInstance2D = chunk_data["node"]
		if not node.visible or node.multimesh == null:
			continue
		var visible_count := node.multimesh.visible_instance_count
		total += node.multimesh.instance_count if visible_count < 0 else visible_count
	return total


func set_wind_direction(new_direction: Vector2) -> void:
	if new_direction.length_squared() < 0.0001:
		return
	wind_direction = new_direction.normalized()
	for material in [_near_material, _mid_material, _far_material]:
		if material != null:
			material.set_shader_parameter("wind_direction", wind_direction)


func _prepare_resources() -> void:
	var grass_atlas := _create_grass_atlas()
	_patch_noise_texture = _create_noise_texture(256, world_seed + 401, 0.022, 4)
	_wind_noise_texture = _create_noise_texture(128, world_seed + 977, 0.028, 3)

	_near_material = _make_grass_material(
		stepped_framerate,
		1.0,
		1.0,
		1.0,
		grass_atlas
	)
	_mid_material = _make_grass_material(
		maxf(2.0, stepped_framerate * 0.62),
		0.68,
		0.55,
		0.0,
		grass_atlas
	)
	_far_material = _make_grass_material(
		maxf(1.0, stepped_framerate * 0.36),
		0.28,
		0.18,
		0.0,
		grass_atlas
	)

	_quad_mesh = QuadMesh.new()
	_quad_mesh.size = grass_quad_size_pixels
	_apply_ground_noise_texture()


func _make_grass_material(
	material_framerate: float,
	wind_multiplier: float,
	perspective_multiplier: float,
	displacement_multiplier: float,
	grass_atlas: Texture2D
) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GRASS_SHADER
	material.set_shader_parameter("grass_atlas", grass_atlas)
	material.set_shader_parameter("patch_noise", _patch_noise_texture)
	material.set_shader_parameter("wind_noise", _wind_noise_texture)
	material.set_shader_parameter("grass_color_base", grass_color_base)
	material.set_shader_parameter("grass_color_patch_a", grass_color_patch_a)
	material.set_shader_parameter("grass_color_patch_b", grass_color_patch_b)
	material.set_shader_parameter("accent_color_a", accent_color_a)
	material.set_shader_parameter("accent_color_b", accent_color_b)
	material.set_shader_parameter("patch_scale_a", patch_scale_a)
	material.set_shader_parameter("patch_scale_b", patch_scale_b)
	material.set_shader_parameter("patch_threshold_a", patch_threshold_a)
	material.set_shader_parameter("patch_threshold_b", patch_threshold_b)
	material.set_shader_parameter("framerate", material_framerate)
	material.set_shader_parameter("quantised", quantised_animation)
	material.set_shader_parameter("wind_direction", wind_direction.normalized())
	material.set_shader_parameter(
		"wind_strength_pixels",
		wind_strength_pixels * wind_multiplier
	)
	material.set_shader_parameter("wind_noise_scale", wind_noise_scale)
	material.set_shader_parameter("wind_noise_speed", wind_noise_speed)
	material.set_shader_parameter("wind_noise_threshold", wind_noise_threshold)
	material.set_shader_parameter("wind_gust_width", wind_gust_width)
	material.set_shader_parameter("noise_diverge_angle", noise_diverge_angle)
	material.set_shader_parameter(
		"fake_perspective_scale",
		fake_perspective_scale * perspective_multiplier
	)
	material.set_shader_parameter(
		"displacement_strength_pixels",
		displacement_strength_pixels * displacement_multiplier
	)
	material.set_shader_parameter("radius_exponent", displacement_radius_exponent)
	material.set_shader_parameter("quad_size_pixels", grass_quad_size_pixels)
	return material


func _apply_ground_noise_texture() -> void:
	var ground := get_node_or_null(ground_path) as MeshInstance2D
	if ground == null:
		return
	if ground.material is ShaderMaterial:
		var ground_material := ground.material as ShaderMaterial
		ground_material.set_shader_parameter("patch_noise", _patch_noise_texture)
		ground_material.set_shader_parameter("world_seed", float(world_seed))


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


func _create_grass_atlas() -> Texture2D:
	var sprite_size := 16
	var sprite_count := GRASS_SPRITE_ROWS.size()
	var image := Image.create(
		sprite_size * sprite_count,
		sprite_size,
		false,
		Image.FORMAT_RGBA8
	)

	for sprite_index in range(sprite_count):
		var rows: Array = GRASS_SPRITE_ROWS[sprite_index]
		for y in range(sprite_size):
			var row: String = rows[y]
			for x in range(sprite_size):
				var alpha := 1.0 if row.substr(x, 1) == "#" else 0.0
				image.set_pixel(
					sprite_index * sprite_size + x,
					y,
					Color(1.0, 1.0, 1.0, alpha)
				)

	return ImageTexture.create_from_image(image)


func _create_chunk(
	chunk: Vector2i,
	entries: Array,
	safe_chunk_size: float
) -> void:
	if entries.is_empty():
		return

	var chunk_origin := Vector2(chunk) * safe_chunk_size
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_custom_data = true
	multimesh.mesh = _quad_mesh
	multimesh.instance_count = entries.size()

	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		var scale: Vector2 = entry["scale"]
		var local_position: Vector2 = entry["position"] - chunk_origin
		var root_anchor_offset := Vector2(
			0.0,
			-grass_quad_size_pixels.y * absf(scale.y) * 0.5
		)
		var transform := Transform2D(
			float(entry["rotation"]),
			scale,
			0.0,
			local_position + root_anchor_offset
		)

		multimesh.set_instance_transform_2d(index, transform)
		multimesh.set_instance_custom_data(
			index,
			Color(
				float(entry["phase"]),
				float(entry["variation"]),
				float(entry["sprite"]) / 5.0,
				float(entry["susceptibility"])
			)
		)

	var chunk_node := MultiMeshInstance2D.new()
	chunk_node.name = "GrassChunk_%d_%d" % [chunk.x, chunk.y]
	chunk_node.position = chunk_origin
	chunk_node.multimesh = multimesh
	chunk_node.material = _near_material
	chunk_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	chunk_node.z_index = 2
	add_child(chunk_node)

	_chunks.append({
		"node": chunk_node,
		"center": chunk_origin + Vector2.ONE * safe_chunk_size * 0.5,
		"count": entries.size(),
		"lod": -1,
	})


func _update_displacer() -> void:
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

	_near_material.set_shader_parameter("displacer", displacer_value)


func _update_chunk_lod() -> void:
	if _chunks.is_empty():
		return

	var camera_position := global_position
	var half_view := get_viewport_rect().size * 0.5
	var camera := get_viewport().get_camera_2d()

	if camera != null:
		camera_position = camera.global_position
		var safe_zoom := Vector2(
			maxf(absf(camera.zoom.x), 0.001),
			maxf(absf(camera.zoom.y), 0.001)
		)
		half_view = Vector2(
			half_view.x / safe_zoom.x,
			half_view.y / safe_zoom.y
		)
	elif _resolved_displacer != null:
		camera_position = _resolved_displacer.global_position

	for chunk_data in _chunks:
		var node: MultiMeshInstance2D = chunk_data["node"]
		var local_center: Vector2 = chunk_data["center"]
		var center_global := to_global(local_center)
		var delta := center_global - camera_position
		var is_visible := (
			absf(delta.x) <= half_view.x + chunk_visibility_margin
			and absf(delta.y) <= half_view.y + chunk_visibility_margin
		)

		node.visible = is_visible
		if not is_visible:
			continue

		var distance := delta.length()
		var lod := 2
		if distance <= near_lod_distance:
			lod = 0
		elif distance <= mid_lod_distance:
			lod = 1

		_apply_chunk_lod(chunk_data, lod)


func _apply_chunk_lod(chunk_data: Dictionary, lod: int) -> void:
	if int(chunk_data["lod"]) == lod:
		return

	var node: MultiMeshInstance2D = chunk_data["node"]
	var total := int(chunk_data["count"])
	var visible_count := total

	if lod == 0:
		node.material = _near_material
	elif lod == 1:
		node.material = _mid_material
		visible_count = clampi(int(round(total * mid_visible_ratio)), 1, total)
	else:
		node.material = _far_material
		visible_count = clampi(int(round(total * far_visible_ratio)), 1, total)

	node.multimesh.visible_instance_count = visible_count
	chunk_data["lod"] = lod


func _pick_sprite_index(rng: RandomNumberGenerator) -> int:
	var roll := rng.randf()
	if roll < accent_b_frequency:
		return 5
	if roll < accent_b_frequency + accent_a_frequency:
		return 4
	return rng.randi_range(0, 3)


func _shuffle_entries(entries: Array, shuffle_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = shuffle_seed
	for index in range(entries.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var temporary = entries[index]
		entries[index] = entries[swap_index]
		entries[swap_index] = temporary


func _clear_chunks() -> void:
	_chunks.clear()
	for child in get_children():
		if child is MultiMeshInstance2D:
			remove_child(child)
			child.queue_free()


func _cell_seed(cell: Vector2i) -> int:
	var mixed := world_seed
	mixed ^= cell.x * 73856093
	mixed ^= cell.y * 19349663
	return abs(mixed)


func _chunk_seed(chunk: Vector2i) -> int:
	var mixed := world_seed + 104729
	mixed ^= chunk.x * 83492791
	mixed ^= chunk.y * 2971215073
	return abs(mixed)
