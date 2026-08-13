@tool
class_name ProceduralGrassField2D
extends Node2D

const GRASS_MASK_TEXTURE: Texture2D = preload(
	"res://assets/sprites/tilesets/terrain/grass_dirt/terrain_grass_dirt_dual_mask_64.png"
)
const GRASS_SHADER: Shader = preload("res://shaders/terrain/procedural_grass_tuft.gdshader")

@export var profile: ProceduralTerrainProfile
@export_node_path("TileMapLayer") var terrain_layer_path := NodePath("../Ground")
@export_node_path("Node2D") var player_path := NodePath()
@export var rebuild_on_ready := true
@export var render_above_characters := true

var _sampler: ProceduralTerrainSampler
var _mask_image: Image
var _grass_material: ShaderMaterial
var _quad_mesh: QuadMesh
var _resolved_player: Node2D


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	set_process(true)
	if rebuild_on_ready:
		call_deferred("rebuild")


func _process(_delta: float) -> void:
	if _grass_material == null:
		return
	if _resolved_player == null or not is_instance_valid(_resolved_player):
		_resolved_player = _find_player()
	if _resolved_player != null:
		_grass_material.set_shader_parameter("player_position", _resolved_player.global_position)


func rebuild() -> void:
	if Engine.is_editor_hint():
		return
	var terrain := get_node_or_null(terrain_layer_path) as TileMapLayer
	if terrain == null:
		push_error("ProceduralGrassField2D requires a TileMapLayer at terrain_layer_path.")
		return
	if profile == null:
		push_error("ProceduralGrassField2D requires a ProceduralTerrainProfile.")
		return

	_clear_chunks()
	_prepare_runtime_resources()
	_sampler = ProceduralTerrainSampler.new(profile)

	var groups := {}
	for cell in terrain.get_used_cells():
		_scatter_cell(terrain, cell, groups)

	for chunk_variant in groups.keys():
		var chunk: Vector2i = chunk_variant
		var entries: Array = groups[chunk]
		_create_chunk(chunk, entries)


func get_total_tuft_count() -> int:
	var total := 0
	for child in get_children():
		if child is MultiMeshInstance2D:
			var grass_chunk := child as MultiMeshInstance2D
			if grass_chunk.multimesh != null:
				total += grass_chunk.multimesh.instance_count
	return total


func _prepare_runtime_resources() -> void:
	_mask_image = GRASS_MASK_TEXTURE.get_image()

	_grass_material = ShaderMaterial.new()
	_grass_material.shader = GRASS_SHADER
	_grass_material.set_shader_parameter("shadow_color", profile.grass_shadow_color)
	_grass_material.set_shader_parameter("base_color", profile.grass_base_color)
	_grass_material.set_shader_parameter("tip_color", profile.grass_tip_color)
	_grass_material.set_shader_parameter("color_variation_strength", profile.color_variation_strength)
	_grass_material.set_shader_parameter("wind_fps", profile.wind_fps)
	_grass_material.set_shader_parameter("wind_speed", profile.wind_speed)
	_grass_material.set_shader_parameter("wind_strength_pixels", profile.wind_strength_pixels)
	_grass_material.set_shader_parameter("wind_world_frequency", profile.wind_world_frequency)
	_grass_material.set_shader_parameter("interaction_radius_pixels", profile.interaction_radius_pixels)
	_grass_material.set_shader_parameter("interaction_bend_pixels", profile.interaction_bend_pixels)

	_quad_mesh = QuadMesh.new()
	_quad_mesh.size = profile.tuft_size_pixels
	_quad_mesh.material = _grass_material


func _scatter_cell(terrain: TileMapLayer, cell: Vector2i, groups: Dictionary) -> void:
	if terrain.get_cell_source_id(cell) == -1:
		return

	var tile_size := profile.tile_size_pixels
	var half_tile := float(tile_size) * 0.5
	var cell_center_local := terrain.map_to_local(cell)
	var rng := RandomNumberGenerator.new()
	rng.seed = _cell_seed(cell)

	for _candidate in range(profile.tufts_per_tile):
		var offset := Vector2(
			rng.randf_range(-half_tile + 1.0, half_tile - 1.0),
			rng.randf_range(-half_tile + 1.0, half_tile - 1.0)
		)
		if not _candidate_is_grass_pixel(terrain, cell, offset):
			continue

		var candidate_global := terrain.to_global(cell_center_local + offset)
		var density := _sampler.grass_density_at(candidate_global)
		if rng.randf() > density:
			continue

		var chunk_world_size := float(profile.chunk_size_tiles * tile_size)
		var chunk := Vector2i(
			floori(candidate_global.x / chunk_world_size),
			floori(candidate_global.y / chunk_world_size)
		)
		if not groups.has(chunk):
			groups[chunk] = []

		var scale := rng.randf_range(profile.min_tuft_scale, profile.max_tuft_scale)
		var flip := -1.0 if rng.randf() < 0.5 else 1.0
		var rotation := rng.randf_range(
			-profile.rotation_variation_radians,
			profile.rotation_variation_radians
		)
		var entry := {
			"global_position": candidate_global,
			"scale": Vector2(scale * flip, scale),
			"rotation": rotation,
			"phase": rng.randf(),
			"variation": rng.randf(),
			"shape": rng.randf(),
		}
		(groups[chunk] as Array).append(entry)


