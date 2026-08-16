extends RefCounted
class_name AlabasterRetargetDiagnostics

# Read-only source opener used by the Bone Studio RETARGET DEBUG tab.
# It deliberately does not depend on the editor's current target rig. The audit
# always evaluates the selected 3D source against the Juno target settings passed
# by Bone Studio.

const V8 := preload("res://scripts/labs/alabaster/AlabasterMixamoRetargetV8.gd")


static func audit_source(
	source_path: String,
	clip_name: String,
	sample_fps: float,
	loop: bool,
	translation_scale: float,
	settings: Dictionary
) -> Dictionary:
	var opened := _open_source(source_path)
	if not bool(opened.get("ok", false)):
		return _failure_report(
			source_path,
			clip_name,
			str(opened.get("resource_kind", "unknown")),
			str(opened.get("error", "Could not open animation source."))
		)

	var kind := str(opened.get("kind", "unknown"))
	var player := opened.get("player") as AnimationPlayer
	var skeleton := opened.get("skeleton") as Skeleton3D
	if player == null:
		_free_opened_source(opened)
		return _failure_report(source_path, clip_name, kind, "Source contains no AnimationPlayer.")

	if clip_name.is_empty():
		var clips := player.get_animation_list()
		if not clips.is_empty():
			clip_name = str(clips[0])

	if skeleton == null:
		var report := _limited_report(source_path, clip_name, kind, player)
		_free_opened_source(opened)
		return report

	var report := V8.build_audit(
		player,
		skeleton,
		clip_name,
		sample_fps,
		loop,
		translation_scale,
		settings
	)
	report["source_path"] = source_path
	report["resource_kind"] = kind
	report["has_skeleton"] = true
	report["source_profile"] = "mixamo" if _looks_mixamo(skeleton) else "unknown"
	_free_opened_source(opened)
	return report


static func list_source_hierarchy(source_path: String) -> Dictionary:
	var opened := _open_source(source_path)
	if not bool(opened.get("ok", false)):
		return opened
	var skeleton := opened.get("skeleton") as Skeleton3D
	if skeleton == null:
		_free_opened_source(opened)
		return {
			"ok": false,
			"error": "This source exposes no Skeleton3D hierarchy.",
			"resource_kind": str(opened.get("kind", "unknown")),
		}

	var rows: Array = []
	for bone_index in range(skeleton.get_bone_count()):
		var parent_index := skeleton.get_bone_parent(bone_index)
		rows.append({
			"index": bone_index,
			"name": str(skeleton.get_bone_name(bone_index)),
			"normalized": V8.normalize(str(skeleton.get_bone_name(bone_index))),
			"parent_index": parent_index,
			"parent": str(skeleton.get_bone_name(parent_index)) if parent_index >= 0 else "",
		})
	var result := {
		"ok": true,
		"resource_kind": str(opened.get("kind", "unknown")),
		"bone_count": skeleton.get_bone_count(),
		"rows": rows,
	}
	_free_opened_source(opened)
	return result


static func _open_source(source_path: String) -> Dictionary:
	if source_path.strip_edges().is_empty():
		return {"ok": false, "error": "No source animation file selected.", "resource_kind": "none"}

	if source_path.get_extension().to_lower() == "fbx":
		var raw_fbx := _open_runtime_fbx_scene(source_path)
		if bool(raw_fbx.get("ok", false)):
			return raw_fbx

	if not ResourceLoader.exists(source_path):
		return {
			"ok": false,
			"error": "Godot has not imported this source yet: %s" % source_path,
			"resource_kind": "missing",
		}

	var resource: Resource = load(source_path)
	if resource == null:
		return {
			"ok": false,
			"error": "Could not load imported animation source: %s" % source_path,
			"resource_kind": "load_failed",
		}

	if resource is PackedScene:
		var root := (resource as PackedScene).instantiate()
		if root == null:
			return {
				"ok": false,
				"error": "Could not instantiate imported scene: %s" % source_path,
				"resource_kind": "packed_scene",
			}
		var player := _find_animation_player(root)
		var skeleton := _find_skeleton3d(root)
		if player == null:
			root.free()
			return {
				"ok": false,
				"error": "Imported scene contains no AnimationPlayer.",
				"resource_kind": "packed_scene",
			}
		return {
			"ok": true,
			"kind": "packed_scene",
			"resource_kind": "packed_scene",
			"root": root,
			"player": player,
			"skeleton": skeleton,
		}

	if resource is AnimationLibrary:
		var library := resource as AnimationLibrary
		var temp_root := Node.new()
		var player := AnimationPlayer.new()
		temp_root.add_child(player)
		player.add_animation_library("", library)
		return {
			"ok": true,
			"kind": "animation_library",
			"resource_kind": "animation_library",
			"root": temp_root,
			"player": player,
			"skeleton": null,
		}

	return {
		"ok": false,
		"error": "Unsupported imported resource type '%s'." % resource.get_class(),
		"resource_kind": resource.get_class(),
	}


