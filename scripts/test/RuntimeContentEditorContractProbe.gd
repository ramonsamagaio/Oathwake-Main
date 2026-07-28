extends Node

const EXPECTED_GROUPS := [
	"screen_shake",
	"combat_feedback",
	"world_occlusion",
	"world_wind",
	"ambient_particles",
	"selective_bloom",
	"color_grading",
	"local_light_mask",
	"layered_fog",
	"light_shafts",
	"water_surface",
	"micro_motion",
]
const GROUP_FIELD_PROBES := {
	"screen_shake": "normal_shake_strength",
	"ambient_particles": "world_particles_pollen",
	"selective_bloom": "post_bloom_intensity",
	"layered_fog": "env_fog_density",
	"light_shafts": "env_shafts_intensity",
}


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	call_deferred("_run_contract_probe")


func _run_contract_probe() -> void:
	await get_tree().process_frame
	var editor := get_parent()
	var launcher := get_tree().get_first_node_in_group("runtime_content_editor_launcher")
	# Scene-isolation tests intentionally have no gameplay launcher. Avoid racing
	# their own section navigation and probe only the real editor opened in-game.
	if editor == null or not is_instance_valid(editor) or launcher == null:
		queue_free()
		return

	_validate_group_navigation(editor)
	await _validate_window_recovery(launcher)
	queue_free()


func _validate_group_navigation(editor: Node) -> void:
	if not editor.has_method("get_post_effect_group_ids"):
		push_error("Runtime Content Editor contract probe: segmented Post Effects navigation is unavailable.")
		return
	var ids_value: Variant = editor.call("get_post_effect_group_ids")
	var ids: Array = []
	if ids_value is Array:
		ids = ids_value as Array
	if ids.size() != EXPECTED_GROUPS.size():
		push_error("Runtime Content Editor contract probe: expected %d Post Effects groups, found %d." % [EXPECTED_GROUPS.size(), ids.size()])
	for expected_id in EXPECTED_GROUPS:
		if expected_id not in ids:
			push_error("Runtime Content Editor contract probe: missing Post Effects group %s." % expected_id)

	var previous_group := str(editor.call("get_selected_post_effect_group")) if editor.has_method("get_selected_post_effect_group") else "screen_shake"
	for group_id in GROUP_FIELD_PROBES.keys():
		editor.call("_select_post_effect_group", str(group_id))
		var controls_value: Variant = editor.get("field_controls")
		var field_name := str(GROUP_FIELD_PROBES[group_id])
		if not controls_value is Dictionary or not (controls_value as Dictionary).has(field_name):
			push_error("Runtime Content Editor contract probe: %s did not build %s." % [group_id, field_name])
			continue
		var control_value: Variant = (controls_value as Dictionary).get(field_name)
		if control_value is CanvasItem and not (control_value as CanvasItem).is_visible_in_tree():
			push_error("Runtime Content Editor contract probe: %s control %s is hidden after selection." % [group_id, field_name])

	editor.call("_select_post_effect_group", previous_group if previous_group in EXPECTED_GROUPS else "screen_shake")

	var record_list := editor.get("record_list") as ItemList
	if record_list == null or record_list.item_count != EXPECTED_GROUPS.size():
		push_error("Runtime Content Editor contract probe: middle column does not expose all Post Effects groups.")


func _validate_window_recovery(launcher: Node) -> void:
	if not launcher.has_method("get_runtime_editor_window"):
		return
	var window := launcher.call("get_runtime_editor_window") as Window
	if window == null:
		push_error("Runtime Content Editor contract probe: launcher has no active embedded Window.")
		return

	window.position = Vector2i(-10000, -10000)
	if launcher.has_method("_clamp_editor_window_to_viewport"):
		launcher.call("_clamp_editor_window_to_viewport")
	await get_tree().process_frame
	if window.position.x < 0 or window.position.y < 0:
		push_error("Runtime Content Editor contract probe: off-screen Window position was not recovered.")
	if launcher.has_method("recenter_runtime_editor"):
		launcher.call("recenter_runtime_editor")