func _candidate_is_grass_pixel(terrain: TileMapLayer, cell: Vector2i, offset: Vector2) -> bool:
	if _mask_image == null:
		return true

	var atlas_coords := terrain.get_cell_atlas_coords(cell)
	if atlas_coords.x < 0 or atlas_coords.y < 0:
		return false

	var tile_size := profile.tile_size_pixels
	var pixel := Vector2i(
		clampi(floori(offset.x + float(tile_size) * 0.5), 0, tile_size - 1),
		clampi(floori(offset.y + float(tile_size) * 0.5), 0, tile_size - 1)
	)

	if terrain.is_cell_transposed(cell):
		pixel = Vector2i(pixel.y, pixel.x)
	if terrain.is_cell_flipped_h(cell):
		pixel.x = tile_size - 1 - pixel.x
	if terrain.is_cell_flipped_v(cell):
		pixel.y = tile_size - 1 - pixel.y

	var atlas_pixel := atlas_coords * tile_size + pixel
	if atlas_pixel.x < 0 or atlas_pixel.y < 0:
		return false
	if atlas_pixel.x >= _mask_image.get_width() or atlas_pixel.y >= _mask_image.get_height():
		return false

	return _mask_image.get_pixelv(atlas_pixel).r >= profile.grass_mask_threshold


func _create_chunk(chunk: Vector2i, entries: Array) -> void:
	if entries.is_empty():
		return

	var tile_size := profile.tile_size_pixels
	var chunk_world_size := float(profile.chunk_size_tiles * tile_size)
	var chunk_global_origin := Vector2(chunk) * chunk_world_size
	var chunk_local_origin := to_local(chunk_global_origin)

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_custom_data = true
	multimesh.mesh = _quad_mesh
	multimesh.instance_count = entries.size()

	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		var global_position: Vector2 = entry["global_position"]
		var scale: Vector2 = entry["scale"]
		var rotation: float = entry["rotation"]
		var local_position := to_local(global_position) - chunk_local_origin

		var baseline_offset := Vector2(
			0.0,
			-profile.tuft_size_pixels.y * absf(scale.y) * 0.5
		)
		var instance_transform := Transform2D(
			rotation,
			scale,
			0.0,
			local_position + baseline_offset
		)
		multimesh.set_instance_transform_2d(index, instance_transform)
		multimesh.set_instance_custom_data(
			index,
			Color(
				float(entry["phase"]),
				float(entry["variation"]),
				float(entry["shape"]),
				1.0
			)
		)

	var chunk_node := MultiMeshInstance2D.new()
	chunk_node.name = "GrassChunk_%d_%d" % [chunk.x, chunk.y]
	chunk_node.position = chunk_local_origin
	chunk_node.multimesh = multimesh
	chunk_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	chunk_node.z_index = 1 if render_above_characters else -1
	add_child(chunk_node)


func _clear_chunks() -> void:
	for child in get_children():
		if child is MultiMeshInstance2D:
			remove_child(child)
			child.queue_free()


func _find_player() -> Node2D:
	if not player_path.is_empty():
		var explicit_player := get_node_or_null(player_path) as Node2D
		if explicit_player != null:
			return explicit_player

	var grouped_player := get_tree().get_first_node_in_group("player") as Node2D
	if grouped_player != null:
		return grouped_player

	var current_scene := get_tree().current_scene
	if current_scene != null:
		var lab_player := current_scene.get_node_or_null("Player") as Node2D
		if lab_player != null:
			return lab_player
		lab_player = current_scene.get_node_or_null("AuthoringLabPlayer") as Node2D
		if lab_player != null:
			return lab_player
	return null


func _cell_seed(cell: Vector2i) -> int:
	var mixed := profile.world_seed
	mixed ^= cell.x * 73856093
	mixed ^= cell.y * 19349663
	return abs(mixed)
