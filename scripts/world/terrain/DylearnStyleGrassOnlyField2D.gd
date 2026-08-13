@tool
class_name DylearnStyleGrassOnlyField2D
extends Node2D

const GRASS_SHADER: Shader = preload(
	"res://shaders/terrain/dylearn_style_grass_2d.gdshader"
)

# The grass masks are embedded as 16x16 pixel art so this lab has no binary
# texture import dependency. This avoids PNG import/cache failures entirely.
const GRASS_MASK_ROWS := [
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
]

const ACCENT_MASK_ROWS := [
	".......##.......",
	"..##...##...##..",
	".####..##..####.",
	"#####..##..#####",
	".#####.##.#####.",
	"..###########...",
	"...#########....",
	"....#######.....",
	".....#####......",
	".....#####......",
	"......####......",
	"......####......",
	"......####......",
	".......##.......",
	".......##.......",
	".......##.......",
]

@export_category("Field")
@export var field_size_pixels := Vector2(3200.0, 2200.0)
@export var spacing_pixels := Vector2(14.0, 11.0)
@export var jitter_pixels := Vector2(5.0, 4.0)
@export var chunk_size_pixels := 384.0
@export var world_seed := 91373
@export var min_scale := 0.82
@export var max_scale := 1.22
@export var rotation_variation_radians := 0.07
@export var grass_quad_size_pixels := Vector2(18.0, 18.0)
@export var rebuild_on_ready := true

@export_category("Colour / heterogeneity")
@export var grass_color_base := Color(0.235, 0.390, 0.105, 1.0)
@export var grass_color_patch_a := Color(0.315, 0.500, 0.135, 1.0)
@export var grass_color_patch_b := Color(0.145, 0.270, 0.075, 1.0)
@export var patch_scale_a := 0.0046
@export var patch_scale_b := 0.0082
@export var patch_threshold_a := 0.59
@export var patch_threshold_b := 0.66
@export_range(0.0, 0.35, 0.001) var accent_frequency := 0.075
@export var accent_color := Color(0.500, 0.650, 0.170, 1.0)

@export_category("Animation")
@export_range(1.0, 16.0, 1.0) var stepped_framerate := 5.0
@export var quantised_animation := true
@export var wind_direction := Vector2(0.92, 0.38)
@export_range(0.0, 12.0, 0.1) var wind_strength_pixels := 5.4
@export_range(0.001, 0.2, 0.001) var wind_noise_scale := 0.032
@export_range(0.0, 80.0, 0.1) var wind_noise_speed := 14.0
@export_range(-1.0, 1.0, 0.001) var wind_noise_threshold := 0.34
@export_range(0.0, 1.2, 0.01) var noise_diverge_angle := 0.42
@export_range(-0.5, 0.75, 0.01) var fake_perspective_scale := 0.28

@export_category("Interaction")
@export var displacer_group := &"grass_displacer"
@export_range(0.0, 128.0, 1.0) var displacement_radius_pixels := 42.0
@export_range(0.0, 20.0, 0.1) var displacement_strength_pixels := 9.0
@export_range(0.1, 6.0, 0.1) var displacement_radius_exponent := 1.4

var _grass_material: ShaderMaterial
var _quad_mesh: QuadMesh
var _resolved_displacer: Node2D


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	set_process(true)
	if rebuild_on_ready:
		call_deferred("rebuild")


func _process(_delta: float) -> void:
	if _grass_material == null:
		return

	if _resolved_displacer == null or not is_instance_valid(_resolved_displacer):
		_resolved_displacer = get_tree().get_first_node_in_group(displacer_group) as Node2D

	if _resolved_displacer != null:
		_grass_material.set_shader_parameter(
			"displacer",
			Vector3(
				_resolved_displacer.global_position.x,
				_resolved_displacer.global_position.y,
				displacement_radius_pixels
			)
		)
	else:
		_grass_material.set_shader_parameter(
			"displacer",
			Vector3(-100000.0, -100000.0, 1.0)
		)


func rebuild() -> void:
	if Engine.is_editor_hint():
		return

	_clear_chunks()
	_prepare_resources()

	var groups: Dictionary = {}
	var safe_spacing := Vector2(
		maxf(spacing_pixels.x, 2.0),
		maxf(spacing_pixels.y, 2.0)
	)
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
				floori(local_position.x / chunk_size_pixels),
				floori(local_position.y / chunk_size_pixels)
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
				"seed": rng.randf(),
				"variation": rng.randf(),
				"shape": rng.randf(),
			})

	for chunk_variant in groups.keys():
		var chunk: Vector2i = chunk_variant
		_create_chunk(chunk, groups[chunk] as Array)


