## Isolated art review using real ResourceNode instances; never starts a session.
extends SceneTree
const Factory := preload("res://scripts/resources/ResourceSceneFactory.gd")
const WorldScene := preload("res://scenes/world/RomesteadProceduralGameWorld.tscn")
const OUT := "res://docs/resources/"
var failures: Array[String] = []
var checked:=0

func _initialize()->void:
	call_deferred("_run")

func _run()->void:
	root.size=Vector2i(1280,720)
	var view:=SubViewport.new()
	view.size=Vector2i(800,600)
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	view.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(view)
	var container:=Node2D.new()
	view.add_child(container)
	var world:=WorldScene.instantiate()
	world.auto_generate=false
	container.add_child(world)
	world.remove_from_group("procedural_resource_world")
	world.set_process(false)
	world._prepare_tilesets()
	for y in range(-2,41):
		for x in range(-2,52):
			world._ground.set_cell(Vector2i(x,y),0,Vector2i(2,1))
			if x<17:world._green_layers[0].set_cell(Vector2i(x,y),0,Vector2i(2,1))
			elif x>33:world._dirt_layers[0].set_cell(Vector2i(x,y),0,Vector2i(2,1))
	for layer in world._all_tile_layers():layer.update_internals()
	var factory:=Factory.new()
	var trees:Array=[]
	for n in range(2,43):
		var i:=n-2
		var node=factory.instantiate_resource("tree%d"%n,"art_review_tree%d"%n,Vector2(48+(i%10)*78,110+(i/10)*106))
		container.add_child(node)
		trees.append(node)
		var label:=Label.new()
		label.text="%d"%n
		label.add_theme_font_size_override("font_size",9)
		label.position=node.position+Vector2(-5,4)
		label.z_index=1000
		label.add_to_group("oathwake_review_label")
		container.add_child(label)
	for i in range(6):await process_frame
	for node in trees:
		var crown:Sprite2D=node.layered_canopy_sprite
		var trunk:Sprite2D=node.layered_trunk_sprite
		if crown==null or trunk==null:failures.append("Missing pair "+node.resource_type_id);continue
		if not crown.texture.resource_path.ends_with("tree_crowns.png"):failures.append("Wrong crown "+node.resource_type_id)
		if not trunk.texture.resource_path.ends_with("tree_trunks.png"):failures.append("Wrong trunk "+node.resource_type_id)
		if crown.position!=Vector2(0,-8):failures.append("Wrong canopy lift "+node.resource_type_id)
		if trunk.position!=Vector2.ZERO:failures.append("Wrong root origin "+node.resource_type_id)
		if crown.z_index<=trunk.z_index:failures.append("Wrong z-order "+node.resource_type_id)
		checked+=1
	await capture(view,"tree-pairs-alive-native.png")
	# Sample a real tween, then exercise the cut/regrow sprite states on every pair.
	var sample=trees[2]
	var original_position:Vector2=sample.layered_trunk_sprite.position
	sample._start_romestead_tree_fall()
	await create_timer(0.45).timeout
	if absf(sample.layered_canopy_wind_pivot.rotation)<.05:failures.append("Tree fall did not move crown")
	if sample.layered_trunk_sprite.position!=original_position:failures.append("Root moved during fall")
	await capture(view,"tree-falling-native.png")
	await create_timer(1.0).timeout
	if sample.layered_canopy_sprite.visible:failures.append("Felled crown still visible")
	for node in trees:
		node._apply_destroyed_stump_sprite()
		node.layered_canopy_sprite.visible=false
		var shadow=node.get_node_or_null("RomesteadShadow")
		if shadow!=null:shadow.visible=false
		var frame:int=(int(node.resource_type_id.trim_prefix("tree"))-2)*2+1
		if node.layered_trunk_sprite.region_rect.position!=Vector2((frame%16)*64,(frame/16)*32):failures.append("Wrong cut stump "+node.resource_type_id)
	await capture(view,"tree-stumps-native.png")
	sample._respawn()
	if sample.collected_state or sample.health!=sample.max_health:failures.append("Tree respawn state not restored")
	var remnants:=get_nodes_in_group("procedural_tree_stump_remnant")
	if remnants.is_empty():failures.append("Persistent stump remnant missing")
	for remnant in remnants:remnant.hide()
	for node in trees:
		node.set_collected(false)
		node._tree_stump_visible=false
		node._restore_living_tree_visual()
		if not node.layered_canopy_sprite.visible:failures.append("Crown not restored "+node.resource_type_id)
	await capture(view,"tree-regrown-native.png")
	# Every other procedural ResourceNode is instantiated through the real factory.
	for node in trees:node.visible=false
	for label in get_nodes_in_group("oathwake_review_label"):label.visible=false
	var ids:Array[String]=[]
	for prefix_count in [["rock",10],["stone",8],["bush",21],["wheat",24]]:
		for n in range(1,int(prefix_count[1])+1):ids.append(str(prefix_count[0])+str(n))
	ids.append_array(["mossy_rock1","copper_ore_node","mushroom_red","mushroom_brown","mushroom_yellow","bellflower1","lily1","purple_bush1","forest_bush1"])
	for i in range(ids.size()):
		var node=factory.instantiate_resource(ids[i],"art_review_"+ids[i],Vector2(40+(i%12)*65,75+(i/12)*72))
		container.add_child(node)
		if node.content_sprite==null or not node.content_sprite.texture.resource_path.contains("oathwake_tilesets/resources/"):failures.append("Resource not reskinned "+ids[i])
	await capture(view,"resources-native.png")
	for child in container.get_children():
		if child!=world:child.hide()
	# Decoration uses the exact 32px cells and wind builder used by the world.
	for i in range(12):
		var plant:=Node2D.new()
		plant.position=Vector2(86+(i%6)*126,230+(i/6)*150)
		container.add_child(plant)
		world._build_wind_sprite(plant,world._textures["ground_plants"],Rect2i((i%6)*32,(i/6)*32,32,32),0.0,0.42)
		if not plant.find_children("*","CollisionObject2D",true,false).is_empty():failures.append("Decorative flora gained collision")
	await capture(view,"flora-in-engine-native.png")
	var file:=FileAccess.open(OUT+"runtime-qa.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"tree_pairs":checked,"other_resources":ids.size(),"fall_tween_checked":true,"failures":failures},"\t"));file.close()
	print("OATHWAKE_RESOURCE_REVIEW ",checked," pairs, ",ids.size()," resources; failures=",failures)
	quit(0 if failures.is_empty() else 1)

func capture(view:SubViewport,name:String)->void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png(OUT+name)
