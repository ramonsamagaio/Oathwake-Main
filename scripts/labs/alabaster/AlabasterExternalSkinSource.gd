extends RefCounted
class_name AlabasterExternalSkinSource

# Canonical repository-local loader for the Alabaster humanoid test figures.
# Nothing in this class searches the user's Steam installation or any absolute
# filesystem location. JSON lives under data/, authored PNG atlases under assets/.

const PROFILE_JSON_PATHS := {
	"male_dummy": "res://data/labs/alabaster/characters/dummy.json",
	"male_temp": "res://data/labs/alabaster/characters/male-temp-01.json",
}
const PROFILE_FIGURES := {
	"male_dummy": "Male-Dummy",
	"male_temp": "Male-Temp-01",
}
const PROFILE_ATLAS_PATHS := {
	"male_dummy": "res://assets/sprites/characters/alabaster/dummy.png",
	"male_temp": "res://assets/sprites/characters/alabaster/male-temp01.png",
}
const REQUIRED_NODES := [
	"root", "top", "head", "bottom",
	"hipL", "legL", "footL",
	"hipR", "legR", "footR",
	"shoulderL", "armL", "handL",
	"shoulderR", "armR", "handR",
]
const REQUIRED_ANIMATIONS := {
	"male_dummy": ["walk", "run", "punch", "laying"],
	"male_temp": ["walk", "run", "punch", "laying", "damage"],
}
const EXPECTED_ATLAS_SIZE := Vector2i(672, 120)
const CHROMA_RGB := Vector3i(255, 0, 195)

static var _bundle_cache: Dictionary = {}
static var _texture_cache: Dictionary = {}


static func load_skin_figure(profile_id: String) -> Dictionary:
	var bundle := _load_repo_bundle(profile_id)
	var figure_value: Variant = bundle.get("figure", {})
	return _runtime_figure_copy(figure_value as Dictionary) if figure_value is Dictionary else {}


static func load_skin_texture(profile_id: String) -> Texture2D:
	if _texture_cache.has(profile_id):
		var cached: Variant = _texture_cache[profile_id]
		if cached is Texture2D:
			return cached as Texture2D
		_texture_cache.erase(profile_id)

	var atlas_path := get_repo_atlas_path(profile_id)
	if atlas_path.is_empty():
		push_error("AlabasterExternalSkinSource: unknown atlas profile %s" % profile_id)
		return null
	if not ResourceLoader.exists(atlas_path) and not FileAccess.file_exists(atlas_path):
		push_error("AlabasterExternalSkinSource: canonical repo atlas is missing: %s" % atlas_path)
		return null

	var image: Image = null
	if ResourceLoader.exists(atlas_path):
		var resource := load(atlas_path)
		if resource is Texture2D:
			image = (resource as Texture2D).get_image()
	if image == null or image.is_empty():
		image = Image.new()
		var image_error := image.load(atlas_path)
		if image_error != OK or image.is_empty():
			push_error("AlabasterExternalSkinSource: failed to load canonical repo atlas %s error=%s" % [atlas_path, image_error])
			return null

	if image.get_width() != EXPECTED_ATLAS_SIZE.x or image.get_height() != EXPECTED_ATLAS_SIZE.y:
		push_error("AlabasterExternalSkinSource: rejected atlas %s size=%dx%d expected=%dx%d" % [
			atlas_path,
			image.get_width(), image.get_height(),
			EXPECTED_ATLAS_SIZE.x, EXPECTED_ATLAS_SIZE.y,
		])
		return null

	var keyed_pixels := _apply_chroma_key(image)
	var texture := ImageTexture.create_from_image(image)
	if texture == null:
		push_error("AlabasterExternalSkinSource: ImageTexture creation failed for %s" % atlas_path)
		return null
	_texture_cache[profile_id] = texture
	print("ALABASTER_REPO_ATLAS_OK profile=%s path=%s size=%dx%d chroma_pixels=%d" % [
		profile_id,
		atlas_path,
		texture.get_width(), texture.get_height(),
		keyed_pixels,
	])
	return texture


