extends SceneTree
const WorldScene := preload("res://scenes/world/RomesteadProceduralGameWorld.tscn")
const AugmentScript := preload("res://scripts/systems/ProceduralWorldAugment.gd")
const OUT := "res://docs/terrain/"
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var canvas := SubViewport.new()
	canvas.size = Vector2i(640,360)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var camera := Camera2D.new()
	canvas.add_child(camera)
	camera.position = Vector2(320,180)
	var world := WorldScene.instantiate()
	var production_skin: bool = world.use_oathwake_tilesets
	world.auto_generate = false
	canvas.add_child(world)
	world.remove_from_group("procedural_resource_world")
	world.set_process(false)
	world._prepare_tilesets()
	world._prepare_noise()
	# Draw the actual runtime's eight-neighbour topology on controlled islands/holes.
	for y in range(-2,25):
		for x in range(-2,43):
			var type := 0
			if x > 26: type = 1
			if (Vector2(x-8,y-7).length() < 6.3 or Vector2(x-14,y-19).length() < 6.5): type = 2
			if x < 6 and y > 13: type = 3
			if x < 3 and y > 18: type = 4
			if Vector2(x-8,y-7).length() < 1.8: type=0
			world._terrain_types[Vector2i(x,y)] = type
			world._biomes[Vector2i(x,y)] = [5,1,2,6,7][type]
	for styled in [false,true]:
		world.use_oathwake_tilesets=styled
		world._load_editable_textures()
		world._prepare_tilesets()
		for y in range(24):
			for x in range(42):
				var cell := Vector2i(x,y)
				world._ground.set_cell(cell,0,Vector2i(2,1))
				world._draw_native_autotile(cell,1,world._dirt_layers)
				world._draw_native_autotile(cell,2,world._green_layers)
				world._draw_native_autotile(cell,3,world._forest_light_layers)
				world._draw_native_autotile(cell,4,world._forest_deep_layers)
				world._draw_native_detail(cell,world._terrain_types[cell])
		for layer in world._all_tile_layers(): layer.update_internals()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		canvas.get_texture().get_image().save_png(OUT + ("terrain-after-native.png" if styled else "terrain-before-native.png"))
	# All 256 masks must resolve to in-bounds opaque-bearing authored cells.
	var checked := 0
	for mask in range(256):
		var pieces: Array = world._surrounding_mask_to_piece_masks(mask)
		for part in range(pieces.size()):
			for role in range(1,5):
				var frame: int = world._frame_for_mask(pieces[part],Vector2i(mask,role),part,role)
				if frame<0 or frame>=76: failures.append("Invalid frame for mask %d" % mask)
				checked += 1
	# Texture replacements are confined to terrain/decorative leaves and never resources.
	var new_image: Image = world._textures["green"].get_image()
	var expected := Image.new()
	expected.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/sprites/world/procedural/terrain/oathwake_tilesets/short_grass.png"))
	if new_image.get_data()!=expected.get_data(): failures.append("Wrong active terrain atlas")
	var resource := load(world.TREE_CANOPY_1_PATH) as Texture2D
	if world._textures["tree1"].get_image().get_data()!=resource.get_image().get_data(): failures.append("Resource changed")
	for layer in [world._base_details,world._green_details,world._dirt_details,world._tiny_flowers,world._tiny_leaves]:
		if layer.tile_set.get_physics_layers_count()!=0: failures.append("Decoration collision")
	if world._forest_barrier_bottom.tile_set.get_physics_layers_count()!=1: failures.append("Barrier collision lost")
	if world._plains_cliff_collision.tile_set.get_physics_layers_count()!=1: failures.append("Cliff collision lost")
	# Review actual road renderer on bends, ends and a T-junction over native ground.
	var augment := AugmentScript.new()
	augment._attached_world = world
	var road: TileMapLayer = augment._make_road_layer("ProceduralRoads", augment.ROAD_Z)
	world.add_child(road)
	var road_cells: Dictionary = {}
	for y in range(3,6):
		for x in range(3,19): road_cells[Vector2i(x,y)] = true
	for y in range(3,18):
		for x in range(16,19): road_cells[Vector2i(x,y)] = true
	for y in range(16,18):
		for x in range(5,19): road_cells[Vector2i(x,y)] = true
	for y in range(3,6):
		for x in range(25,37): road_cells[Vector2i(x,y)] = true
	for y in range(4,20):
		for x in range(30,32): road_cells[Vector2i(x,y)] = true
	var logical_cells := road_cells.duplicate()
	augment.OathwakeRoadEdges.paint(road, road_cells, {}, world._terrain_types)
	if road_cells != logical_cells: failures.append("Visual road pass changed logical route")
	if not augment._road_uses_edge_atlas: failures.append("Authored road atlas not active")
	if road.tile_set.get_physics_layers_count()!=0: failures.append("Road edge added collision")
	var road_image: Image = road.tile_set.get_source(0).texture.get_image()
	if road_image.get_size()!=Vector2i(256,2048): failures.append("Road atlas dimensions")
	var soil_join := road.get_cell_atlas_coords(Vector2i(30,19))
	if posmod(soil_join.y*16+soil_join.x,512)!=511: failures.append("Road end leaves a cap over matching soil")
	for cell_value in road_cells:
		var cell := Vector2i(cell_value)
		var coord := road.get_cell_atlas_coords(cell)
		if road_image.get_pixelv(coord*16+Vector2i(8,8)).a<1.0: failures.append("Road center disconnected")
	road.update_internals()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	canvas.get_texture().get_image().save_png(OUT+"road-edge-review-native.png")
	augment.free()
	var report := {"mask_count":256,"piece_variants_checked":checked,"road_atlas_frames":2048,"road_route_preserved":road_cells==logical_cells,"failures":failures,"default_production_skin":production_skin}
	FileAccess.open(OUT+"terrain-runtime-validation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("OATHWAKE_TERRAIN_REVIEW ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
