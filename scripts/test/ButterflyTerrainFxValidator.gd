extends SceneTree

const BUTTERFLY_SCENE := preload("res://scenes/enemies/ButterflyMonster.tscn")
const STUN_SCENE := preload("res://scenes/effects/StunEffect.tscn")
const SPAWNER_SCRIPT := preload("res://scripts/enemies/NightEnemySpawner.gd")
const INVENTORY_SCRIPT := preload("res://scripts/Inventory.gd")

const BUTTERFLY_IDS := [
	"butterfly_blue",
	"butterfly_grey",
	"butterfly_pink",
	"butterfly_red",
	"butterfly_white",
	"butterfly_yellow",
]

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_content()
	_validate_inventory_items()
	_validate_content_editor_contract()
	await _validate_wild_butterfly_runtime()
	await _validate_stun_frames()
	await _validate_spawn_visibility_guard()
	if failures.is_empty():
		print("BUTTERFLY_TERRAIN_FX_VALIDATION_PASS")
		quit(0)
		return
	for failure in failures:
		push_error("BUTTERFLY_TERRAIN_FX_VALIDATION_FAILURE: %s" % failure)
	quit(1)


func _validate_content() -> void:
	var content_db := root.get_node_or_null("ContentDB")
	if content_db == null:
		failures.append("ContentDB unavailable.")
		return
	for butterfly_id in BUTTERFLY_IDS:
		if not content_db.has_monster(butterfly_id):
			failures.append("Missing butterfly monster %s." % butterfly_id)
			continue
		var data: Dictionary = content_db.get_monster(butterfly_id)
		if int(data.get("max_health", 0)) != 10:
			failures.append("%s does not have exactly 10 health." % butterfly_id)
		if not bool(data.get("peaceful", false)) or not bool(data.get("fearful", false)):
			failures.append("%s is not both peaceful and fearful." % butterfly_id)
		var loot: Variant = data.get("loot_table", [])
		if not loot is Array or loot.size() != 1 or str((loot[0] as Dictionary).get("item_id", "")) != "butterfly_wings":
			failures.append("%s does not drop only butterfly_wings." % butterfly_id)
		if not (data.get("spawn_tiles", []) as Array).has("grass"):
			failures.append("%s is not registered for grass spawn." % butterfly_id)
	var grass: Dictionary = content_db.get_terrain_type("grass")
	var spawn_entries: Variant = grass.get("monster_spawns", [])
	if not spawn_entries is Array or spawn_entries.size() != 7:
		failures.append("Grass terrain does not contain slime plus all six butterflies.")


func _validate_inventory_items() -> void:
	var inventory = INVENTORY_SCRIPT.new()
	if inventory.add_item("campfire", 1) != 0 or inventory.get_count("campfire") != 1:
		failures.append("Campfire still cannot enter the inventory.")
	if inventory.add_item("butterfly_wings", 1) != 0 or inventory.get_count("butterfly_wings") != 1:
		failures.append("Butterfly wings cannot enter the inventory.")


func _validate_content_editor_contract() -> void:
	var editor_text := FileAccess.get_file_as_string("res://tools/content_editor/ContentEditorRuntimeTuningSuite.gd")
	for token in ["Peaceful", "Fearful", "runtime_monster_peaceful", "runtime_monster_fearful"]:
		if not editor_text.contains(token):
			failures.append("Content Editor is missing disposition field %s." % token)


func _validate_wild_butterfly_runtime() -> void:
	var butterfly := BUTTERFLY_SCENE.instantiate() as CharacterBody2D
	butterfly.set("monster_id", "butterfly_blue")
	root.add_child(butterfly)
	await process_frame
	await process_frame
	if int(butterfly.get("max_health")) != 10 or int(butterfly.get("health")) != 10:
		failures.append("Wild butterfly runtime health did not load as 10.")
	if not bool(butterfly.get("peaceful")) or not bool(butterfly.get("fearful")):
		failures.append("Wild butterfly runtime disposition did not load.")
	var sprite := butterfly.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null or sprite.sprite_frames == null or sprite.sprite_frames.get_frame_count("idle") != 5:
		failures.append("Wild butterfly did not load its five-frame sprite sheet.")
	var shadow := butterfly.get_node_or_null("GroundShadow") as Node2D
	if shadow == null or shadow.position.y < 24.0:
		failures.append("Wild butterfly shadow is not far below its flight sprite.")
	butterfly.queue_free()
	await process_frame


func _validate_stun_frames() -> void:
	var stun := STUN_SCENE.instantiate()
	root.add_child(stun)
	await process_frame
	if int(stun.call("get_frame_count")) != 7:
		failures.append("Stun effect did not load STUN_0001 through STUN_0007.")
	stun.queue_free()
	await process_frame


func _validate_spawn_visibility_guard() -> void:
	var player := CharacterBody2D.new()
	player.name = "SpawnVisibilityPlayer"
	root.add_child(player)
	player.global_position = Vector2(200.0, 200.0)
	var spawner := SPAWNER_SCRIPT.new()
	root.add_child(spawner)
	spawner.player = player
	await process_frame
	if spawner.is_position_outside_player_view(player.global_position):
		failures.append("Spawner considers the player position outside the visible screen.")
	if not spawner.is_position_outside_player_view(Vector2(100000.0, 100000.0)):
		failures.append("Spawner accepts a clearly offscreen position as visible.")
	spawner.queue_free()
	player.queue_free()
	await process_frame