static func get_source_path(profile_id: String) -> String:
	return str(PROFILE_JSON_PATHS.get(profile_id, ""))


static func get_source_kind(profile_id: String) -> String:
	return "REPO_SOURCE_JSON" if PROFILE_JSON_PATHS.has(profile_id) else ""


static func get_repo_atlas_path(profile_id: String) -> String:
	return str(PROFILE_ATLAS_PATHS.get(profile_id, ""))


static func clear_cache() -> void:
	_bundle_cache.clear()
	_texture_cache.clear()


static func _load_repo_bundle(profile_id: String) -> Dictionary:
	if _bundle_cache.has(profile_id):
		var cached: Variant = _bundle_cache[profile_id]
		if cached is Dictionary:
			return (cached as Dictionary).duplicate(false)
		_bundle_cache.erase(profile_id)

	var json_path := get_source_path(profile_id)
	var figure_name := str(PROFILE_FIGURES.get(profile_id, ""))
	var atlas_path := get_repo_atlas_path(profile_id)
	if json_path.is_empty() or figure_name.is_empty() or atlas_path.is_empty():
		push_error("AlabasterExternalSkinSource: unknown skin profile %s" % profile_id)
		return {}
	if not FileAccess.file_exists(json_path):
		push_error("AlabasterExternalSkinSource: canonical repo figure JSON is missing: %s" % json_path)
		return {}

	var source_text := FileAccess.get_file_as_string(json_path)
	if source_text.is_empty():
		push_error("AlabasterExternalSkinSource: canonical figure JSON is empty: %s" % json_path)
		return {}
	var json := JSON.new()
	if json.parse(source_text) != OK:
		push_error("AlabasterExternalSkinSource: invalid JSON source=%s line=%d error=%s" % [
			json_path,
			json.get_error_line(),
			json.get_error_message(),
		])
		return {}
	var parsed: Variant = json.data
	if not parsed is Dictionary:
		push_error("AlabasterExternalSkinSource: JSON root is not a dictionary: %s" % json_path)
		return {}
	var payload := parsed as Dictionary

	var figures_value: Variant = payload.get("figures", {})
	if not figures_value is Dictionary:
		push_error("AlabasterExternalSkinSource: %s has no figures dictionary" % json_path)
		return {}
	var figure_value: Variant = (figures_value as Dictionary).get(figure_name, {})
	if not figure_value is Dictionary or (figure_value as Dictionary).is_empty():
		push_error("AlabasterExternalSkinSource: expected figure %s not found in %s; available=%s" % [
			figure_name,
			json_path,
			str((figures_value as Dictionary).keys()),
		])
		return {}
	var figure := _runtime_figure_copy(figure_value as Dictionary)
	if not _validate_humanoid_figure(profile_id, figure_name, figure, json_path):
		return {}
	if not _validate_sprite_sheet_binding(payload, atlas_path, json_path):
		return {}

	var bundle := {
		"figure": figure,
		"source_path": json_path,
		"atlas_path": atlas_path,
		"source_kind": "REPO_SOURCE_JSON",
	}
	_bundle_cache[profile_id] = bundle.duplicate(false)
	var anims := figure.get("anims", {}) as Dictionary
	var animation_names := anims.keys()
	animation_names.sort()
	print("ALABASTER_REPO_FIGURE_OK profile=%s figure=%s path=%s nodes=%d anims=%d animations=%s" % [
		profile_id,
		figure_name,
		json_path,
		(figure.get("nodes", {}) as Dictionary).size(),
		anims.size(),
		str(animation_names),
	])
	return bundle.duplicate(false)


