extends SceneTree

const LAB_PATH := "res://scenes/labs/alabaster/AlabasterMechanicLab.tscn"
const EXPECTED_PROFILES := ["golem_stone", "golem_jade"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(LAB_PATH) as PackedScene
	if packed == null:
		_fail("Mechanic Lab scene failed to load.")
		return
	var lab := packed.instantiate()
	if lab == null:
		_fail("Mechanic Lab scene failed to instantiate.")
		return
	root.add_child(lab)
	for _frame in range(5):
		await process_frame

	var buttons_value: Variant = lab.get("_profile_buttons")
	if not buttons_value is Dictionary:
		_fail("Mechanic Lab profile switcher was not created.")
		return
	var buttons := buttons_value as Dictionary

	for profile_id in EXPECTED_PROFILES:
		if not buttons.has(profile_id):
			_fail("Mechanic Lab has no button for %s." % profile_id)
			return
		lab.call("_replace_rig", profile_id, true)
		for _frame in range(3):
			await process_frame
		var rig_value: Variant = lab.get("rig")
		if not rig_value is Object:
			_fail("Mechanic Lab exposed no rig for %s." % profile_id)
			return
		var rig := rig_value as Object
		if str(rig.get("profile_id")) != profile_id:
			_fail("Mechanic Lab selected %s but monster rig reports %s." % [profile_id, str(rig.get("profile_id"))])
			return
		if not bool(rig.get("monster_ready")):
			_fail("Monster rig did not become ready for %s." % profile_id)
			return
		if not rig.has_method("get_profile_label"):
			_fail("Monster rig lost its profile API for %s." % profile_id)
			return
		var label := str(rig.call("get_profile_label"))
		if label.is_empty():
			_fail("Monster rig has an empty label for %s." % profile_id)
			return
		var anims_value: Variant = rig.call("get_animation_names") if rig.has_method("get_animation_names") else []
		if not anims_value is Array or (anims_value as Array).is_empty():
			_fail("Monster rig exposed no animations for %s." % profile_id)
			return
		print("ALABASTER_MECHANIC_GOLEM_PROFILE_OK id=%s label=%s animations=%d" % [profile_id, label, (anims_value as Array).size()])

	print("ALABASTER_MECHANIC_GOLEMS_OK profiles=%d" % EXPECTED_PROFILES.size())
	lab.queue_free()
	await process_frame
	quit(0)


func _fail(message: String) -> void:
	printerr("ALABASTER_MECHANIC_GOLEMS_FAILURE: %s" % message)
	quit(1)
