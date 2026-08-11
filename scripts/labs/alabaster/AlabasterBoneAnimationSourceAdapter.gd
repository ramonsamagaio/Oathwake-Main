extends RefCounted
class_name AlabasterBoneAnimationSourceAdapter

const LegacyImporter := preload("res://scripts/labs/alabaster/AlabasterSmartBoneAnimationImporter.gd")
const SemanticConverter := preload("res://scripts/labs/alabaster/AlabasterMixamoSemanticConverter.gd")


static func inspect_scene(source_path: String) -> Dictionary:
	var opened := _open_source(source_path)
	if not bool(opened.get("ok", false)):
		return opened
	var clips: Array[String] = []
	var bones: Array[String] = []
	var kind := str(opened.get("kind", ""))
	var has_skeleton := false

	if _is_scene_kind(kind):
		var player := opened.get("player") as AnimationPlayer
		var skeleton := opened.get("skeleton") as Skeleton3D
		has_skeleton = skeleton != null
		if player == null:
			_free_opened_source(opened)
			return {"ok": false, "error": "Imported scene contains no AnimationPlayer."}
		for clip_name_value in player.get_animation_list():
			var clip_name := str(clip_name_value)
			var animation := player.get_animation(clip_name)
			if animation == null:
				continue
			clips.append(clip_name)
			_append_unique_bones(bones, LegacyImporter.get_source_bones(animation))
	elif kind == "animation_library":
		var library := opened.get("library") as AnimationLibrary
		if library == null:
			return {"ok": false, "error": "Imported AnimationLibrary could not be read."}
		for clip_name_value in library.get_animation_list():
			var clip_name := str(clip_name_value)
			var animation := library.get_animation(clip_name)
			if animation == null:
				continue
			clips.append(clip_name)
			_append_unique_bones(bones, LegacyImporter.get_source_bones(animation))

	clips.sort()
	bones.sort()
	var profile := LegacyImporter.detect_source_profile(bones)
	var retarget_mode := "generic_track"
	if profile == "mixamo":
		retarget_mode = "mixamo_rest_delta_v5" if has_skeleton else "mixamo_track_fallback"
	_free_opened_source(opened)

	if clips.is_empty():
		return {
			"ok": false,
			"error": "Godot loaded %s, but it contains no animation clips. Check the FBX Import dock and Reimport with animations enabled." % kind,
			"resource_kind": kind,
		}
	return {
		"ok": true,
		"clips": clips,
		"bones": bones,
		"resource_kind": kind,
		"retarget_profile": profile,
		"retarget_mode": retarget_mode,
		"has_skeleton": has_skeleton,
	}


static func import_scene_clip(source_path: String, clip_name: String, sample_fps := 60.0, loop := true, translation_scale := 0.0, custom_retarget: Dictionary = {}, settings: Dictionary = {}) -> Dictionary:
	var opened := _open_source(source_path)
	if not bool(opened.get("ok", false)):
		push_warning(str(opened.get("error", "Could not open animation source.")))
		return {}

	var animation: Animation = null
	var player: AnimationPlayer = null
	var skeleton: Skeleton3D = null
	var kind := str(opened.get("kind", ""))
	if _is_scene_kind(kind):
		player = opened.get("player") as AnimationPlayer
		skeleton = opened.get("skeleton") as Skeleton3D
		if player != null and player.has_animation(clip_name):
			animation = player.get_animation(clip_name)
	elif kind == "animation_library":
		var library := opened.get("library") as AnimationLibrary
		if library != null and library.has_animation(clip_name):
			animation = library.get_animation(clip_name)

	if animation == null:
		_free_opened_source(opened)
		push_warning("Animation '%s' not found in %s (%s)." % [clip_name, source_path, kind])
		return {}

	var source_bones := LegacyImporter.get_source_bones(animation)
	var profile := LegacyImporter.detect_source_profile(source_bones)
	var result := {}

	if profile == "mixamo" and _is_scene_kind(kind) and skeleton != null and _mapping_matches_auto(source_bones, custom_retarget):
		# Authoritative Mixamo path. V5 samples the Animation tracks directly into
		# Skeleton3D bone pose properties, then transfers REST->POSE anatomical
		# motion deltas onto Default. It does not depend on detached AnimationPlayer
		# processing and does not copy the source T-pose into the target rest pose.
		result = SemanticConverter.convert_scene(player, skeleton, clip_name, sample_fps, loop, translation_scale, settings)
		if result.is_empty():
			push_warning("Mixamo Rest-Delta V5 conversion failed. Refusing to silently fall back to the known-distorting raw local-axis path.")
	else:
		result = LegacyImporter.convert_animation(animation, sample_fps, loop, translation_scale, custom_retarget, settings)
		if profile == "mixamo" and skeleton == null:
			push_warning("Mixamo source has no Skeleton3D; using track-only fallback. A raw FBX/GLB scene is recommended for rest-delta retargeting.")

	_free_opened_source(opened)
	return result


