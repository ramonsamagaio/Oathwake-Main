extends RefCounted
class_name AlabasterExternalSkinSource

const SourceImporter := preload("res://scripts/labs/alabaster/AlabasterSourceImporter.gd")

const PROFILE_FILES := {
	"male_dummy": ["dummy.json"],
	"male_temp": ["male-temp-01.json", "male-temp01.json"],
}
const PROFILE_FIGURES := {
	"male_dummy": "Male-Dummy",
	"male_temp": "Male-Temp-01",
}
const PROFILE_ATLASES := {
	"male_dummy": ["dummy.png"],
	"male_temp": ["male-temp01.png", "male-temp-01.png"],
}
const EXPECTED_ATLAS_SIZE := Vector2i(672, 120)
const CHROMA_RGB := Vector3i(255, 0, 195)
const MAX_JSON_SEARCH_DEPTH := 4

static var _bundle_cache: Dictionary = {}
static var _texture_cache: Dictionary = {}


static func load_skin_figure(profile_id: String) -> Dictionary:
	var bundle := _load_skin_bundle(profile_id)
	var figure_value: Variant = bundle.get("figure", {})
	return _runtime_figure_copy(figure_value as Dictionary) if figure_value is Dictionary else {}


static func load_skin_texture(profile_id: String) -> Texture2D:
	if _texture_cache.has(profile_id):
		var cached: Variant = _texture_cache[profile_id]
		if cached is Texture2D:
			return cached as Texture2D
		_texture_cache.erase(profile_id)

	var bundle := _load_skin_bundle(profile_id)
	if bundle.is_empty():
		return null
	var source_path := str(bundle.get("source_path", ""))
	var atlas_rel := str(bundle.get("atlas_rel", ""))
	var install_root := str(bundle.get("install_root", ""))
	var atlas_path := _resolve_atlas_path(profile_id, source_path, install_root, atlas_rel)
	if atlas_path.is_empty():
		print("ALABASTER_SKIN_EXTERNAL_ATLAS_MISSING profile=%s source=%s atlas_rel=%s install_root=%s" % [
			profile_id, source_path, atlas_rel, install_root,
		])
		return null

	var texture := _load_external_png(atlas_path)
	if texture != null:
		_texture_cache[profile_id] = texture
		print("ALABASTER_SKIN_EXTERNAL_ATLAS_OK profile=%s source=%s size=%dx%d" % [
			profile_id,
			atlas_path,
			texture.get_width(),
			texture.get_height(),
		])
	return texture


static func get_source_path(profile_id: String) -> String:
	return str(_load_skin_bundle(profile_id).get("source_path", ""))


static func clear_cache() -> void:
	_bundle_cache.clear()
	_texture_cache.clear()


static func _load_skin_bundle(profile_id: String) -> Dictionary:
	if _bundle_cache.has(profile_id):
		var cached: Variant = _bundle_cache[profile_id]
		if cached is Dictionary:
			return (cached as Dictionary).duplicate(false)

	var file_names_value: Variant = PROFILE_FILES.get(profile_id, [])
	if not file_names_value is Array:
		return {}
	var file_names := file_names_value as Array
	var figure_name := str(PROFILE_FIGURES.get(profile_id, ""))
	if figure_name.is_empty():
		return {}

	var visited_roots: Dictionary = {}
	for juno_path_value in SourceImporter.CANDIDATES:
		var juno_path := str(juno_path_value)
		var player_dir := juno_path.get_base_dir()
		var char_dir := player_dir.get_base_dir()
		if char_dir.is_empty() or visited_roots.has(char_dir):
			continue
		visited_roots[char_dir] = true
		print("ALABASTER_SKIN_EXTERNAL_SEARCH profile=%s char_root=%s" % [profile_id, char_dir])

		for file_name_value in file_names:
			var file_name := str(file_name_value)
			var source_candidates := [
				player_dir.path_join(file_name),
				char_dir.path_join(file_name),
			]
			for source_path_variant in source_candidates:
				var source_path := str(source_path_variant)
				var bundle := _load_bundle_from_path(source_path, figure_name)
				if not bundle.is_empty():
					return _cache_bundle(profile_id, figure_name, bundle)

			var recursive_match := _find_file_recursive(char_dir, file_name, MAX_JSON_SEARCH_DEPTH)
			if not recursive_match.is_empty():
				var recursive_bundle := _load_bundle_from_path(recursive_match, figure_name)
				if not recursive_bundle.is_empty():
					return _cache_bundle(profile_id, figure_name, recursive_bundle)

	print("ALABASTER_SKIN_EXTERNAL_SEARCH_FAILED profile=%s files=%s" % [profile_id, str(file_names)])
	return {}


static func _cache_bundle(profile_id: String, figure_name: String, bundle: Dictionary) -> Dictionary:
	var source_path := str(bundle.get("source_path", ""))
	var install_root := _find_install_root(source_path)
	bundle["install_root"] = install_root
	_bundle_cache[profile_id] = bundle.duplicate(false)
	var figure_value: Variant = bundle.get("figure", {})
	var figure := figure_value as Dictionary if figure_value is Dictionary else {}
	print("ALABASTER_SKIN_EXTERNAL_SOURCE_OK profile=%s figure=%s source=%s install_root=%s atlas_rel=%s nodes=%d anims=%d" % [
		profile_id,
		figure_name,
		source_path,
		install_root,
		str(bundle.get("atlas_rel", "")),
		(figure.get("nodes", {}) as Dictionary).size() if figure.get("nodes", {}) is Dictionary else 0,
		(figure.get("anims", {}) as Dictionary).size() if figure.get("anims", {}) is Dictionary else 0,
	])
	return bundle.duplicate(false)


