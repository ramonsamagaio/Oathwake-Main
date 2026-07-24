extends SceneTree

const TILESET_PATH := "res://tilesets/terrain/terrain_grass_dirt_tileset.tres"
const MATERIAL_PATH := "res://materials/terrain/terrain_grass_dirt_material.tres"
const PRODUCTION_SCENE_PATH := "res://scenes/world/terrain/OathwakeGrassDirtTerrainLayer.tscn"
const AUTHORING_SCENE_PATH := "res://scenes/labs/TerrainAuthoringLab.tscn"
const IMAGE_PATHS := {
	"mask": "res://assets/sprites/tilesets/terrain/grass_dirt/terrain_grass_dirt_dual_mask_64.png",
	"overlay": "res://assets/sprites/tilesets/terrain/grass_dirt/terrain_grass_dirt_dual_edge_overlay_64.png",
	"grass": "res://assets/sprites/tilesets/terrain/grass_dirt/terrain_grass_texture_256.png",
	"dirt": "res://assets/sprites/tilesets/terrain/grass_dirt/terrain_dirt_texture_256.png",
}

var failures: Array[String] = []


func _initialize() -> void:
	_validate_files_and_images()
	_validate_tileset()
	_validate_material()
	_validate_scenes()

	if failures.is_empty():
		print("TERRAIN_PIPELINE_VALIDATION: PASS")
		quit(OK)
		return
	for failure in failures:
		push_error(failure)
	print("TERRAIN_PIPELINE_VALIDATION: FAIL (%d issue(s))" % failures.size())
	quit(1)


func _validate_files_and_images() -> void:
	for label: String in IMAGE_PATHS:
		var path: String = IMAGE_PATHS[label]
		_check(FileAccess.file_exists(path), "%s image is missing: %s" % [label, path])
		var texture := load(path) as Texture2D
		_check(texture != null, "%s image cannot be imported as Texture2D" % label)
		if texture != null:
			_check(texture.get_size() == Vector2(256, 256), "%s image must be 256x256" % label)


func _validate_tileset() -> void:
	var tileset := load(TILESET_PATH) as TileSet
	_check(tileset != null, "Canonical TileSet does not load")
	if tileset == null:
		return
	_check(tileset.tile_size == Vector2i(64, 64), "TileSet tile_size must be 64x64")
	_check(tileset.get_terrain_sets_count() == 1, "TileSet must expose exactly one Terrain Set")
	_check(tileset.get_terrain_set_mode(0) == TileSet.TERRAIN_MODE_MATCH_CORNERS, "Terrain Set 0 must use Match Corners")
	_check(tileset.get_terrains_count(0) == 2, "Terrain Set 0 must expose dirt and grass terrains")
	_check(tileset.get_terrain_name(0, 1) == "Grass over Dirt", "Terrain 1 must be named Grass over Dirt")
	var atlas := tileset.get_source(0) as TileSetAtlasSource
	_check(atlas != null, "TileSet source 0 must be an atlas")
	if atlas != null:
		_check(atlas.texture_region_size == Vector2i(64, 64), "Atlas regions must be 64x64")
		_check(atlas.get_tiles_count() == 16, "Atlas must contain all 16 corner combinations")


func _validate_material() -> void:
	var shader_material := load(MATERIAL_PATH) as ShaderMaterial
	_check(shader_material != null, "Canonical material must load as ShaderMaterial")
	if shader_material != null:
		_check(shader_material.shader != null, "Canonical material must have a shader")
		_check(shader_material.get_shader_parameter("edge_overlay") != null, "Material must bind the edge overlay")


func _validate_scenes() -> void:
	var production_scene := load(PRODUCTION_SCENE_PATH) as PackedScene
	_check(production_scene != null, "Production terrain scene does not load")
	if production_scene != null:
		var production_instance := production_scene.instantiate() as TileMapLayer
		_check(production_instance != null, "Production terrain scene root must be TileMapLayer")
		if production_instance != null:
			_check(production_instance.tile_set != null, "Production terrain scene must bind the TileSet")
			_check(production_instance.scale == Vector2.ONE, "Production terrain layer scale must remain 1,1")
			production_instance.free()

	var authoring_scene := load(AUTHORING_SCENE_PATH) as PackedScene
	_check(authoring_scene != null, "Authoring lab scene does not load")
	if authoring_scene == null:
		return
	var lab := authoring_scene.instantiate()
	var terrain := lab.get_node_or_null("AuthoredGrassDirtTerrain") as TileMapLayer
	_check(terrain != null, "Authoring lab must contain AuthoredGrassDirtTerrain")
	if terrain != null:
		var used_cells := terrain.get_used_cells()
		_check(used_cells.size() >= 200, "Authoring lab must contain substantial saved tile data")
		var atlas_coordinates: Dictionary = {}
		for cell in used_cells:
			atlas_coordinates[terrain.get_cell_atlas_coords(cell)] = true
		var sorted_atlas_coordinates: Array = atlas_coordinates.keys()
		sorted_atlas_coordinates.sort()
		print("TerrainAuthoringLab atlas coordinates: ", sorted_atlas_coordinates)
		_check(atlas_coordinates.size() == 16, "Authoring lab must exercise all 16 atlas corner combinations; found %d" % atlas_coordinates.size())
		print("TerrainAuthoringLab: %d saved cells, %d atlas combinations" % [used_cells.size(), atlas_coordinates.size()])
	lab.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
