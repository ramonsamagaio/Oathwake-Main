extends SceneTree

const SourceAdapter := preload("res://scripts/labs/alabaster/AlabasterBoneAnimationSourceAdapter.gd")
const SOURCE_PATH := "res://assets/anims/UAL1_Standard.glb"
const OUTPUT_DIR := "res://assets/anims/UAL1_Standard"
const MANIFEST_PATH := OUTPUT_DIR + "/manifest.json"


func _initialize() -> void:
	var opened: Dictionary = SourceAdapter.open_preview_source(SOURCE_PATH)
	if not bool(opened.get("ok", false)):
		push_error("ALABASTER_UAL1_UNPACK_FAILURE: %s" % str(opened.get("error", "unknown source error")))
		quit(1)
		return

	var player := opened.get("player") as AnimationPlayer
	if player == null:
		SourceAdapter.close_preview_source(opened)
		push_error("ALABASTER_UAL1_UNPACK_FAILURE: source has no AnimationPlayer")
		quit(1)
		return

	var output_abs := ProjectSettings.globalize_path(OUTPUT_DIR)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(output_abs)
	if mkdir_error != OK:
		SourceAdapter.close_preview_source(opened)
		push_error("ALABASTER_UAL1_UNPACK_FAILURE: could not create %s error=%s" % [OUTPUT_DIR, error_string(mkdir_error)])
		quit(1)
		return

	_clear_previous_generated_files(output_abs)

	var manifest_clips: Array[Dictionary] = []
	var used_stems: Dictionary = {}
	var written := 0
	for clip_value in player.get_animation_list():
		var clip_name := str(clip_value)
		var animation := player.get_animation(clip_name)
		if animation == null:
			continue

		var stem := _unique_stem(_safe_file_stem(clip_name), used_stems)
		var output_path := "%s/%s.tres" % [OUTPUT_DIR, stem]
		var library := AnimationLibrary.new()
		var copy := animation.duplicate(true) as Animation
		if copy == null:
			SourceAdapter.close_preview_source(opened)
			push_error("ALABASTER_UAL1_UNPACK_FAILURE: could not duplicate clip %s" % clip_name)
			quit(1)
			return
		var add_error := library.add_animation(clip_name, copy)
		if add_error != OK:
			SourceAdapter.close_preview_source(opened)
			push_error("ALABASTER_UAL1_UNPACK_FAILURE: could not add clip %s error=%s" % [clip_name, error_string(add_error)])
			quit(1)
			return
		var save_error := ResourceSaver.save(library, output_path)
		if save_error != OK:
			SourceAdapter.close_preview_source(opened)
			push_error("ALABASTER_UAL1_UNPACK_FAILURE: could not save %s error=%s" % [output_path, error_string(save_error)])
			quit(1)
			return

		manifest_clips.append({
			"name": clip_name,
			"file": output_path,
			"length": animation.length,
			"tracks": animation.get_track_count(),
			"loop_mode": animation.loop_mode,
		})
		written += 1
		print("ALABASTER_UAL1_UNPACK_CLIP name=%s file=%s length=%.4f tracks=%d" % [clip_name, output_path, animation.length, animation.get_track_count()])

	SourceAdapter.close_preview_source(opened)

	manifest_clips.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("name", "")) < str(b.get("name", "")))
	var manifest := {
		"source": SOURCE_PATH,
		"format": "Godot AnimationLibrary resource per source clip",
		"clip_count": written,
		"clips": manifest_clips,
	}
	var manifest_file := FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	if manifest_file == null:
		push_error("ALABASTER_UAL1_UNPACK_FAILURE: could not write manifest %s" % MANIFEST_PATH)
		quit(1)
		return
	manifest_file.store_string(JSON.stringify(manifest, "\t"))
	manifest_file.close()

	print("ALABASTER_UAL1_UNPACK_OK clips=%d output=%s" % [written, OUTPUT_DIR])
	quit(0)


func _clear_previous_generated_files(output_abs: String) -> void:
	var dir := DirAccess.open(output_abs)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if not dir.current_is_dir() and (name.get_extension().to_lower() == "tres" or name == "manifest.json"):
			dir.remove(name)
		name = dir.get_next()
	dir.list_dir_end()


func _safe_file_stem(value: String) -> String:
	var result := value.strip_edges()
	for invalid in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		result = result.replace(invalid, "_")
	result = result.replace(" ", "_")
	while result.contains("__"):
		result = result.replace("__", "_")
	result = result.trim_prefix("_").trim_suffix("_")
	if result.is_empty():
		return "clip"
	return result


func _unique_stem(base: String, used: Dictionary) -> String:
	var stem := base
	var suffix := 2
	while used.has(stem.to_lower()):
		stem = "%s_%d" % [base, suffix]
		suffix += 1
	used[stem.to_lower()] = true
	return stem
