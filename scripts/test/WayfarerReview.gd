extends Node2D
## F6: live 8-direction comparison. -- --capture: save native rendered board.
const Original := preload("res://scripts/labs/alabaster/AlabasterJunoBaseRig.gd")
const Character := preload("res://scripts/labs/alabaster/WayfarerRig.gd")
const OUTPUT := "res://docs/characters/wayfarer/"
var canvas: SubViewport
var rigs: Array[Node2D] = []

func _ready() -> void:
	get_window().size = Vector2i(1280, 960)
	canvas = SubViewport.new()
	canvas.size = Vector2i(640, 480)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(canvas)
	var bg := ColorRect.new()
	bg.size = Vector2(640,480)
	bg.color = Color("25313b")
	canvas.add_child(bg)
	var view := TextureRect.new()
	view.texture = canvas.get_texture()
	view.size = Vector2(1280,960)
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(view)
	var clips := ["idle", "idle", "walk", "run", "atkSwordN1", "guard", "dead"]
	var directions := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	for row in range(clips.size()):
		for column in range(8):
			var rig: Node2D = Original.new() if row == 0 else Character.new()
			canvas.add_child(rig)
			rig.position = Vector2(column * 80 + 40, row * 64 + 61)
			rig.set("facing_degrees", float(column * 45))
			rig.call("set_animation", clips[row])
			rigs.append(rig)
			var label := Label.new()
			label.position = Vector2(column * 80 + 3, row * 64 + 1)
			label.add_theme_font_size_override("font_size", 8)
			label.text = ("JUNO" if row == 0 else str(clips[row])) + " / " + directions[column]
			canvas.add_child(label)
	if "--capture" in OS.get_cmdline_user_args() or "--motion" in OS.get_cmdline_user_args():
		for rig in rigs:
			rig.set_process(false)
			rig.set("animation_time", 0.16)
			rig.call("_apply_pose")
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var error := canvas.get_texture().get_image().save_png(OUTPUT + "godot-native.png")
		print("WAYFARER_CAPTURE result=", error)
		if "--motion" in OS.get_cmdline_user_args():
			for frame in range(16):
				for rig in rigs:
					rig.set("animation_time", float(frame) / 16.0)
					rig.call("_apply_pose")
				await RenderingServer.frame_post_draw
				canvas.get_texture().get_image().save_png(OUTPUT + "motion-%02d.png" % frame)
		get_tree().quit(error)