func get_total_tuft_count() -> int:
	var total := 0
	for child in get_children():
		if child is MultiMeshInstance2D:
			var instance := child as MultiMeshInstance2D
			if instance.multimesh != null:
				total += instance.multimesh.instance_count
	return total


func set_wind_direction(new_direction: Vector2) -> void:
	if new_direction.length_squared() < 0.0001:
		return
	wind_direction = new_direction.normalized()
	if _grass_material != null:
		_grass_material.set_shader_parameter("wind_direction", wind_direction)


func _prepare_resources() -> void:
	var grass_texture := _create_mask_texture(GRASS_MASK_ROWS)
	var accent_texture := _create_mask_texture(ACCENT_MASK_ROWS)

	_grass_material = ShaderMaterial.new()
	_grass_material.shader = GRASS_SHADER
	_grass_material.set_shader_parameter("grass_texture", grass_texture)
	_grass_material.set_shader_parameter("accent_texture", accent_texture)
	_grass_material.set_shader_parameter("grass_color_base", grass_color_base)
	_grass_material.set_shader_parameter("grass_color_patch_a", grass_color_patch_a)
	_grass_material.set_shader_parameter("grass_color_patch_b", grass_color_patch_b)
	_grass_material.set_shader_parameter("patch_scale_a", patch_scale_a)
	_grass_material.set_shader_parameter("patch_scale_b", patch_scale_b)
	_grass_material.set_shader_parameter("patch_threshold_a", patch_threshold_a)
	_grass_material.set_shader_parameter("patch_threshold_b", patch_threshold_b)
	_grass_material.set_shader_parameter("accent_frequency", accent_frequency)
	_grass_material.set_shader_parameter("accent_color", accent_color)
	_grass_material.set_shader_parameter("framerate", stepped_framerate)
	_grass_material.set_shader_parameter("quantised", quantised_animation)
	_grass_material.set_shader_parameter("wind_direction", wind_direction.normalized())
	_grass_material.set_shader_parameter("wind_strength_pixels", wind_strength_pixels)
	_grass_material.set_shader_parameter("wind_noise_scale", wind_noise_scale)
	_grass_material.set_shader_parameter("wind_noise_speed", wind_noise_speed)
	_grass_material.set_shader_parameter("wind_noise_threshold", wind_noise_threshold)
	_grass_material.set_shader_parameter("noise_diverge_angle", noise_diverge_angle)
	_grass_material.set_shader_parameter("fake_perspective_scale", fake_perspective_scale)
	_grass_material.set_shader_parameter("displacement_strength_pixels", displacement_strength_pixels)
	_grass_material.set_shader_parameter("radius_exponent", displacement_radius_exponent)
	_grass_material.set_shader_parameter("quad_size_pixels", grass_quad_size_pixels)
	_grass_material.set_shader_parameter("world_seed", float(world_seed))

	_quad_mesh = QuadMesh.new()
	_quad_mesh.size = grass_quad_size_pixels


func _create_mask_texture(rows: Array) -> Texture2D:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in range(16):
		var row: String = rows[y]
		for x in range(16):
			var alpha := 1.0 if row.substr(x, 1) == "#" else 0.0
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)


func _create_chunk(chunk: Vector2i, entries: Array) -> void:
	if entries.is_empty():
		return

	var chunk_origin := Vector2(chunk) * chunk_size_pixels
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
				float(entry["seed"]),
				float(entry["variation"]),
				float(entry["shape"]),
				1.0
			)
		)

	var chunk_node := MultiMeshInstance2D.new()
	chunk_node.name = "GrassChunk_%d_%d" % [chunk.x, chunk.y]
	chunk_node.position = chunk_origin
	chunk_node.multimesh = multimesh
	chunk_node.material = _grass_material
	chunk_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	chunk_node.z_index = 2
	add_child(chunk_node)


func _clear_chunks() -> void:
	for child in get_children():
		if child is MultiMeshInstance2D:
			remove_child(child)
			child.queue_free()


func _cell_seed(cell: Vector2i) -> int:
	var mixed := world_seed
	mixed ^= cell.x * 73856093
	mixed ^= cell.y * 19349663
	return abs(mixed)