static func _validate_humanoid_figure(profile_id: String, figure_name: String, figure: Dictionary, json_path: String) -> bool:
	var nodes_value: Variant = figure.get("nodes", {})
	var anims_value: Variant = figure.get("anims", {})
	if not nodes_value is Dictionary or (nodes_value as Dictionary).is_empty():
		push_error("AlabasterExternalSkinSource: %s has no humanoid nodes in %s" % [figure_name, json_path])
		return false
	if not anims_value is Dictionary or (anims_value as Dictionary).is_empty():
		push_error("AlabasterExternalSkinSource: %s has no animations in %s" % [figure_name, json_path])
		return false
	var nodes := nodes_value as Dictionary
	var anims := anims_value as Dictionary
	for node_name in REQUIRED_NODES:
		if not nodes.has(node_name):
			push_error("AlabasterExternalSkinSource: %s is not the expected full humanoid rig; missing node=%s source=%s" % [
				figure_name, node_name, json_path,
			])
			return false
	var required_anims_value: Variant = REQUIRED_ANIMATIONS.get(profile_id, [])
	if required_anims_value is Array:
		for animation_name_variant in required_anims_value as Array:
			var animation_name := str(animation_name_variant)
			if not anims.has(animation_name):
				push_error("AlabasterExternalSkinSource: %s is missing expected test-character animation=%s source=%s" % [
					figure_name, animation_name, json_path,
				])
				return false
	if str(figure.get("rootFacing", "")) != "FACE_16":
		push_error("AlabasterExternalSkinSource: %s does not declare FACE_16 rootFacing in %s" % [figure_name, json_path])
		return false
	return true


static func _validate_sprite_sheet_binding(payload: Dictionary, atlas_path: String, json_path: String) -> bool:
	var sheets_value: Variant = payload.get("spriteSheets", {})
	if not sheets_value is Dictionary:
		push_error("AlabasterExternalSkinSource: %s has no spriteSheets dictionary" % json_path)
		return false
	var male_sheet_value: Variant = (sheets_value as Dictionary).get("Male-1", {})
	if not male_sheet_value is Dictionary:
		push_error("AlabasterExternalSkinSource: %s has no Male-1 sprite sheet declaration" % json_path)
		return false
	var male_sheet := male_sheet_value as Dictionary
	var declared_img := str(male_sheet.get("img", "")).strip_edges()
	if declared_img.is_empty():
		push_error("AlabasterExternalSkinSource: %s Male-1 has no img path" % json_path)
		return false
	if declared_img.get_file().to_lower() != atlas_path.get_file().to_lower():
		push_error("AlabasterExternalSkinSource: JSON/PNG pair mismatch source=%s declared=%s repo_atlas=%s" % [
			json_path, declared_img, atlas_path,
		])
		return false
	var range_value: Variant = male_sheet.get("range", [])
	if range_value is Array and (range_value as Array).size() >= 4:
		var atlas_range := range_value as Array
		if int(atlas_range[2]) != EXPECTED_ATLAS_SIZE.x or int(atlas_range[3]) != EXPECTED_ATLAS_SIZE.y:
			push_error("AlabasterExternalSkinSource: declared Male-1 range does not match %dx%d source=%s range=%s" % [
				EXPECTED_ATLAS_SIZE.x, EXPECTED_ATLAS_SIZE.y, json_path, str(atlas_range),
			])
			return false
	return true


static func _apply_chroma_key(image: Image) -> int:
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	var rgba := image.get_data()
	var keyed_pixels := 0
	var i := 0
	while i + 3 < rgba.size():
		if int(rgba[i]) == CHROMA_RGB.x and int(rgba[i + 1]) == CHROMA_RGB.y and int(rgba[i + 2]) == CHROMA_RGB.z:
			rgba[i + 3] = 0
			keyed_pixels += 1
		i += 4
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, rgba)
	return keyed_pixels


static func _runtime_figure_copy(source: Dictionary) -> Dictionary:
	var result := source.duplicate(false)
	var nodes_value: Variant = source.get("nodes", {})
	result["nodes"] = (nodes_value as Dictionary).duplicate(false) if nodes_value is Dictionary else {}
	var anims_value: Variant = source.get("anims", {})
	result["anims"] = (anims_value as Dictionary).duplicate(false) if anims_value is Dictionary else {}
	return result
