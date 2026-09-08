## Isolated visual comparison: real procedural terrain and ResourceNode sprites.
## Does not modify ContentDB files or load/create a player save.
extends SceneTree
const WorldScene := preload("res://scenes/world/RomesteadProceduralGameWorld.tscn")
const Factory := preload("res://scripts/resources/ResourceSceneFactory.gd")
const HeroRig := preload("res://scripts/labs/alabaster/WayfarerRig.gd")
const OUT := "res://docs/resources/native/"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size=Vector2i(1000,720)
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(1000,720)
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(viewport)
	var stage:=Node2D.new()
	viewport.add_child(stage)
	var streamed:=Node2D.new()
	streamed.name="Resources"
	stage.add_child(streamed)
	var world:=WorldScene.instantiate()
	world.auto_generate=false
	world.use_oathwake_tilesets=true
	stage.add_child(world)
	if not world.is_node_ready():await world.ready
	await process_frame
	if not world._has_required_nodes():
		push_error("Reference preview: terrain scene is not ready or has missing layers")
		for property in world.get_property_list():
			var key:String=property["name"]
			if key.begins_with("_") and world.get(key)==null:print("NULL_FIELD ",key)
		quit(1)
		return
	world.generate_world(74291)
	var camera:=Camera2D.new()
	camera.position=Vector2(-288,-44)
	viewport.add_child(camera)
	camera.force_update_scroll()
	world.stream_terrain_for_bounds(Rect2(camera.position-Vector2(550,400),Vector2(1100,800)),2048)
	world.process_deferred_props(2000)
	for i in range(12):await process_frame
	streamed.hide()
	for layer in world._all_tile_layers():layer.update_internals()
	var info:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"reference3-family.json"))
	var models:Array=info["models"]
	var crown_texture:=ImageTexture.create_from_image(Image.load_from_file(OUT+"reference3-crowns.png"))
	var trunk_texture:=ImageTexture.create_from_image(Image.load_from_file(OUT+"reference3-trunks.png"))
	var positions:=[Vector2(-380,-130),Vector2(-190,-130),Vector2(0,-130),Vector2(190,-130),Vector2(380,-130),Vector2(-380,78),Vector2(-190,78),Vector2(0,78),Vector2(190,78),Vector2(380,78),Vector2(-270,285),Vector2(280,285)]
	var factory:=Factory.new()
	var instances:Array=[]
	for i in range(models.size()):
		var node=factory.instantiate_resource("tree2","reference3_%d"%i,camera.position+positions[i])
		stage.add_child(node)
		instances.append(node)
	for i in range(4):await process_frame
	for i in range(models.size()):
		var node=instances[i]
		node.set_process(false)
		var model:Dictionary=models[i]
		var anchor:=Vector2(float(model["anchor"][0]),float(model["anchor"][1]))
		var rect:=Rect2((i%6)*128,(i/6)*192,128,192)
		var trunk:Sprite2D=node.layered_trunk_sprite
		var crown:Sprite2D=node.layered_canopy_sprite
		for sprite in [trunk,crown]:
			sprite.region_enabled=true
			sprite.region_rect=rect
			sprite.offset=Vector2(64,96)-anchor
			sprite.material=null
			sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		trunk.texture=trunk_texture
		crown.texture=crown_texture
		trunk.position=Vector2.ZERO
		var pivot:Node2D=node.layered_canopy_wind_pivot
		pivot.rotation=0
		pivot.position=Vector2(0,float(model["cut_native"])-anchor.y)
		crown.position=-pivot.position
		var shadow=node.get_node_or_null("RomesteadShadow")
		if shadow!=null:shadow.hide()
	var hero:=HeroRig.new()
	hero.position=camera.position+Vector2(0,265)
	hero.facing_degrees=180
	hero.z_index=100
	stage.add_child(hero)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(OUT+"reference3-in-godot.png")
	print("REFERENCE3_REVIEW: 12 trees; native scale 1; seed 74291; preview-only, catalog unchanged")
	quit()
