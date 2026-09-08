extends SceneTree
const Controller:=preload("res://scripts/player/AlabasterPlayerVisualController.gd")
var failures:Array[String]=[]
func _initialize()->void:call_deferred("_run")
func check(ok:bool,why:String)->void:
	if not ok:failures.append(why)
func _run()->void:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/characters.json"))
	var before:Dictionary=data["wayfarer_alabaster"].duplicate(true)
	before["display_name"]="Mooncloak"
	before["rig_profile_id"]="mooncloak"
	check(data["mooncloak_alabaster"]==before,"character clone stats differ")
	var owner:=Node2D.new()
	owner.z_index=120
	root.add_child(owner)
	var controller:=Controller.new()
	check(controller.configure(owner,data["mooncloak_alabaster"],Vector2.ZERO,1.0),"controller configuration")
	var rig:Node2D=controller.rig
	check(rig.get_script().resource_path.ends_with("MooncloakRig.gd"),"gameplay rig selection")
	rig.set_process(false)
	var samples:=0
	for clip in ["idle","walk","run","atkSwordN1","dead"]:
		for direction in range(16):
			rig.set("current_animation",clip)
			rig.set("facing_degrees",direction*22.5)
			rig.set("animation_time",0.16)
			rig.call("_apply_pose")
			for field in ["_moon_cape","_moon_pack"]:
				var gear:Sprite2D=rig.get(field)
				check(gear.z_as_relative,field+" not grouped under player depth")
				check(gear.z_index>=-32 and gear.z_index<=32,field+" exceeds embedded depth band")
				check(Rect2(0,0,256,64).encloses(gear.region_rect),field+" region bounds")
			samples+=1
	rig.call("set_sprite_opacity",0.4)
	check(is_equal_approx(rig.get("_moon_cape").self_modulate.a,0.4),"cape opacity")
	check(is_equal_approx(rig.get("_moon_pack").self_modulate.a,0.4),"pack opacity")
	controller.dispose()
	FileAccess.open("res://docs/characters/mooncloak/gameplay-qa.json",FileAccess.WRITE).store_string(JSON.stringify({"samples":samples,"failures":failures,"character_clone_preserved":true},"\t"))
	print("MOONCLOAK_GAMEPLAY ",failures)
	quit(0 if failures.is_empty() else 1)
