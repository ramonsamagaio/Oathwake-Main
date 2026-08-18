extends SceneTree

const WORLD_SCENE := preload("res://scenes/world/RomesteadProceduralGameWorld.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := WORLD_SCENE.instantiate()
	world.world_size_tiles = Vector2i(120, 80)
	root.add_child(world)
	for _index in range(8):
		await process_frame
	var invalid := 0
	for child in world.get_children():
		if not child is TileMapLayer:
			continue
		var layer := child as TileMapLayer
		var source := layer.tile_set.get_source(0) as TileSetAtlasSource if layer.tile_set != null and layer.tile_set.has_source(0) else null
		if source == null:
			continue
		for cell in layer.get_used_cells():
			var coord := layer.get_cell_atlas_coords(cell)
			if not source.has_tile(coord):
				invalid += 1
				print("INVALID_TILE layer=%s cell=%s atlas=%s" % [layer.name, cell, coord])
			if layer.name == "TinyLeaves" and coord.x >= 8:
				invalid += 1
				print("WHITE_SENTINEL_TILE layer=%s cell=%s atlas=%s" % [layer.name, cell, coord])
	var biomes := world.get("_biomes") as Dictionary
	var barrier_cells := world.get("_forest_barriers") as Dictionary
	var left_cells := world.get("_forest_tree_left") as Dictionary
	var right_cells := world.get("_forest_tree_right") as Dictionary
	for cell_value in barrier_cells.keys():
		var cell := cell_value as Vector2i
		if int(biomes.get(cell, -1)) not in [3, 6, 7]:
			invalid += 1
			print("FOREST_WALL_OUTSIDE_FOREST cell=%s biome=%s" % [cell, biomes.get(cell, -1)])
		var has_cardinal := false
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if barrier_cells.has(cell + offset) or left_cells.has(cell + offset) or right_cells.has(cell + offset):
				has_cardinal = true
				break
		if not has_cardinal:
			invalid += 1
			print("ISOLATED_FOREST_WALL cell=%s" % cell)
	print("ROMESTEAD_ATLAS_COORDINATES invalid=%d" % invalid)
	quit(0 if invalid == 0 else 1)
