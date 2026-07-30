class_name ShadowProfileLibrary
extends RefCounted

const DEFAULT_PROFILE_ID := "humanoid"
const PROFILE_IDS := [
	"humanoid",
	"small_creature",
	"trunk_wide",
	"rock_compact",
	"building_wide",
	"thin_segment",
]

const DEFAULT_PROFILES := {
	"humanoid": {
		"display_name": "Humanoid",
		"width_ratio": 0.52,
		"length_ratio": 0.92,
		"minimum_width": 14.0,
		"minimum_length": 22.0,
		"root_width_ratio": 0.72,
		"tip_width_ratio": 0.34,
		"root_overlap_multiplier": 0.90,
		"edge_softness": 0.12,
		"tip_fade": 0.16,
		"roundness": 1.35,
	},
	"small_creature": {
		"display_name": "Small Creature",
		"width_ratio": 0.82,
		"length_ratio": 0.48,
		"minimum_width": 14.0,
		"minimum_length": 10.0,
		"root_width_ratio": 0.92,
		"tip_width_ratio": 0.62,
		"root_overlap_multiplier": 0.65,
		"edge_softness": 0.14,
		"tip_fade": 0.18,
		"roundness": 1.15,
	},
	"trunk_wide": {
		"display_name": "Tree / Trunk",
		"width_ratio": 0.70,
		"length_ratio": 0.84,
		"minimum_width": 22.0,
		"minimum_length": 28.0,
		"root_width_ratio": 0.90,
		"tip_width_ratio": 0.46,
		"root_overlap_multiplier": 1.10,
		"edge_softness": 0.13,
		"tip_fade": 0.14,
		"roundness": 1.20,
	},
	"rock_compact": {
		"display_name": "Rock / Compact Prop",
		"width_ratio": 0.90,
		"length_ratio": 0.38,
		"minimum_width": 16.0,
		"minimum_length": 10.0,
		"root_width_ratio": 0.96,
		"tip_width_ratio": 0.68,
		"root_overlap_multiplier": 0.55,
		"edge_softness": 0.16,
		"tip_fade": 0.20,
		"roundness": 1.05,
	},
	"building_wide": {
		"display_name": "Building / Wide Structure",
		"width_ratio": 0.92,
		"length_ratio": 0.58,
		"minimum_width": 44.0,
		"minimum_length": 30.0,
		"root_width_ratio": 0.96,
		"tip_width_ratio": 0.72,
		"root_overlap_multiplier": 1.25,
		"edge_softness": 0.11,
		"tip_fade": 0.12,
		"roundness": 1.10,
	},
	"thin_segment": {
		"display_name": "Thin Post / Fence Segment",
		"width_ratio": 0.42,
		"length_ratio": 0.88,
		"minimum_width": 8.0,
		"minimum_length": 18.0,
		"root_width_ratio": 0.78,
		"tip_width_ratio": 0.26,
		"root_overlap_multiplier": 0.75,
		"edge_softness": 0.10,
		"tip_fade": 0.14,
		"roundness": 1.50,
	},
}

static var _mask_texture_cache: Dictionary = {}


static func get_profile_ids() -> Array[String]:
	var result: Array[String] = []
	for profile_id in PROFILE_IDS:
		result.append(str(profile_id))
	return result


static func get_profile_display_name(profile_id: String) -> String:
	var profile := DEFAULT_PROFILES.get(profile_id, {}) as Dictionary
	return str(profile.get("display_name", profile_id.capitalize()))


static func is_profile_system_enabled(global_shadow_config: Dictionary) -> bool:
	var system := _dictionary(global_shadow_config.get("profile_system", {}))
	return bool(system.get("enabled", true))


static func resolve_profile(
	target: Node2D,
	source: CanvasItem,
	caster_config: Dictionary,
	global_shadow_config: Dictionary,
	visual_size: Vector2
) -> Dictionary:
	var system := _dictionary(global_shadow_config.get("profile_system", {}))
	var requested_id := str(caster_config.get("shadow_profile_id", caster_config.get("profile_id", ""))).strip_edges()
	if requested_id.is_empty() and target != null and target.has_meta("shadow_profile_id"):
		requested_id = str(target.get_meta("shadow_profile_id", "")).strip_edges()
	if requested_id.is_empty() and source != null and source.has_meta("shadow_profile_id"):
		requested_id = str(source.get_meta("shadow_profile_id", "")).strip_edges()
	if requested_id == "auto":
		requested_id = ""
	if requested_id.is_empty() and bool(system.get("auto_classify", true)):
		requested_id = classify_profile_id(target, source, visual_size)
	if not DEFAULT_PROFILES.has(requested_id):
		requested_id = str(system.get("default_profile", DEFAULT_PROFILE_ID))
	if not DEFAULT_PROFILES.has(requested_id):
		requested_id = DEFAULT_PROFILE_ID

	var resolved := (DEFAULT_PROFILES[requested_id] as Dictionary).duplicate(true)
	var profile_overrides := _dictionary(system.get("profiles", {}))
	var override_value: Variant = profile_overrides.get(requested_id, {})
	if override_value is Dictionary:
		resolved.merge((override_value as Dictionary).duplicate(true), true)
	var caster_override: Variant = caster_config.get("shadow_profile", {})
	if caster_override is Dictionary:
		resolved.merge((caster_override as Dictionary).duplicate(true), true)
	resolved["id"] = requested_id
	return resolved