static func make_auto_retarget(source_bones: Array[String]) -> Dictionary:
	return LegacyImporter.make_auto_retarget(source_bones)


static func _mapping_matches_auto(source_bones: Array[String], mapping: Dictionary) -> bool:
	if mapping.is_empty():
		return true
	var expected := make_auto_retarget(source_bones)
	for source_bone in source_bones:
		if str(mapping.get(source_bone, "")) != str(expected.get(source_bone, "")):
			return false
	return true


static func _open_source(source_path: String) -> Dictionary:
	if source_path.strip_edges().is_empty():
		return {"ok": false, "error": "No source animation file selected."}

	# Mixamo FBX files are often imported by Godot as an AnimationLibrary. That
	# exposes curves but hides Skeleton3D Bone Rest. Reconstruct a transient scene
	# directly from the raw FBX so V5 can use the actual rest hierarchy.
	if source_path.get_extension().to_lower() == "fbx":
		var raw_fbx := _open_runtime_fbx_scene(source_path)
		if bool(raw_fbx.get("ok", false)):
			return raw_fbx

	if not ResourceLoader.exists(source_path):
		return {
			"ok": false,
			"error": "Godot has not imported this source yet: %s. Wait for import to finish or use Reimport in the FileSystem dock." % source_path,
		}
	var resource: Resource = load(source_path)
	if resource == null:
		return {"ok": false, "error": "Could not load imported animation source: %s" % source_path}

	if resource is PackedScene:
		var root := (resource as PackedScene).instantiate()
		if root == null:
			return {"ok": false, "error": "Could not instantiate imported scene: %s" % source_path}
		var player := LegacyImporter.find_animation_player(root)
		if player == null:
			root.free()
			return {
				"ok": false,
				"error": "Godot imported the file as a scene, but no AnimationPlayer was found. Check Advanced Import Settings and verify the animation is enabled.",
				"resource_kind": "packed_scene",
			}
		var skeleton := _find_skeleton3d(root)
		return {"ok": true, "kind": "packed_scene", "root": root, "player": player, "skeleton": skeleton}

	if resource is AnimationLibrary:
		return {"ok": true, "kind": "animation_library", "library": resource as AnimationLibrary}

	return {
		"ok": false,
		"error": "Unsupported imported resource type '%s'. Bone Studio accepts a Godot PackedScene or AnimationLibrary generated from FBX/GLB/GLTF/TSCN." % resource.get_class(),
		"resource_kind": resource.get_class(),
	}


static func _open_runtime_fbx_scene(source_path: String) -> Dictionary:
	if not ClassDB.class_exists("FBXDocument") or not ClassDB.class_exists("FBXState"):
		return {"ok": false, "error": "This Godot build does not expose FBXDocument/FBXState."}
	if not FileAccess.file_exists(source_path):
		return {"ok": false, "error": "Raw FBX file is missing: %s" % source_path}

	var document := FBXDocument.new()
	var state := FBXState.new()
	state.allow_geometry_helper_nodes = true
	var filesystem_path := ProjectSettings.globalize_path(source_path)
	var error := document.append_from_file(filesystem_path, state)
	if error != OK:
		return {"ok": false, "error": "FBXDocument could not parse %s error=%s" % [source_path, error_string(error)]}

	var root := document.generate_scene(state, 30.0, false, false)
	if root == null:
		return {"ok": false, "error": "FBXDocument parsed the file but could not generate a scene: %s" % source_path}
	var player := LegacyImporter.find_animation_player(root)
	var skeleton := _find_skeleton3d(root)
	if player == null or skeleton == null:
		root.free()
		return {"ok": false, "error": "Raw FBX scene is missing AnimationPlayer or Skeleton3D: %s" % source_path}

	print("ALABASTER_MIXAMO_FBX_SCENE_OK path=%s clips=%d bones=%d" % [source_path, player.get_animation_list().size(), skeleton.get_bone_count()])
	return {
		"ok": true,
		"kind": "fbx_runtime_scene",
		"root": root,
		"player": player,
		"skeleton": skeleton,
	}


static func _is_scene_kind(kind: String) -> bool:
	return kind == "packed_scene" or kind == "fbx_runtime_scene"


static func _find_skeleton3d(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton3d(child)
		if found != null:
			return found
	return null


static func _append_unique_bones(target: Array[String], incoming: Array[String]) -> void:
	for bone_name in incoming:
		if not target.has(bone_name):
			target.append(bone_name)


static func _free_opened_source(opened: Dictionary) -> void:
	var root := opened.get("root") as Node
	if root != null and is_instance_valid(root):
		root.free()
