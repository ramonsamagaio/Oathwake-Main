extends "res://scripts/labs/alabaster/WayfarerRig.gd"
## Wayfarer-compatible body with isolated directional cloak and carried bow/quiver.
const MOONCLOAK_ATLAS := "res://assets/sprites/characters/MOONCLOAK.png"
const MOONCLOAK_GEAR := "res://assets/sprites/characters/MOONCLOAK_GEAR.png"
var _moon_cape:Sprite2D
var _moon_pack:Sprite2D

func _load_png_texture(path:String)->Texture2D:
	if path==COMPACT_ATLAS_PATH:
		return super._load_png_texture(MOONCLOAK_ATLAS)
	return super._load_png_texture(path)

func _ready()->void:
	super._ready()
	var gear:=_load_png_texture(MOONCLOAK_GEAR)
	for label in ["MooncloakCape","MooncloakBowQuiver"]:
		var sprite:=Sprite2D.new()
		sprite.name=label
		sprite.texture=gear
		sprite.region_enabled=true
		sprite.centered=false
		sprite.z_as_relative=false
		sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(sprite)
		if label=="MooncloakCape":_moon_cape=sprite
		else:_moon_pack=sprite
	_update_mooncloak_gear()

func _apply_pose()->void:
	super._apply_pose()
	_update_mooncloak_gear()

func _update_mooncloak_gear()->void:
	if _moon_cape==null or _moon_pack==null:return
	var body:Sprite2D
	for record in _sprite_records:
		var sprite:Sprite2D=record.get("sprite")
		if sprite!=null and sprite.name=="top_gfx_0":body=sprite;break
	if body==null:return
	var direction:=posmod(int(floor((fposmod(facing_degrees,360.0)+22.5)/45.0)),8)
	var rear:=direction in [0,1,7]
	var lowest_z:=body.z_index
	for record in _sprite_records:
		var piece:Sprite2D=record.get("sprite")
		if piece!=null and piece.visible:lowest_z=mini(lowest_z,piece.z_index)
	var step:=1 if _embedded_world_mode else 16
	var rear_z:=lowest_z-step
	if _embedded_world_mode:rear_z=clampi(rear_z,-32,32)
	for sprite in [_moon_cape,_moon_pack]:
		sprite.transform=body.transform
		sprite.visible=body.visible
		sprite.modulate=body.modulate
		sprite.self_modulate=body.self_modulate
		sprite.z_as_relative=body.z_as_relative
	_moon_cape.region_rect=Rect2(direction*32,0,32,32)
	_moon_cape.offset=Vector2(-16,-2)
	_moon_cape.z_index=body.z_index+1 if rear else rear_z
	_moon_pack.region_rect=Rect2(direction*32,32,32,32)
	_moon_pack.offset=Vector2(-16,-14)
	_moon_pack.z_index=body.z_index+2 if rear else rear_z+1

func set_sprite_opacity(value:float)->void:
	super.set_sprite_opacity(value)
	_update_mooncloak_gear()

func get_runtime_summary()->Dictionary:
	var result:=super.get_runtime_summary()
	result["profile"]="mooncloak"
	result["profile_label"]="Mooncloak"
	result["core_atlas_path"]=MOONCLOAK_ATLAS
	result["compact_atlas_path"]=MOONCLOAK_ATLAS
	result["accessory_atlas_path"]=MOONCLOAK_GEAR
	return result
