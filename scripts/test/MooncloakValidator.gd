extends SceneTree
const Original := preload("res://scripts/labs/alabaster/WayfarerRig.gd")
const Character := preload("res://scripts/labs/alabaster/MooncloakRig.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var original := Original.new()
	var character := Character.new()
	root.add_child(original)
	root.add_child(character)
	original.set_process(false)
	character.set_process(false)
	var poses := 0
	var regions := 0
	var failures: Array[String] = []
	var snapshots: Array = []
	for clip: String in original._anims:
		var duration := float(original._anims[clip].get("frameCnt",60)) / 60.0
		for direction in range(16):
			for sample in range(4):
				for rig in [original,character]:
					rig.current_animation = clip
					rig.facing_degrees = direction * 22.5
					rig.animation_time = duration * sample / 4.0
					rig._apply_pose()
				poses += 1
				for index in range(original._sprite_records.size()):
					var a: Sprite2D = original._sprite_records[index]["sprite"]
					var b: Sprite2D = character._sprite_records[index]["sprite"]
					if a.visible != b.visible or a.region_rect != b.region_rect or a.offset != b.offset or a.transform != b.transform or a.flip_h != b.flip_h or a.z_index != b.z_index:
						failures.append("Pose mismatch: %s %d %d %s" % [clip,direction,sample,a.name])
					if b.visible:
						regions += 1
						if not Rect2(Vector2.ZERO,Vector2(144,284)).encloses(b.region_rect):
							failures.append("Out of bounds: " + str(b.region_rect))
						if clip == "idle" and sample == 0:
							snapshots.append({"direction":direction*22.5,"node":str(b.name),"region":str(b.region_rect),"offset":str(b.offset),"position":str(b.position),"scale":str(b.scale),"rotation":b.rotation,"flip_h":b.flip_h,"z":b.z_index})
	var report := {"poses":poses,"visible_regions":regions,"animations":original._anims.keys(),"failures":failures,"idle_runtime_samples":snapshots,"missing_mapping_warnings":character._compact_missing_region_warnings.keys()}
	var file := FileAccess.open("res://docs/characters/mooncloak/rig-validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("MOONCLOAK_VALIDATION poses=%d regions=%d failures=%d missing=%d" % [poses,regions,failures.size(),character._compact_missing_region_warnings.size()])
	original.queue_free()
	character.queue_free()
	quit(0 if failures.is_empty() and character._compact_missing_region_warnings.is_empty() else 1)
