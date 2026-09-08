## Real ContentDB + ResourceNode fall/respawn contract in an isolated viewport.
extends SceneTree
const Factory := preload("res://scripts/resources/ResourceSceneFactory.gd")
const OUT := "res://docs/resources/native/integration/"
var failures:Array[String]=[]

func _initialize()->void:call_deferred("_run")

func check(condition:bool,message:String)->void:
	if not condition:failures.append(message)

func capture(view:SubViewport,file:String)->Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image:=view.get_texture().get_image()
	image.save_png(OUT+file)
	return image

func _run()->void:
	root.size=Vector2i(1280,900)
	var watchdog:=create_timer(55)
	watchdog.timeout.connect(func():push_error("Integrated tree review timed out");quit(2))
	var view:=SubViewport.new()
	view.size=Vector2i(1280,1260)
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	view.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(view)
	var background:=ColorRect.new()
	background.size=Vector2(1280,1260)
	background.color=Color("777960")
	view.add_child(background)
	var stage:=Node2D.new()
	view.add_child(stage)
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"manifest.json"))
	var records:Array=manifest["variants"]
	var factory:=Factory.new()
	var nodes:Array=[]
	for i in range(records.size()):
		var rec:Dictionary=records[i]
		var node=factory.instantiate_resource(rec["resource"],"integrated_review_%d"%i,Vector2(75+(i%8)*155,185+(i/8)*205))
		stage.add_child(node)
		nodes.append(node)
		var label:=Label.new()
		label.text=rec["resource"]+" / "+rec["model"]
		label.add_theme_font_size_override("font_size",9)
		label.position=node.position+Vector2(-50,7)
		label.z_index=1000
		stage.add_child(label)
	for i in range(4):await process_frame
	for i in range(nodes.size()):
		var node=nodes[i];var rec:Dictionary=records[i]
		node.set_process(false)
		var pivot:=Vector2(rec["pivot"][0],rec["pivot"][1])
		var crown:Sprite2D=node.layered_canopy_sprite
		var trunk:Sprite2D=node.layered_trunk_sprite
		check(crown!=null and trunk!=null,rec["resource"]+" missing parts")
		if crown==null or trunk==null:continue
		check(crown.texture.resource_path.ends_with("integrated-tree-crowns.png"),rec["resource"]+" crown texture")
		check(trunk.texture.resource_path.ends_with("integrated-tree-trunks.png"),rec["resource"]+" trunk texture")
		check(node.layered_canopy_wind_pivot.position.is_equal_approx(pivot),rec["resource"]+" pivot")
		check(crown.position.is_equal_approx(-pivot),rec["resource"]+" assembly compensation")
		check(trunk.position==Vector2.ZERO,rec["resource"]+" grounded base")
		node.set_romestead_environment(0,0,0.8,1,Vector2.RIGHT)
		node.tick_romestead_motion(0.2)
		check(node.layered_canopy_wind_pivot.position.is_equal_approx(pivot),rec["resource"]+" wind shifted joint")
		node._restore_living_tree_visual()
		check(node._romestead_reaction_base_position.is_equal_approx(pivot),rec["resource"]+" cached joint")
	var before:Image=await capture(view,"alive.png")
	# Existing art without an authored joint retains its zero pivot / -8 lift.
	var legacy=nodes[0]
	legacy._restore_canopy_rest_transform({})
	check(legacy.layered_canopy_wind_pivot.position==Vector2.ZERO,"legacy zero pivot")
	check(legacy.layered_canopy_sprite.position==Vector2(0,-8),"legacy lift")
	legacy._restore_living_tree_visual()
	legacy._start_romestead_tree_fall()
	await create_timer(0.45).timeout
	check(absf(legacy.layered_canopy_wind_pivot.rotation)>0.03,"real falling tween did not rotate")
	check(legacy.layered_trunk_sprite.position==Vector2.ZERO,"base moved during fall")
	await capture(view,"falling.png")
	for i in range(1,nodes.size()):nodes[i]._start_romestead_tree_fall()
	await create_timer(1.3).timeout
	for i in range(nodes.size()):
		var node=nodes[i];var rec:Dictionary=records[i]
		var pivot:=Vector2(rec["pivot"][0],rec["pivot"][1])
		check(node.collected_state and not node.layered_canopy_sprite.visible,rec["resource"]+" cut state")
		check(node.layered_trunk_sprite.texture.resource_path.ends_with("integrated-tree-stumps.png"),rec["resource"]+" stump texture")
		check(node.layered_canopy_wind_pivot.position.is_equal_approx(pivot),rec["resource"]+" cut reset")
	await capture(view,"cut-stumps.png")
	for node in nodes:node._respawn();node.set_process(false)
	for remnant in get_nodes_in_group("procedural_tree_stump_remnant"):remnant.hide()
	check(get_nodes_in_group("procedural_tree_stump_remnant").size()==41,"persistent stump remnants")
	for i in range(nodes.size()):
		var node=nodes[i];var rec:Dictionary=records[i]
		check(not node.collected_state and node.health==node.max_health,rec["resource"]+" respawn health")
		check(node.layered_canopy_sprite.visible,rec["resource"]+" respawn crown")
		check(node.layered_trunk_sprite.texture.resource_path.ends_with("integrated-tree-trunks.png"),rec["resource"]+" restored living base")
		check(node.layered_canopy_wind_pivot.position.is_equal_approx(Vector2(rec["pivot"][0],rec["pivot"][1])),rec["resource"]+" respawn joint")
	var after:Image=await capture(view,"regrown.png")
	check(before.get_data()==after.get_data(),"regrown rendering differs from intact rendering")
	var file:=FileAccess.open(OUT+"runtime-qa.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"variants":41,"real_fall_tween":true,"respawn":true,"legacy_pivot_checked":true,"failures":failures},"\t"))
	file.close()
	print("INTEGRATED_TREE_REVIEW failures=",failures)
	quit(0 if failures.is_empty() else 1)
