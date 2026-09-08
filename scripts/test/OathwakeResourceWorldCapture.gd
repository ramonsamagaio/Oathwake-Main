## Real seed, real streamed resources and terrain; no saved player session.
extends SceneTree
const WorldScene := preload("res://scenes/world/RomesteadProceduralGameWorld.tscn")
const HeroRig := preload("res://scripts/labs/alabaster/WayfarerRig.gd")
const OUT := "res://docs/resources/"

func _initialize()->void:call_deferred("_run")

func _run()->void:
	root.size=Vector2i(1280,720)
	var canvas:=SubViewport.new()
	canvas.size=Vector2i(800,450)
	canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	canvas.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(canvas)
	var container:=Node2D.new()
	canvas.add_child(container)
	var resources:=Node2D.new()
	resources.name="Resources"
	container.add_child(resources)
	var camera:=Camera2D.new()
	canvas.add_child(camera)
	var world:=WorldScene.instantiate()
	world.auto_generate=false
	world.use_oathwake_tilesets=true
	container.add_child(world)
	world.generate_world(74291)
	for i in range(8):await process_frame
	var hero:=HeroRig.new()
	container.add_child(hero)
	hero.facing_degrees=180.0
	hero.z_index=100
	var targets:=[Vector2i(-18,-4),Vector2i.ZERO,Vector2i(-187,29)]
	for index in range(targets.size()):
		camera.position=Vector2(targets[index]*16)
		hero.position=camera.position+Vector2(8,8)
		camera.force_update_scroll()
		world.stream_terrain_for_bounds(Rect2(camera.position-Vector2(480,310),Vector2(960,620)),1024)
		world.process_deferred_props(2000)
		for i in range(12):await process_frame
		for layer in world._all_tile_layers():layer.update_internals()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var im:=canvas.get_texture().get_image()
		im.save_png(OUT+"world-%d-native.png"%index)
		im.resize(1600,900,Image.INTERPOLATE_NEAREST)
		im.save_png(OUT+"world-%d.png"%index)
	print("OATHWAKE_RESOURCE_WORLD seed=74291 resources=",resources.get_child_count()," targets=",targets)
	quit()
