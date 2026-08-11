extends RefCounted
class_name AlabasterBoneAnimationSourceAdapter

const LegacyImporter := preload("res://scripts/labs/alabaster/AlabasterSmartBoneAnimationImporter.gd")

static func inspect_scene(source_path: String) -> Dictionary:
	var opened := _open_source(source_path)
	if not bool(opened.get("ok", false)):
		return opened
	var clips: Array[String] = []
	var bones: Array[String] = []
	var kind := str(opened.get("kind", ""))
	if kind == "packed_scene":
		var player := opened.get("player") as AnimationPlayer
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
	_free_opened_source(opened)
	if clips.is_empty():
		return {"ok": false, "error": "Godot loaded %s, but it contains no animation clips. Check the FBX Import dock and Reimport with animations enabled." % kind, "resource_kind": kind}
	return {"ok": true, "clips": clips, "bones": bones, "resource_kind": kind, "retarget_profile": LegacyImporter.detect_source_profile(bones)}

static func import_scene_clip(source_path: String, clip_name: String, sample_fps := 60.0, loop := true, translation_scale := 0.0, custom_retarget: Dictionary = {}, settings: Dictionary = {}) -> Dictionary:
	var opened := _open_source(source_path)
	if not bool(opened.get("ok", false)):
		push_warning(str(opened.get("error", "Could not open animation source.")))
		return {}
	var animation: Animation = null
	var kind := str(opened.get("kind", ""))
	if kind == "packed_scene":
		var player := opened.get("player") as AnimationPlayer
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
	var result := LegacyImporter.convert_animation(animation, sample_fps, loop, translation_scale, custom_retarget, settings)
	_free_opened_source(opened)
	return result

static func make_auto_retarget(source_bones: Array[String]) -> Dictionary:
	return LegacyImporter.make_auto_retarget(source_bones)

static func _open_source(source_path: String) -> Dictionary:
	if source_path.strip_edges().is_empty():
		return {"ok": false, "error": "No source animation file selected."}
	if not ResourceLoader.exists(source_path):
		return {"ok": false, "error": "Godot has not imported this source yet: %s. Wait for import to finish or use Reimport in the FileSystem dock." % source_path}
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
			return {"ok": false, "error": "Godot imported the file as a scene, but no AnimationPlayer was found. Check Advanced Import Settings and verify the animation is enabled.", "resource_kind": "packed_scene"}
		return {"ok": true, "kind": "packed_scene", "root": root, "player": player}
	if resource is AnimationLibrary:
		return {"ok": true, "kind": "animation_library", "library": resource as AnimationLibrary}
	return {"ok": false, "error": "Unsupported imported resource type '%s'. Bone Studio accepts a Godot PackedScene or AnimationLibrary generated from FBX/GLB/GLTF/TSCN." % resource.get_class(), "resource_kind": resource.get_class()}

static func _append_unique_bones(target: Array[String], incoming: Array[String]) -> void:
	for bone_name in incoming:
		if not target.has(bone_name):
			target.append(bone_name)

static func _free_opened_source(opened: Dictionary) -> void:
	var root := opened.get("root") as Node
	if root != null and is_instance_valid(root):
		root.free()
