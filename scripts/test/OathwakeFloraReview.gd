## Arranged art comparison using production prop spawning, shadows and wind pivots.
## Does not create a session or write game saves.
extends SceneTree
const WorldScene := preload("res://scenes/world/RomesteadProceduralGameWorld.tscn")
const OUT := "res://docs/resources/native/flora/"
var failures: Array[String] = []

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1000,600)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(768,256)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(viewport)
	var world = WorldScene.instantiate()
	world.auto_generate = false
	world.use_oathwake_tilesets = true
	viewport.add_child(world)
	if not world.is_node_ready(): await world.ready
	await process_frame
	if not world._has_required_nodes(): push_error("Flora review missing world layers");quit(1);return
	world.set_process(false)
	world._load_editable_textures()
	world._prepare_tilesets()
	var expected := Image.load_from_file(OUT+"flora_ground_plants.png")
	var current: Image = world._textures["ground_plants"].get_image()
	# After publication this also checks the live skin redirect.
	var active_matches: bool = current.get_data() == expected.get_data()
	if "--require-active" in OS.get_cmdline_user_args() and not active_matches:
		failures.append("Published atlas does not match reviewed art")
	world._textures["ground_plants"] = ImageTexture.create_from_image(expected)
	for y in range(16):
		for x in range(48):
			world._ground.set_cell(Vector2i(x,y),0,Vector2i(2,1))
			if x>=16 and x<32: world._green_layers[0].set_cell(Vector2i(x,y),0,Vector2i(2,1))
			elif x>=32: world._dirt_layers[0].set_cell(Vector2i(x,y),0,Vector2i(2,1))
	for layer in world._all_tile_layers(): layer.update_internals()
	var seeds: Dictionary = {}
	for seed_value in range(10000):
		var rng := RandomNumberGenerator.new()
		rng.seed=seed_value
		var column := rng.randi_range(0,5)
		var row := rng.randi_range(0,1)
		var frame := row*6+column
		if not seeds.has(frame): seeds[frame] = seed_value
		if seeds.size()==12:break
	if seeds.size()!=12: failures.append("Unable to cover twelve frames")
	for terrain in range(3):
		var label := Label.new()
		label.position=Vector2(terrain*256+16,12)
		label.text=["AREIA", "GRAMA OLIVA", "TERRA"][terrain]
		label.add_theme_color_override("font_color",Color("30372b"))
		label.add_theme_font_size_override("font_size",13)
		viewport.add_child(label)
		for frame in range(12):
			var at := Vector2(terrain*256+40+(frame%4)*58,84+(frame/4)*66)
			world._spawn_prop(at,world.PropKind.GROUND_PLANT,seeds[frame])
			var plant: Node2D=world._vegetation.get_child(-1)
			if plant.find_children("*","CollisionObject2D",true,false).size()>0: failures.append("Decorative plant has collision")
			var pivot: Node2D=plant.get_child(1)
			var sprite: Sprite2D=pivot.get_child(0)
			var texture: AtlasTexture=sprite.texture
			var wanted:=Rect2((frame%6)*32,(frame/6)*32,32,32)
			if texture.region!=wanted: failures.append("Wrong frame %d"%frame)
			if sprite.position!=Vector2(0,-16) or sprite.scale!=Vector2.ONE: failures.append("Native anchor or scale changed")
			pivot.rotation=0.06
			if sprite.to_global(Vector2(0,16)).distance_to(plant.global_position)>0.001: failures.append("Foot moves under wind")
			pivot.rotation=0
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(OUT+"on-terrain-native.png")
	var result:={"frames":12,"terrain_backgrounds":3,"production_instances":36,
		"active_atlas_matches":active_matches,"native_scale":true,"failures":failures,
		"fixture":"Arranged comparison using production _spawn_prop; not random world placements."}
	FileAccess.open(OUT+"runtime-qa.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("OATHWAKE_FLORA_REVIEW ",JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
