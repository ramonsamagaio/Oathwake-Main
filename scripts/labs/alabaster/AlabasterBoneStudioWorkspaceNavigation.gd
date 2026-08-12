extends "res://scripts/labs/alabaster/AlabasterBoneStudioWorkspace.gd"

# Final interaction layer for the Bone Studio workspace.
# - Target/profile switches preserve the exact selected animation, source frame,
#   loop/play state and selected bone whenever the destination rig supports them.
# - The sprite-sheet inspector behaves like a real 2D viewport: wheel zooms and
#   middle-mouse drag pans, while source pixels remain NEAREST-filtered.

const ATLAS_ZOOM_MIN := 0.50
const ATLAS_ZOOM_MAX := 12.0
const ATLAS_ZOOM_FACTOR := 1.20

var _atlas_scroll: ScrollContainer = null
var _atlas_zoom_host: Control = null
var _atlas_zoom := 1.0
var _atlas_pan_active := false


func setup(owner: Control) -> void:
	super.setup(owner)
	_install_atlas_navigation()


# Switching the visual target used to call _select_default_idle() unconditionally.
# Keep the animation as editor state instead: the character changes, not the clip.
func _on_target_pressed(profile_id: String) -> void:
	if _suppress_ui or profile_id == target_profile:
		return

	var previous_record := current_record.duplicate(true)
	var previous_frame := _capture_current_source_frame()
	var was_playing := _workspace_is_playing()
	var previous_part := selected_part

	target_profile = profile_id
	_update_target_buttons()
	if not _replace_host_rig(profile_id):
		_set_status("Could not initialize target figure %s." % str(PROFILE_LABEL.get(profile_id, profile_id)), true)
		return

	_rebuild_animation_records()
	_rebuild_parts_list()

	var restored := _restore_previous_animation_selection(previous_record)
	if not restored:
		# Safety fallback only. In normal use every global-bank record remains
		# available across target figures, so this path should be rare.
		_select_default_idle()
	else:
		_restore_source_frame(previous_frame)

	if not previous_part.is_empty():
		selected_part = previous_part
		_select_part_in_list(previous_part)
		var rig_value: Variant = _rig()
		if rig_value is Object and (rig_value as Object).has_method("set_selected_sprite_part"):
			(rig_value as Object).call("set_selected_sprite_part", previous_part)
		if _workspace_editor != null:
			_workspace_editor.call("set_selected_bone", previous_part)

	_set_playback_state(was_playing)
	_refresh_live_inspection(true)
	_refresh_workspace_editor_rig()


func _capture_current_source_frame() -> int:
	var rig_value: Variant = _rig()
	if rig_value is Object:
		var rig_object := rig_value as Object
		if rig_object.has_method("get_current_source_frame"):
			return roundi(float(rig_object.call("get_current_source_frame")))
		if rig_object.has_method("get_current_tuning_frame"):
			return int(rig_object.call("get_current_tuning_frame"))
	if frame_spin != null:
		return int(frame_spin.value)
	return 0


func _restore_previous_animation_selection(previous_record: Dictionary) -> bool:
	if previous_record.is_empty() or animation_option == null:
		return false

	var previous_name := str(previous_record.get("name", ""))
	var previous_source_profile := str(previous_record.get("source_profile", ""))
	var previous_source_kind := str(previous_record.get("source", "builtin"))
	var name_fallback := -1

	for index in range(animation_option.item_count):
		var meta_value: Variant = animation_option.get_item_metadata(index)
		if not meta_value is Dictionary:
			continue
		var record := meta_value as Dictionary
		if str(record.get("name", "")) != previous_name:
			continue
		if name_fallback < 0:
			name_fallback = index
		if (
			str(record.get("source_profile", "")) == previous_source_profile
			and str(record.get("source", "builtin")) == previous_source_kind
		):
			animation_option.select(index)
			_on_animation_selected(index)
			return true

	# If a filter/library refresh changed only the source variant, preserve the
	# animation name rather than dropping the user back to idle.
	if name_fallback >= 0:
		animation_option.select(name_fallback)
		_on_animation_selected(name_fallback)
		return true
	return false


func _restore_source_frame(frame: int) -> void:
	if frame_spin == null:
		_seek_frame(maxi(frame, 0))
		return
	var safe_frame := clampi(frame, int(frame_spin.min_value), int(frame_spin.max_value))
	_suppress_ui = true
	frame_spin.value = safe_frame
	_suppress_ui = false
	_seek_frame(safe_frame)
	_sync_adjustment_controls()


