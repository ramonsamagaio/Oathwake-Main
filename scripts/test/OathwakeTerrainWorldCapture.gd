extends SceneTree
const WorldScene := preload("res://scenes/world/RomesteadProceduralGameWorld.tscn")
const HeroRig := preload("res://scripts/labs/alabaster/WayfarerRig.gd")
const OUT := "res://docs/terrain/"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size=Vector2i(1280,720)
	var canvas := SubViewport.new()
	canvas.size=Vector2i(800,450)
	canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var container := Node2D.new()
	canvas.add_child(container)
	var resources := Node2D.new()
	resources.name="Resources"
	container.add_child(resources)
	var camera := Camera2D.new()
	canvas.add_child(camera)
	var world := WorldScene.instantiate()
	world.auto_generate=false
	container.add_child(world)
	world.generate_world(74291)
	for i in range(8): await process_frame
	var best := Vector2i.ZERO
	var best_score := -100000.0
	# Select a real generated clearing near biome transitions and a cliff, not a mock map.
	for y in range(-100,100,4):
		for x in range(-170,170,4):
			var candidate := Vector2i(x,y)
			if int(world._terrain_types.get(candidate,0)) != 0: continue
			if world._is_world_position_blocked(Vector2(candidate*16),9.0,false): continue
			var kinds: Dictionary={}
			var cliff_count:=0
			var dark_count:=0
			for dy in range(-12,13,3):
				for dx in range(-23,24,3):
					var cell:=candidate+Vector2i(dx,dy)
					var kind: int=world._terrain_types.get(cell,0)
					kinds[kind]=int(kinds.get(kind,0))+1
					if world._plains_cliffs.has(cell): cliff_count+=1
					if world._forest_barriers.has(cell): dark_count+=1
			var sand: int = kinds.get(0,0)
			var earth: int = kinds.get(1,0)
			var grass: int = kinds.get(2,0)
			var score:=float(mini(sand,40)+mini(earth,30)*2+mini(grass,30)*2+mini(cliff_count,8)*2-dark_count*3)-Vector2(candidate).length()*.02
			if score>best_score:
				best_score=score
				best=candidate
	var targets := [best,Vector2i.ZERO]
	var center: Vector2 = world._forest_center_grid
	targets.append(Vector2i(center) - world.world_size_tiles/2)
	var hero := HeroRig.new()
	container.add_child(hero)
	hero.facing_degrees=180.0
	hero.z_index=100
	for index in range(targets.size()):
		camera.position=Vector2(targets[index]*16)
		hero.position=camera.position+Vector2(8,8)
		camera.force_update_scroll()
		var bounds := Rect2(camera.position-Vector2(480,310),Vector2(960,620))
		world.stream_terrain_for_bounds(bounds,1024)
		world.process_deferred_props(2000)
		for i in range(12): await process_frame
		for styled in [false,true]:
			world.use_oathwake_tilesets=styled
			world._load_editable_textures()
			world._prepare_tilesets()
			# Rebuild augment colors for an honest same-layout before/after comparison.
			var augment := root.get_node_or_null("ProceduralWorldAugment")
			if augment != null: augment.call("_augment_world")
			for layer in world._all_tile_layers(): layer.update_internals()
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			canvas.get_texture().get_image().save_png(OUT+"world-%d-%s-native.png" % [index,"after" if styled else "before"])
	print("OATHWAKE_WORLD_CAPTURE seed=74291 size=",world.world_size_tiles," resources=",resources.get_child_count()," targets=",targets)
	quit()
