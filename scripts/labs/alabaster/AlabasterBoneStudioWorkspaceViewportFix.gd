extends "res://scripts/labs/alabaster/AlabasterBoneStudioWorkspaceNavigation.gd"

# Final viewport-geometry shim for the Live Tuning workspace.
#
# SubViewportContainer.stretch=true is the stable render path for Bone Studio,
# especially inside Godot's embedded Game View. Workspace.gd historically also
# wrote SubViewport.size manually, which means two owners fought over the same
# render texture. This layer leaves size ownership to the container while still
# keeping the interactive overlay and preview origin synchronized.


func _sync_workspace_viewport_geometry() -> void:
	if _workspace_holder == null or _workspace_viewport == null:
		return
	var holder_size: Vector2 = _workspace_holder.size
	if not _workspace_holder.stretch:
		_workspace_viewport.size = Vector2i(
			maxi(roundi(holder_size.x), 1),
			maxi(roundi(holder_size.y), 1)
		)
	if _workspace_editor != null:
		_workspace_editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sync_workspace_editor_origin()


func _sync_workspace_editor_origin() -> void:
	if _workspace_holder == null or host == null:
		return
	var preview_world_value: Variant = host.get("preview_world")
	if not preview_world_value is Node2D:
		return
	var preview_world := preview_world_value as Node2D
	var holder_size: Vector2 = _workspace_holder.size
	if holder_size.x < 4.0 or holder_size.y < 4.0:
		holder_size = Vector2(_workspace_viewport.size) if _workspace_viewport != null else Vector2(620.0, 620.0)
	preview_world.position = Vector2(
		holder_size.x * 0.5,
		holder_size.y * 0.5 + WORKSPACE_PREVIEW_Y_OFFSET
	) + _workspace_pan
	if _workspace_editor != null:
		_workspace_editor.call("set_preview_origin", preview_world.position)
