## Twenty real ResourceNode records on three arranged production terrain patches.
## Candidate art can be inspected without publishing or writing a saved session.
extends SceneTree
const WorldScene := preload("res://scenes/world/RomesteadProceduralGameWorld.tscn")
const Factory := preload("res://scripts/resources/ResourceSceneFactory.gd")
const OUT := "res://docs/resources/native/stones/"
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message)
func capture(view:SubViewport,name:String)->void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png(OUT+name+".png")
func _run()->void:
	root.size=Vector2i(1120,650)
	create_timer(50).timeout.connect(func():push_error("Stone review timeout");quit(2))
	var view:=SubViewport.new()
	view.size=Vector2i(1008,480)
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	view.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(view)
	var world=WorldScene.instantiate()
	world.auto_generate=false
	world.use_oathwake_tilesets=true
	view.add_child(world)
	if not world.is_node_ready():await world.ready
	await process_frame
	if not world._has_required_nodes():push_error("Stone review missing terrain layers");quit(2);return
	world.set_process(false)
	world._load_editable_textures()
	world._prepare_tilesets()
	for y in range(30):
		for x in range(63):
			world._ground.set_cell(Vector2i(x,y),0,Vector2i(2,1))
			if x>=21 and x<42:world._green_layers[0].set_cell(Vector2i(x,y),0,Vector2i(2,1))
			elif x>=42:world._dirt_layers[0].set_cell(Vector2i(x,y),0,Vector2i(2,1))
	for layer in world._all_tile_layers():layer.update_internals()
	var stage:=Node2D.new()
	view.add_child(stage)
	var factory:=Factory.new()
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"manifest.json"))
	var before:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"resources-before.json"))
	var require_active:bool="--require-active" in OS.get_cmdline_user_args()
	var nodes:Array=[]
	var records:Array=manifest["records"]
	var active_matches:=true
	var imports:Dictionary={}
	for terrain in range(3):
		var label:=Label.new()
		label.text=["AREIA", "GRAMA OLIVA", "TERRA"][terrain]
		label.position=Vector2(terrain*336+15,12)
		label.add_theme_color_override("font_color",Color("30372b"))
		label.add_theme_font_size_override("font_size",12)
		stage.add_child(label)
		for i in range(records.size()):
			var rec:Dictionary=records[i]
			var node=factory.instantiate_resource(rec["resource"],"stone_review_%d_%d"%[terrain,i],
				Vector2(terrain*336+35+(i%5)*66,110+(i/5)*110))
			stage.add_child(node)
			nodes.append(node)
			var sprite:Sprite2D=node.content_sprite
			check(sprite!=null,rec["resource"]+" missing content sprite")
			if sprite==null:continue
			var expected:=Image.new()
			expected.load_png_from_buffer(FileAccess.get_file_as_bytes(OUT+rec["atlas"]+".png"))
			var matches:bool=sprite.texture.get_image().get_data()==expected.get_data()
			if not imports.has(rec["atlas"]):
				var actual:Image=sprite.texture.get_image()
				var visible_changes:=0
				var transparent_rgb_changes:=0
				for py in range(expected.get_height()):
					for px in range(expected.get_width()):
						var a:Color=actual.get_pixel(px,py)
						var b:Color=expected.get_pixel(px,py)
						if a!=b:
							if a.a==0 and b.a==0:transparent_rgb_changes+=1
							else:visible_changes+=1
				imports[rec["atlas"]]={"visible_changes":visible_changes,"transparent_rgb_changes":transparent_rgb_changes}
			active_matches=active_matches and matches
			if require_active:check(matches,rec["resource"]+" active atlas differs")
			if not require_active:
				sprite.texture=ImageTexture.create_from_image(expected)
				node._refresh_world_presentation()
			var r:Array=rec["region"]
			check(sprite.region_rect==Rect2(r[0],r[1],r[2],r[3]),rec["resource"]+" frame")
			check(sprite.scale==Vector2.ONE,rec["resource"]+" rescaled")
			check(sprite.offset==Vector2(0,-r[3]*0.5),rec["resource"]+" anchor")
			var config:Dictionary=before[rec["resource"]]
			check(node.resource_data==config,rec["resource"]+" resource data changed")
			var body:CollisionShape2D=node.get_node("StaticBody2D/CollisionShape2D")
			var interaction:CollisionShape2D=node.get_node("InteractionShape")
			check(is_equal_approx(body.shape.radius,config["collision"]["body_radius"]),rec["resource"]+" body radius")
			check(is_equal_approx(interaction.shape.radius,config["collision"]["interaction_radius"]),rec["resource"]+" interaction")
			var tag:=Label.new()
			tag.text=rec["resource"].replace("copper_ore_node","cobre").replace("mossy_rock1","musgo")
			tag.position=node.position+Vector2(-22,7)
			tag.add_theme_font_size_override("font_size",9)
			tag.add_theme_color_override("font_color",Color("34372e"))
			tag.z_index=1000
			stage.add_child(tag)
	for i in range(4):await process_frame
	await capture(view,"on-terrain-native")
	for node in nodes:
		var texture:Texture2D=node.content_sprite.texture
		var at:Vector2=node.position
		node.take_damage(1)
		check(node.health==node.max_health-1,node.resource_type_id+" hit health")
		node.tick_romestead_motion(0.02)
		check(node._romestead_hit_timer<0.5,node.resource_type_id+" hit reaction")
		node.set_collected(true,3.0)
		check(not node.visible and node.collected_state,node.resource_type_id+" mined visibility")
		await process_frame
		check(node.get_node("StaticBody2D/CollisionShape2D").disabled,node.resource_type_id+" mined collision")
		node._respawn()
		node.set_process(false)
		await process_frame
		check(node.visible and not node.collected_state and node.health==node.max_health,node.resource_type_id+" respawn")
		check(not node.get_node("StaticBody2D/CollisionShape2D").disabled,node.resource_type_id+" restored collision")
		check(node.content_sprite.texture==texture and node.position==at,node.resource_type_id+" respawn art/anchor")
	FileAccess.open(OUT+"runtime-qa.json",FileAccess.WRITE).store_string(JSON.stringify({
		"records":20,"production_instances":60,"terrain_backgrounds":3,"active_atlas_matches":active_matches,
		"hit_mined_respawn_checked":true,"imported_pixels":imports,"failures":failures,
		"fixture":"Arranged ResourceNode comparison; no random distribution or saved session."},"\t"))
	print("OATHWAKE_STONE_REVIEW failures=",failures)
	quit(0 if failures.is_empty() else 1)
