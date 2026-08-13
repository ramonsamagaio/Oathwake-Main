extends "res://scripts/labs/alabaster/AlabasterBoneStudioLiveTuningPanel.gd"

# Alabaster's frameCnt is the exclusive end of the source interval for looping
# clips. The runtime wraps as soon as source_frame >= frameCnt. The first Live
# Tuning UI exposed frameCnt itself as an editable frame, which created a phantom
# terminal frame (for example frame 16 of a 16-frame run) that the real runtime
# never displays during locomotion. Keep the editor on the same frame domain as
# gameplay: animStart .. frameCnt - 1.


func _load_selected_animation() -> void:
	super._load_selected_animation()
	_clamp_live_frame_range()


func _seek_frame(frame: int) -> void:
	var safe_frame := frame
	if frame_spin != null:
		safe_frame = clampi(frame, int(frame_spin.min_value), int(frame_spin.max_value))
		suppress_frame_spin_signal(true)
		frame_spin.value = safe_frame
		suppress_frame_spin_signal(false)
	super._seek_frame(safe_frame)


func _clamp_live_frame_range() -> void:
	if frame_spin == null:
		return
	var rig_value: Variant = _rig()
	if rig_value == null or not rig_value is Object:
		return
	var rig_object := rig_value as Object
	if not rig_object.has_method("get_animation_data"):
		return
	var preview_value: Variant = rig_object.call("get_animation_data", PREVIEW_ANIMATION)
	if not preview_value is Dictionary:
		return
	var preview := preview_value as Dictionary
	var start_frame := int(preview.get("animStart", 0))
	var frame_count := maxi(int(preview.get("frameCnt", 1)), start_frame + 1)
	var last_valid_frame := maxi(frame_count - 1, start_frame)
	suppress_frame_spin_signal(true)
	frame_spin.min_value = start_frame
	frame_spin.max_value = last_valid_frame
	if int(frame_spin.value) > last_valid_frame:
		frame_spin.value = last_valid_frame
	elif int(frame_spin.value) < start_frame:
		frame_spin.value = start_frame
	suppress_frame_spin_signal(false)
	_update_frame_label(int(frame_spin.value))


func suppress_frame_spin_signal(enabled: bool) -> void:
	_suppress_ui = enabled
