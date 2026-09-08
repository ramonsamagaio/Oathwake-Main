## Same production-world regions, seed and camera for the border comparison.
extends SceneTree
const WorldScene := preload("res://scenes/world/RomesteadProceduralGameWorld.tscn")
const HeroRig := preload("res://scripts/labs/alabaster/WayfarerRig.gd")
const OUT := "res://docs/terrain/reference-edge-revision/"
func _initialize()->void:call_deferred("_run")
func _run()->void:
	root.size=Vector2i(1200,760)
	var canvas:=SubViewport.new()
	canvas.size=Vector2i(1000,680)
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
	var world=WorldScene.instantiate()
	world.auto_generate=false
	world.use_oathwake_tilesets=true
	container.add_child(world)
	if not world.is_node_ready():await world.ready
	await process_frame
	if not world._has_required_nodes():push_error("World capture missing layers");quit(1);return
	world.generate_world(74291)
	for i in range(8):await process_frame
	var hero:=HeroRig.new()
	container.add_child(hero)
	hero.facing_degrees=180.0
	hero.z_index=100
	var targets:=[Vector2i(-18,-4),Vector2i(-187,29)]
	var suffix:="before" if "--before" in OS.get_cmdline_user_args() else "after"
	var output_path:= "res://docs/resources/native/stones/" if "--stones" in OS.get_cmdline_user_args() else OUT
	for index in range(targets.size()):
		camera.position=Vector2(targets[index]*16)
		hero.position=camera.position+Vector2(8,8)
		camera.force_update_scroll()
		world.stream_terrain_for_bounds(Rect2(camera.position-Vector2(560,400),Vector2(1120,800)),2048)
		world.process_deferred_props(3000)
		for i in range(18):await process_frame
		for layer in world._all_tile_layers():layer.update_internals()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		canvas.get_texture().get_image().save_png(output_path+"world-%d-%s.png"%[index,suffix])
	print("REFERENCE_EDGE_WORLD seed=74291 resources=",resources.get_child_count()," targets=",targets," stage=",suffix)
	quit()