func _install_atlas_navigation() -> void:
	if _atlas_canvas == null:
		return
	var parent := _atlas_canvas.get_parent()
	if not parent is ScrollContainer:
		return
	_atlas_scroll = parent as ScrollContainer

	_atlas_zoom_host = Control.new()
	_atlas_zoom_host.name = "SpriteSheetZoomHost"
	_atlas_zoom_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_atlas_zoom_host.clip_contents = false

	_atlas_scroll.remove_child(_atlas_canvas)
	_atlas_scroll.add_child(_atlas_zoom_host)
	_atlas_zoom_host.add_child(_atlas_canvas)
	_atlas_canvas.position = Vector2.ZERO
	_atlas_canvas.pivot_offset = Vector2.ZERO
	_atlas_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_atlas_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_atlas_scroll.tooltip_text = "Sprite sheet: mouse wheel = zoom · middle mouse drag = pan"
	_atlas_scroll.gui_input.connect(_on_atlas_gui_input)
	_apply_atlas_zoom_layout()


# Parent inspection refreshes the atlas whenever the active direction/cell changes.
# Reapply the zoom wrapper afterward so profile swaps with different atlas sizes also
# keep correct scroll extents.
func _refresh_atlas_inspector(force: bool) -> void:
	super._refresh_atlas_inspector(force)
	_apply_atlas_zoom_layout()


func _apply_atlas_zoom_layout() -> void:
	if _atlas_zoom_host == null or _atlas_canvas == null:
		return
	var native_size := _atlas_native_size()
	if native_size.x <= 0.0 or native_size.y <= 0.0:
		return
	_atlas_canvas.position = Vector2.ZERO
	_atlas_canvas.size = native_size
	_atlas_canvas.scale = Vector2.ONE * _atlas_zoom
	_atlas_zoom_host.custom_minimum_size = native_size * _atlas_zoom
	_atlas_zoom_host.size = native_size * _atlas_zoom


func _atlas_native_size() -> Vector2:
	if _atlas_texture_rect != null and _atlas_texture_rect.texture != null:
		var texture := _atlas_texture_rect.texture
		return Vector2(float(texture.get_width()), float(texture.get_height()))
	if _atlas_canvas != null:
		return _atlas_canvas.size
	return Vector2.ZERO


func _on_atlas_gui_input(event: InputEvent) -> void:
	if _atlas_scroll == null:
		return

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_zoom_atlas_at(button.position, ATLAS_ZOOM_FACTOR)
			_atlas_scroll.accept_event()
			return
		if button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_zoom_atlas_at(button.position, 1.0 / ATLAS_ZOOM_FACTOR)
			_atlas_scroll.accept_event()
			return
		if button.button_index == MOUSE_BUTTON_MIDDLE:
			_atlas_pan_active = button.pressed
			_atlas_scroll.accept_event()
			return

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _atlas_pan_active and not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			_atlas_pan_active = false
		if not _atlas_pan_active:
			return
		_atlas_scroll.scroll_horizontal = roundi(float(_atlas_scroll.scroll_horizontal) - motion.relative.x)
		_atlas_scroll.scroll_vertical = roundi(float(_atlas_scroll.scroll_vertical) - motion.relative.y)
		_atlas_scroll.accept_event()


func _zoom_atlas_at(mouse_position: Vector2, factor: float) -> void:
	var old_zoom := _atlas_zoom
	var next_zoom := clampf(old_zoom * factor, ATLAS_ZOOM_MIN, ATLAS_ZOOM_MAX)
	if is_equal_approx(old_zoom, next_zoom):
		return

	# Preserve the source pixel underneath the cursor while changing zoom.
	var content_before := Vector2(
		float(_atlas_scroll.scroll_horizontal) + mouse_position.x,
		float(_atlas_scroll.scroll_vertical) + mouse_position.y
	) / maxf(old_zoom, 0.001)
	_atlas_zoom = next_zoom
	_apply_atlas_zoom_layout()
	call_deferred("_restore_atlas_zoom_anchor", content_before, mouse_position)


func _restore_atlas_zoom_anchor(source_pixel: Vector2, mouse_position: Vector2) -> void:
	if _atlas_scroll == null:
		return
	var desired := source_pixel * _atlas_zoom - mouse_position
	_atlas_scroll.scroll_horizontal = roundi(maxf(desired.x, 0.0))
	_atlas_scroll.scroll_vertical = roundi(maxf(desired.y, 0.0))
