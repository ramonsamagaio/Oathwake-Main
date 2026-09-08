## Native atlas coverage plus unmodified flower-noise placement on a test meadow.
## No player session or save files. Arranged terrain, actual detail-generation rules.
extends SceneTree
const WorldScene := preload("res://scenes/world/RomesteadProceduralGameWorld.tscn")
const OUT := "res://docs/resources/native/ground-details/"
var failures: Array[String] = []
var world
var viewport: SubViewport
var camera: Camera2D

func _initialize() -> void: call_deferred("_run")

func _texture(file: String) -> ImageTexture:
	return ImageTexture.create_from_image(Image.load_from_file(OUT+file+".png"))

func _set_art(prefix: String = "") -> void:
	world._assign_native_tileset(world._tiny_leaves,_texture(prefix+"flora_tiny_ground_leaves"))
	world._assign_native_tileset(world._tiny_flowers,_texture(prefix+"flora_tiny_flowers"))

func _capture(name: String) -> void:
	for layer in world._all_tile_layers(): layer.update_internals()
	camera.force_update_scroll()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(OUT+name+"-native.png")

func _cells() -> Array:
	var result: Array=[]
	for layer in [world._tiny_leaves,world._tiny_flowers]:
		for cell_value in layer.get_used_cells():
			result.append([layer.name,cell_value,layer.get_cell_atlas_coords(cell_value)])
	return result

func _run() -> void:
	root.size=Vector2i(1100,720)
	viewport=SubViewport.new()
	viewport.size=Vector2i(576,192)
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(viewport)
	camera=Camera2D.new()
	camera.position=Vector2(280,88)
	viewport.add_child(camera)
	world=WorldScene.instantiate()
	world.auto_generate=false
	world.use_oathwake_tilesets=true
	world.world_seed=74291
	viewport.add_child(world)
	if not world.is_node_ready(): await world.ready
	await process_frame
	if not world._has_required_nodes(): push_error("Ground detail review missing terrain layers");quit(1);return
	world.set_process(false)
	world._load_editable_textures()
	world._prepare_tilesets()
	world._prepare_noise()
	var active_matches := true
	for pair in [["tiny_leaves","flora_tiny_ground_leaves"],["tiny_flowers","flora_tiny_flowers"]]:
		var active: Image=world._textures[pair[0]].get_image()
		var candidate:=Image.load_from_file(OUT+pair[1]+".png")
		active_matches=active_matches and active.get_data()==candidate.get_data()
	if "--require-active" in OS.get_cmdline_user_args() and not active_matches:
		failures.append("Active texture redirect differs from reviewed exports")
	_set_art()
	for layer in [world._tiny_leaves,world._tiny_flowers]:
		if layer.tile_set.get_physics_layers_count()!=0: failures.append("Detail collision added")
		if layer.texture_filter!=CanvasItem.TEXTURE_FILTER_NEAREST: failures.append("Non-native filtering")
		if layer.z_index>=-4000: failures.append("Detail above actor depth band")
	for y in range(12):
		for x in range(36):
			world._ground.set_cell(Vector2i(x,y),0,Vector2i(2,1))
			if x>=12 and x<24: world._green_layers[0].set_cell(Vector2i(x,y),0,Vector2i(2,1))
			elif x>=24: world._dirt_layers[0].set_cell(Vector2i(x,y),0,Vector2i(2,1))
	var labels: Array[Label]=[]
	for terrain in range(3):
		var label:=Label.new()
		label.position=Vector2(terrain*192+8,5)
		label.text=["AREIA","GRAMA OLIVA","TERRA"][terrain]
		label.add_theme_font_size_override("font_size",12)
		label.add_theme_color_override("font_color",Color("30372b"))
		viewport.add_child(label)
		labels.append(label)
		for row in range(2):
			for column in range(9):
				world._tiny_leaves.set_cell(Vector2i(terrain*12+2+column,4+row*3),0,Vector2i(column,row))
		for frame in range(4):
			world._tiny_flowers.set_cell(Vector2i(terrain*12+3+frame*2,10),0,Vector2i(frame%2,frame/2))
	await _capture("on-terrain")
	for label in labels: label.queue_free()
	for layer in world._all_tile_layers(): layer.clear()
	# Locate a patch using the existing noise, without changing its seed or gate.
	var best:=Vector2i.ZERO
	var best_value: float=-1.0
	for y in range(-256,257,2):
		for x in range(-256,257,2):
			var value: float=absf(world._flower_noise.get_noise_2d(x+16,y+16))
			if value>best_value: best_value=value;best=Vector2i(x,y)
	viewport.size=Vector2i(384,224)
	camera.position=Vector2(best*16)
	for dy in range(-8,9):
		for dx in range(-13,14):
			var cell:=best+Vector2i(dx,dy)
			var type: int=world.TERRAIN_GREEN if dx<0 else world.TERRAIN_FOREST_LIGHT
			world._terrain_types[cell]=type
			world._ground.set_cell(cell,0,Vector2i(2,1))
			world._green_layers[0].set_cell(cell,0,Vector2i(2,1))
			world._draw_native_detail(cell,type)
	var placement:=_cells()
	if placement.is_empty(): failures.append("No actual noise-generated detail cells")
	for layer in [world._tiny_leaves,world._tiny_flowers]:
		for cell_value in layer.get_used_cells():
			var frame: Vector2i=layer.get_cell_atlas_coords(cell_value)
			if frame.y!=(0 if cell_value.x<best.x else 1): failures.append("Biome row changed")
			if layer==world._tiny_leaves and frame.x>=8: failures.append("Reserved leaf frame used")
	_set_art("before-")
	await _capture("cluster-before")
	_set_art()
	await _capture("cluster-after")
	if _cells()!=placement: failures.append("Art switch changed procedural placements")
	var report:={"active_atlases_match":active_matches,"active_frames":20,"reserve_frames":2,
		"comparison_cells":66,"noise_generated_cells":placement.size(),"noise_peak":best_value,
		"center":[best.x,best.y],"placement_preserved":_cells()==placement,"failures":failures,
		"capture":"Arranged terrain; original procedural flower/leaf noise, seeds and density."}
	FileAccess.open(OUT+"runtime-qa.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("OATHWAKE_GROUND_DETAILS_REVIEW ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