static func classify_profile_id(target: Node2D, source: CanvasItem, visual_size: Vector2) -> String:
	if target != null:
		if target.is_in_group("player") or target.is_in_group("npc"):
			return "humanoid"
		if target.is_in_group("building") or target.is_in_group("world_building"):
			return "building_wide"
		if target.is_in_group("resource_tree") or target.is_in_group("tree_resource"):
			return "trunk_wide"

	var searchable := ""
	if target != null:
		searchable += " %s" % str(target.name)
	if source != null:
		searchable += " %s" % str(source.name)
	searchable = searchable.to_lower()

	if _contains_any(searchable, ["slime", "gosma", "blob", "bat", "morcego", "pet", "rat", "spider"]):
		return "small_creature"
	if _contains_any(searchable, ["tree", "trunk", "stump", "toco", "pine", "pinheiro", "log", "crown"]):
		return "trunk_wide"
	if _contains_any(searchable, ["rock", "stone", "ore", "mineral", "crystal", "pedra", "boulder"]):
		return "rock_compact"
	if _contains_any(searchable, ["house", "building", "roof", "wall", "tower", "workshop", "forge", "casa", "cabana"]):
		return "building_wide"
	if _contains_any(searchable, ["fence", "post", "pole", "sign", "board", "pillar", "cerca", "placa"]):
		return "thin_segment"
	if _contains_any(searchable, ["player", "skeleton", "enemy", "monster", "npc", "human", "character", "esqueleto"]):
		return "humanoid"

	var safe_height := maxf(visual_size.y, 1.0)
	var aspect := visual_size.x / safe_height
	if source is AnimatedSprite2D:
		return "small_creature" if visual_size.y <= 36.0 or aspect >= 1.10 else "humanoid"
	if visual_size.x >= 120.0 and visual_size.y >= 72.0:
		return "building_wide"
	if aspect <= 0.38:
		return "thin_segment"
	if visual_size.y >= 72.0 and aspect <= 1.15:
		return "trunk_wide"
	if visual_size.y <= 48.0:
		return "rock_compact"
	return DEFAULT_PROFILE_ID


static func get_mask_texture(profile: Dictionary) -> Texture2D:
	var profile_id := str(profile.get("id", DEFAULT_PROFILE_ID))
	var cache_key := "%s:%s" % [profile_id, JSON.stringify(profile)]
	var cached: Variant = _mask_texture_cache.get(cache_key)
	if cached is Texture2D and is_instance_valid(cached):
		return cached as Texture2D

	var resolution := Vector2i(64, 128)
	var image := Image.create(resolution.x, resolution.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var root_width_ratio := clampf(float(profile.get("root_width_ratio", 0.8)), 0.05, 1.0)
	var tip_width_ratio := clampf(float(profile.get("tip_width_ratio", 0.4)), 0.02, 1.0)
	var edge_softness := clampf(float(profile.get("edge_softness", 0.12)), 0.01, 0.45)
	var tip_fade := clampf(float(profile.get("tip_fade", 0.16)), 0.01, 0.48)
	var roundness := maxf(float(profile.get("roundness", 1.2)), 0.25)

	for pixel_y in range(resolution.y):
		var v := float(pixel_y) / float(resolution.y - 1)
		var width_progress := smoothstep(0.0, 1.0, v)
		var local_width := lerpf(tip_width_ratio, root_width_ratio, width_progress)
		var tip_alpha := smoothstep(0.0, tip_fade, v)
		for pixel_x in range(resolution.x):
			var centered_x := absf((float(pixel_x) / float(resolution.x - 1)) * 2.0 - 1.0)
			var normalized_edge := centered_x / maxf(local_width, 0.001)
			var edge_alpha := 1.0 - smoothstep(1.0 - edge_softness, 1.0, normalized_edge)
			var alpha := pow(clampf(edge_alpha, 0.0, 1.0), roundness) * tip_alpha
			if alpha > 0.001:
				image.set_pixel(pixel_x, pixel_y, Color(1.0, 1.0, 1.0, alpha))

	var texture := ImageTexture.create_from_image(image)
	_mask_texture_cache[cache_key] = texture
	return texture


static func clear_mask_cache() -> void:
	_mask_texture_cache.clear()


static func _dictionary(value: Variant) -> Dictionary:
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


static func _contains_any(text: String, needles: Array) -> bool:
	for needle in needles:
		if text.contains(str(needle)):
			return true
	return false
