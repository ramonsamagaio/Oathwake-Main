## Controlled edge topology, before/after from the same terrain cells.
extends SceneTree
const WorldScene := preload("res://scenes/world/RomesteadProceduralGameWorld.tscn")
const RoadEdges := preload("res://scripts/world/terrain/OathwakeRoadEdges.gd")
const OUT := "res://docs/terrain/reference-edge-revision/"
const FILES := {"base":"plainsgrass2","dirt":"plainsgrass3","green":"short_grass","forest_light":"plainsgrass1","forest_deep":"tall_grass"}
var failures: Array[String]=[]

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	root.size=Vector2i(1100,720)
	var canvas:=SubViewport.new()
	canvas.size=Vector2i(640,384)
	canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	canvas.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(canvas)
	var camera:=Camera2D.new()
	camera.position=Vector2(312,184)
	canvas.add_child(camera)
	var world=WorldScene.instantiate()
	world.auto_generate=false
	world.use_oathwake_tilesets=true
	canvas.add_child(world)
	if not world.is_node_ready(): await world.ready
	await process_frame
	if not world._has_required_nodes():push_error("Missing edge-review layers");quit(1);return
	world.set_process(false)
	world.remove_from_group("procedural_resource_world")
	world._load_editable_textures()
	var active_matches:=true
	for key in FILES:
		var expected:=Image.load_from_file(OUT+FILES[key]+".png")
		active_matches=active_matches and world._textures[key].get_image().get_data()==expected.get_data()
	if "--require-active" in OS.get_cmdline_user_args() and not active_matches:failures.append("Active terrain files differ")
	world._prepare_noise()
	for y in range(-2,27):
		for x in range(-2,43):
			var type:=0
			if x>26 and y>12:type=1
			if Vector2(x-7,y-6).length()<5.8 or Vector2(x-12,y-18).length()<6.2:type=2
			if Vector2(x-8,y-6).length()<1.7:type=0
			if x<3 and y>14:type=3
			if x<1 and y>19:type=4
			world._terrain_types[Vector2i(x,y)]=type
	var logical: Dictionary=world._terrain_types.duplicate()
	var road_cells: Dictionary={}
	for x in range(20,36):
		for y in range(3,6):road_cells[Vector2i(x,y)]=true
	for x in range(26,29):
		for y in range(3,21):road_cells[Vector2i(x,y)]=true
	for x in range(18,29):
		for y in range(19,21):road_cells[Vector2i(x,y)]=true
	var road:=TileMapLayer.new()
	road.z_index=-4086
	road.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	world.add_child(road)
	for prefix in ["before/", ""]:
		for key in FILES:
			world._textures[key]=ImageTexture.create_from_image(Image.load_from_file(OUT+prefix+FILES[key]+".png"))
		world._prepare_tilesets()
		world._assign_native_tileset(road,ImageTexture.create_from_image(Image.load_from_file(OUT+prefix+"oathwake_road.png")))
		for y in range(25):
			for x in range(41):
				var cell:=Vector2i(x,y)
				world._ground.set_cell(cell,0,Vector2i(2,1))
				world._draw_native_autotile(cell,1,world._dirt_layers)
				world._draw_native_autotile(cell,2,world._green_layers)
				world._draw_native_autotile(cell,3,world._forest_light_layers)
				world._draw_native_autotile(cell,4,world._forest_deep_layers)
		RoadEdges.paint(road,road_cells,{},world._terrain_types)
		for layer in world._all_tile_layers():layer.update_internals()
		road.update_internals()
		camera.force_update_scroll()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		canvas.get_texture().get_image().save_png(OUT+("topology-before-native.png" if prefix!="" else "topology-after-native.png"))
	var checked:=0
	for mask in range(256):
		var pieces: Array=world._surrounding_mask_to_piece_masks(mask)
		for piece in range(pieces.size()):
			for role in range(1,5):
				var frame: int=world._frame_for_mask(pieces[piece],Vector2i(mask,role),piece,role)
				if frame<0 or frame>=76:failures.append("Unmapped neighbor mask")
				checked+=1
	for layer in [world._ground,world._green_layers[0],world._dirt_layers[0],road]:
		if layer.tile_set.get_physics_layers_count()!=0:failures.append("Added ground collision")
	if world._plains_cliff_collision.tile_set.get_physics_layers_count()!=1:failures.append("Lost cliff collision")
	if world._forest_barrier_bottom.tile_set.get_physics_layers_count()!=1:failures.append("Lost forest collision")
	if world._terrain_types!=logical:failures.append("Changed logical terrain")
	for cell in road_cells:
		var frame:=road.get_cell_atlas_coords(cell)
		var tex: Texture2D=road.tile_set.get_source(0).texture
		if tex.get_image().get_pixelv(frame*16+Vector2i(8,8)).a<1:failures.append("Road center broken")
	var report:={"active_terrain_matches":active_matches,"neighbor_masks":256,"piece_selections":checked,
		"logical_terrain_preserved":world._terrain_types==logical,"road_cells":road_cells.size(),"failures":failures}
	FileAccess.open(OUT+"runtime-qa.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("REFERENCE_EDGES_REVIEW ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