static func _open_runtime_fbx_scene(source_path: String) -> Dictionary:
	if not ClassDB.class_exists("FBXDocument") or not ClassDB.class_exists("FBXState"):
		return {
			"ok": false,
			"error": "This Godot build does not expose FBXDocument/FBXState.",
			"resource_kind": "fbx",
		}
	if not FileAccess.file_exists(source_path):
		return {
			"ok": false,
			"error": "Raw FBX file is missing: %s" % source_path,
			"resource_kind": "fbx",
		}

	var document := FBXDocument.new()
	var state := FBXState.new()
	state.allow_geometry_helper_nodes = true
	var filesystem_path := ProjectSettings.globalize_path(source_path)
	var error := document.append_from_file(filesystem_path, state)
	if error != OK:
		return {
			"ok": false,
			"error": "FBXDocument could not parse %s error=%s" % [source_path, error_string(error)],
			"resource_kind": "fbx_runtime_scene",
		}

	var root := document.generate_scene(state, 30.0, false, false)
	if root == null:
		return {
			"ok": false,
			"error": "FBXDocument parsed the file but could not generate a scene.",
			"resource_kind": "fbx_runtime_scene",
		}

	var player := _find_animation_player(root)
	var skeleton := _find_skeleton3d(root)
	if player == null:
		root.free()
		return {
			"ok": false,
			"error": "Raw FBX scene contains no AnimationPlayer.",
			"resource_kind": "fbx_runtime_scene",
		}

	return {
		"ok": true,
		"kind": "fbx_runtime_scene",
		"resource_kind": "fbx_runtime_scene",
		"root": root,
		"player": player,
		"skeleton": skeleton,
	}


static func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child_value in node.get_children():
		var child := child_value as Node
		if child == null:
			continue
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


static func _find_skeleton3d(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child_value in node.get_children():
		var child := child_value as Node
		if child == null:
			continue
		var found := _find_skeleton3d(child)
		if found != null:
			return found
	return null


static func _looks_mixamo(skeleton: Skeleton3D) -> bool:
	var names := {}
	for bone_index in range(skeleton.get_bone_count()):
		names[V8.normalize(str(skeleton.get_bone_name(bone_index)))] = true
	for required in ["hips", "spine", "leftarm", "rightarm", "leftupleg", "rightupleg"]:
		if not names.has(required):
			return false
	return true


static func _limited_report(
	source_path: String,
	clip_name: String,
	kind: String,
	player: AnimationPlayer
) -> Dictionary:
	var clip_exists := not clip_name.is_empty() and player.has_animation(clip_name)
	var track_count := 0
	var length := 0.0
	if clip_exists:
		var animation := player.get_animation(clip_name)
		if animation != null:
			track_count = animation.get_track_count()
			length = animation.length
	return {
		"ok": false,
		"status": "FAIL",
		"profile": V8.PROFILE_NAME,
		"source_path": source_path,
		"resource_kind": kind,
		"has_skeleton": false,
		"clip": clip_name,
		"clip_length_seconds": length,
		"track_count": track_count,
		"issues": [{
			"severity": "FAIL",
			"code": "NO_SKELETON3D",
			"message": "The source exposes animation tracks but no Skeleton3D. V8 cannot verify REST pose, hierarchy, axes or anatomical segment motion. Reimport/use the raw FBX/GLB scene for authoritative retargeting.",
		}],
		"frame_diagnostics": [],
	}


static func _failure_report(source_path: String, clip_name: String, kind: String, error: String) -> Dictionary:
	return {
		"ok": false,
		"status": "FAIL",
		"profile": V8.PROFILE_NAME,
		"source_path": source_path,
		"resource_kind": kind,
		"has_skeleton": false,
		"clip": clip_name,
		"issues": [{
			"severity": "FAIL",
			"code": "SOURCE_OPEN_FAILED",
			"message": error,
		}],
		"frame_diagnostics": [],
	}


static func _free_opened_source(opened: Dictionary) -> void:
	var root := opened.get("root") as Node
	if root != null and is_instance_valid(root):
		root.free()