static func _load_bundle_from_path(source_path: String, figure_name: String) -> Dictionary:
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		return {}
	var source_text := FileAccess.get_file_as_string(source_path)
	if source_text.is_empty():
		return {}
	var json := JSON.new()
	if json.parse(source_text) != OK:
		push_warning("AlabasterExternalSkinSource: invalid JSON source=%s line=%d error=%s" % [
			source_path,
			json.get_error_line(),
			json.get_error_message(),
		])
		return {}
	var parsed: Variant = json.data
	if not parsed is Dictionary:
		return {}
	var payload := parsed as Dictionary
	var figure := {}

	if payload.get("nodes", {}) is Dictionary and payload.get("anims", {}) is Dictionary:
		if not (payload.get("nodes", {}) as Dictionary).is_empty():
			figure = _runtime_figure_copy(payload)
	else:
		var figures_value: Variant = payload.get("figures", {})
		if figures_value is Dictionary:
			var figure_value: Variant = (figures_value as Dictionary).get(figure_name, {})
			if figure_value is Dictionary and not (figure_value as Dictionary).is_empty():
				figure = _runtime_figure_copy(figure_value as Dictionary)

	if figure.is_empty():
		return {}

	var atlas_rel := ""
	var sheets_value: Variant = payload.get("spriteSheets", {})
	if sheets_value is Dictionary:
		var sheets := sheets_value as Dictionary
		var male_sheet_value: Variant = sheets.get("Male-1", {})
		if male_sheet_value is Dictionary:
			atlas_rel = str((male_sheet_value as Dictionary).get("img", "")).strip_edges()

	return {
		"figure": figure,
		"source_path": source_path,
		"atlas_rel": atlas_rel,
	}


static func _find_file_recursive(root_dir: String, file_name: String, depth_left: int) -> String:
	if depth_left < 0 or root_dir.is_empty() or not DirAccess.dir_exists_absolute(root_dir):
		return ""
	var direct_path := root_dir.path_join(file_name)
	if FileAccess.file_exists(direct_path):
		return direct_path
	if depth_left == 0:
		return ""

	var dir := DirAccess.open(root_dir)
	if dir == null:
		return ""
	dir.list_dir_begin()
	while true:
		var entry := dir.get_next()
		if entry.is_empty():
			break
		if not dir.current_is_dir() or entry == "." or entry == "..":
			continue
		var found := _find_file_recursive(root_dir.path_join(entry), file_name, depth_left - 1)
		if not found.is_empty():
			dir.list_dir_end()
			return found
	dir.list_dir_end()
	return ""


static func _find_install_root(source_path: String) -> String:
	if source_path.is_empty():
		return ""
	var cursor := source_path.get_base_dir()
	for _i in range(10):
		if cursor.is_empty():
			break
		if cursor.get_file().to_lower() == "terra":
			return cursor.get_base_dir()
		var parent := cursor.get_base_dir()
		if parent == cursor:
			break
		cursor = parent
	return ""


static func _resolve_atlas_path(profile_id: String, source_path: String, install_root: String, atlas_rel: String) -> String:
	var candidates: Array[String] = []
	if not atlas_rel.is_empty():
		if not install_root.is_empty():
			candidates.append(install_root.path_join(atlas_rel))
		candidates.append(source_path.get_base_dir().path_join(atlas_rel))

	var atlas_names_value: Variant = PROFILE_ATLASES.get(profile_id, [])
	if atlas_names_value is Array:
		for atlas_name_value in atlas_names_value as Array:
			var atlas_name := str(atlas_name_value)
			if not install_root.is_empty():
				candidates.append(install_root.path_join("media/char").path_join(atlas_name))
				candidates.append(install_root.path_join("terra/media/char").path_join(atlas_name))
			candidates.append(source_path.get_base_dir().path_join(atlas_name))

	for candidate in candidates:
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


static func _load_external_png(path: String) -> Texture2D:
	var image := Image.new()
	var error := image.load(path)
	if error != OK or image.is_empty():
		push_warning("AlabasterExternalSkinSource: failed to load atlas %s error=%s" % [path, error])
		return null
	if image.get_width() != EXPECTED_ATLAS_SIZE.x or image.get_height() != EXPECTED_ATLAS_SIZE.y:
		push_warning("AlabasterExternalSkinSource: rejected atlas %s size=%dx%d expected=%dx%d" % [
			path,
			image.get_width(), image.get_height(),
			EXPECTED_ATLAS_SIZE.x, EXPECTED_ATLAS_SIZE.y,
		])
		return null
	_apply_chroma_key(image)
	return ImageTexture.create_from_image(image)


static func _apply_chroma_key(image: Image) -> void:
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var rgba := image.get_data()
	var i := 0
	while i + 3 < rgba.size():
		if int(rgba[i]) == CHROMA_RGB.x and int(rgba[i + 1]) == CHROMA_RGB.y and int(rgba[i + 2]) == CHROMA_RGB.z:
			rgba[i + 3] = 0
		i += 4
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, rgba)


static func _runtime_figure_copy(source: Dictionary) -> Dictionary:
	var result := source.duplicate(false)
	var nodes_value: Variant = source.get("nodes", {})
	result["nodes"] = (nodes_value as Dictionary).duplicate(false) if nodes_value is Dictionary else {}
	var anims_value: Variant = source.get("anims", {})
	result["anims"] = (anims_value as Dictionary).duplicate(false) if anims_value is Dictionary else {}
	return result
