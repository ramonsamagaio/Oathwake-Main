extends Node2D
## F6: eight directions. Keys 1..6 switch the animation. Captures reuse eight rigs.
const Character := preload("res://scripts/labs/alabaster/MooncloakRig.gd")
const OUTPUT := "res://docs/characters/mooncloak/"
const CLIPS := ["idle","walk","run","atkSwordN1","guard","dead"]
var canvas:SubViewport
var rigs:Array[Node2D]=[]
var labels:Array[Label]=[]

func _ready()->void:
	get_window().size=Vector2i(1280,220)
	canvas=SubViewport.new()
	canvas.size=Vector2i(640,80)
	canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	canvas.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(canvas)
	var bg:=ColorRect.new()
	bg.size=Vector2(640,80)
	bg.color=Color("484941")
	bg.z_index=-4096
	canvas.add_child(bg)
	var view:=TextureRect.new()
	view.texture=canvas.get_texture()
	view.size=Vector2(1280,160)
	view.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(view)
	var help:=Label.new()
	help.text="MOONCLOAK    1 idle   2 walk   3 run   4 attack   5 guard   6 dead"
	help.position=Vector2(20,178)
	add_child(help)
	for column in range(8):
		var rig:Node2D=Character.new()
		canvas.add_child(rig)
		rig.position=Vector2(column*80+40,68)
		rig.set("facing_degrees",float(column*45))
		rig.call("set_animation","idle")
		rigs.append(rig)
		var label:=Label.new()
		label.position=Vector2(column*80+5,2)
		label.add_theme_font_size_override("font_size",8)
		canvas.add_child(label)
		labels.append(label)
	set_clip("idle")
	if "--capture" in OS.get_cmdline_user_args() or "--motion" in OS.get_cmdline_user_args():
		for clip in CLIPS:
			set_clip(clip)
			for rig in rigs:
				rig.set_process(false)
				rig.set("animation_time",0.16)
				rig.call("_apply_pose")
			await capture("pose-"+clip+".png")
		set_clip("idle")
		for rig in rigs:
			rig.set("animation_time",0.16)
			rig.call("_apply_pose")
		await capture("godot-native.png")
		if "--motion" in OS.get_cmdline_user_args():
			set_clip("walk")
			for frame in range(16):
				for rig in rigs:
					rig.set("animation_time",float(frame)/32.0)
					rig.call("_apply_pose")
				await capture("motion-%02d.png"%frame)
		print("MOONCLOAK_CAPTURE complete")
		get_tree().quit()

func capture(filename:String)->void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	canvas.get_texture().get_image().save_png(OUTPUT+filename)

func set_clip(clip:String)->void:
	for i in range(rigs.size()):
		rigs[i].call("set_animation",clip)
		labels[i].text=clip+" / "+["N","NE","E","SE","S","SW","W","NW"][i]

func _unhandled_key_input(event:InputEvent)->void:
	if event is InputEventKey and event.pressed and not event.echo:
		var index:=int(event.physical_keycode)-KEY_1
		if index>=0 and index<CLIPS.size():set_clip(CLIPS[index])
