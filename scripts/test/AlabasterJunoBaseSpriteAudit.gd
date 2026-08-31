extends SceneTree

const JunoRigScript := preload("res://scripts/systems/bones/BonesSystem.gd")

const REPORT_PATH := "res://data/labs/alabaster/juno_base_sprite_audit.json"
const CORE_ATLAS_PATH := "res://data/labs/alabaster/juno_base_core_atlas.png"
const SOURCE_FPS := 60.0

# JunoBase is deliberately a player foundation, not a museum of every authored
# Alabaster pose. Keep locomotion, survivability, the basic magic gesture and the
# complete sword family. Alternate weapon families/emotes/cutscene poses remain
# available on full Juno but do not define the base character sheet.
const CORE_GROUPS := {
	"locomotion": ["idle", "walk", "run", "dash", "idleJump1"],
	"combat": [
		"damage", "dead", "guard", "guardParry",
		"atkSwordN1", "atkSwordN2", "atkSwordNFinisher",
		"atkSwordTripleSlash", "atkSwordCrossStrike",
	],
	"utility": ["respawn", "castPoint"],
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var rig_value: Variant = JunoRigScript.new()
	if not rig_value is Node2D:
		_fail("could not instantiate Juno BonesSystem")
		return
	var rig := rig_value as Node2D
	root.add_child(rig)
	await process_frame
	rig.set_process(false)

	var atlas_value: Variant = rig.get("_atlas")
	var nodes_value: Variant = rig.get("_nodes")
	var records_value: Variant = rig.get("_sprite_records")
	if not atlas_value is Texture2D or not nodes_value is Dictionary or not records_value is Array:
		_fail("Juno runtime did not expose atlas/nodes/sprite records")
		return
	var atlas := atlas_value as Texture2D
	var nodes := nodes_value as Dictionary
	var records := records_value as Array
	var source_image := atlas.get_image()
	if source_image == null or source_image.is_empty():
		_fail("could not read Juno atlas image")
		return
	source_image.convert(Image.FORMAT_RGBA8)

	var full_cells := _enumerate_defined_cells(rig, nodes)
	if full_cells.is_empty():
		_fail("could not enumerate Juno source atlas cells")
		return

	var sampled_regions: Dictionary = {}
	var per_animation: Dictionary = {}
	var missing: Array[String] = []
	var core_animations: Array[String] = []
	for group_value in CORE_GROUPS.values():
		if not group_value is Array:
			continue
		for animation_value in group_value as Array:
			var animation_name := str(animation_value)
			if not core_animations.has(animation_name):
				core_animations.append(animation_name)

	for animation_name in core_animations:
		if not bool(rig.call("has_animation", animation_name)):
			missing.append(animation_name)
			continue
		var animation_value: Variant = rig.call("get_animation_data", animation_name)
		if not animation_value is Dictionary:
			missing.append(animation_name)
			continue
		var animation := animation_value as Dictionary
		var start_frame := int(animation.get("animStart", 0))
		var frame_count := maxi(int(animation.get("frameCnt", start_frame + 1)), start_frame + 1)
		var frame_repeat := maxf(float(animation.get("frameRepeat", 1.0)), 1.0)
		var animation_regions: Dictionary = {}
		for facing_index in range(16):
			var facing_degrees := float(facing_index) * 22.5
			var radians := deg_to_rad(facing_degrees)
			var direction := Vector2(sin(radians), -cos(radians))
			rig.call("set_facing_from_vector", direction)
			for frame in range(start_frame, frame_count):
				rig.set("current_animation", animation_name)
				rig.set("animation_time", float(frame - start_frame) * frame_repeat / SOURCE_FPS)
				rig.call("_apply_pose")
				_collect_visible_regions(records, sampled_regions, animation_regions)
		per_animation[animation_name] = {
			"frames": frame_count - start_frame,
			"sampled_facings": 16,
			"unique_render_regions": animation_regions.size(),
		}

	var core_cells: Dictionary = {}
	for cell_key_value in full_cells.keys():
		var cell_key := str(cell_key_value)
		var cell_value: Variant = full_cells[cell_key_value]
		if not cell_value is Dictionary:
			continue
		var cell := cell_value as Dictionary
		var cell_rect := _dict_to_rect(cell)
		for sampled_value in sampled_regions.values():
			if not sampled_value is Dictionary:
				continue
			var sampled_rect := _dict_to_rect(sampled_value as Dictionary)
			if cell_rect.intersects(sampled_rect) or cell_rect.encloses(sampled_rect):
				core_cells[cell_key] = cell.duplicate(true)
				break

	if core_cells.is_empty():
		_fail("core animation sampling did not match any source cells")
		return

	var per_node := _build_per_node_summary(full_cells, core_cells)
	var excluded_cells: Array[Dictionary] = []
	for cell_key_value in full_cells.keys():
		var cell_key := str(cell_key_value)
		if core_cells.has(cell_key):
			continue
		var cell_value: Variant = full_cells[cell_key_value]
		if cell_value is Dictionary:
			excluded_cells.append((cell_value as Dictionary).duplicate(true))

	var kept_cells: Array[Dictionary] = []
	for cell_value in core_cells.values():
		if cell_value is Dictionary:
			kept_cells.append((cell_value as Dictionary).duplicate(true))
	kept_cells.sort_custom(_sort_cell)
	excluded_cells.sort_custom(_sort_cell)

	var core_image := Image.create(source_image.get_width(), source_image.get_height(), false, Image.FORMAT_RGBA8)
	core_image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for cell in kept_cells:
		var rect := _dict_to_recti(cell)
		var clipped := rect.intersection(Rect2i(Vector2i.ZERO, source_image.get_size()))
		if clipped.size.x <= 0 or clipped.size.y <= 0:
			continue
		core_image.blit_rect(source_image, clipped, clipped.position)
	var png_error := core_image.save_png(CORE_ATLAS_PATH)
	if png_error != OK:
		_fail("could not write JunoBase core atlas: %s" % error_string(png_error))
		return

	var report := {
		"version": 1,
		"profile": "juno_base",
		"source_profile": "juno",
		"policy": "Only source atlas cells touched by the core player animation set across all source frames and 16 root facings are retained.",
		"core_groups": CORE_GROUPS.duplicate(true),
		"core_animation_count": core_animations.size(),
		"missing_core_animations": missing,
		"atlas_size": [source_image.get_width(), source_image.get_height()],
		"defined_source_cells": full_cells.size(),
		"core_used_cells": core_cells.size(),
		"excluded_cells": excluded_cells.size(),
		"kept_percent": 100.0 * float(core_cells.size()) / maxf(float(full_cells.size()), 1.0),
		"sampled_render_regions": sampled_regions.size(),
		"per_animation": per_animation,
		"per_node": per_node,
		"kept_cells": kept_cells,
		"excluded_cell_details": excluded_cells,
		"generated_atlas": CORE_ATLAS_PATH,
	}
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		_fail("could not write audit report")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.flush()

	print("ALABASTER_JUNO_BASE_AUDIT_OK core_anims=%d defined=%d kept=%d excluded=%d kept_pct=%.1f render_regions=%d" % [
		core_animations.size(), full_cells.size(), core_cells.size(), excluded_cells.size(),
		float(report["kept_percent"]), sampled_regions.size(),
	])
	for node_value in per_node.keys():
		var node_name := str(node_value)
		var summary_value: Variant = per_node[node_value]
		if summary_value is Dictionary:
			var summary := summary_value as Dictionary
			print("ALABASTER_JUNO_BASE_NODE node=%s defined=%d kept=%d excluded=%d" % [
				node_name,
				int(summary.get("defined", 0)),
				int(summary.get("kept", 0)),
				int(summary.get("excluded", 0)),
			])

	rig.queue_free()
	await process_frame
	quit(0)


func _enumerate_defined_cells(rig: Node2D, nodes: Dictionary) -> Dictionary:
	var cells: Dictionary = {}
	for node_value in nodes.keys():
		var node_name := str(node_value)
		var node_def_value: Variant = nodes[node_value]
		if not node_def_value is Dictionary:
			continue
		var gfx_value: Variant = (node_def_value as Dictionary).get("gfx", [])
		if not gfx_value is Array:
			continue
		var gfx_list := gfx_value as Array
		for gfx_index in range(gfx_list.size()):
			var gfx_entry_value: Variant = gfx_list[gfx_index]
			if not gfx_entry_value is Dictionary:
				continue
			var gfx := gfx_entry_value as Dictionary
			if bool(gfx.get("hidden", false)):
				continue
			var tex_value: Variant = gfx.get("tex", {})
			if not tex_value is Dictionary:
				continue
			var tex := tex_value as Dictionary
			if tex.has("simple") and tex["simple"] is Dictionary:
				_append_entry_cells(rig, cells, node_name, gfx_index, "simple", tex["simple"] as Dictionary, {}, 0)
			var multi_value: Variant = tex.get("multi", {})
			if not multi_value is Dictionary:
				continue
			var entries_value: Variant = (multi_value as Dictionary).get("entries", {})
			if not entries_value is Dictionary:
				continue
			for entry_name_value in (entries_value as Dictionary).keys():
				var entry_name := str(entry_name_value)
				var entry_value: Variant = (entries_value as Dictionary)[entry_name_value]
				if not entry_value is Dictionary:
					continue
				var entry := entry_value as Dictionary
				var variants_value: Variant = entry.get("variants", [])
				if variants_value is Array and not (variants_value as Array).is_empty():
					continue
				var rows_value: Variant = entry.get("rows", [])
				if rows_value is Array and not (rows_value as Array).is_empty():
					var rows := rows_value as Array
					for row_index in range(rows.size()):
						var row_value: Variant = rows[row_index]
						if row_value is Dictionary:
							_append_entry_cells(rig, cells, node_name, gfx_index, entry_name, entry, row_value as Dictionary, row_index)
				else:
					_append_entry_cells(rig, cells, node_name, gfx_index, entry_name, entry, {}, 0)
	return cells


func _append_entry_cells(
	rig: Node2D,
	cells: Dictionary,
	node_name: String,
	gfx_index: int,
	entry_name: String,
	entry: Dictionary,
	row: Dictionary,
	row_index: int
) -> void:
	var range_value: Variant = entry.get("range", [])
	if not range_value is Array or (range_value as Array).size() < 4:
		return
	var range_data := range_value as Array
	var tile_w := int(range_data[2])
	var tile_h := int(range_data[3])
	if tile_w <= 0 or tile_h <= 0:
		return
	var facing_mode := str(entry.get("facing", "FACE_1"))
	var tile_indices: Dictionary = {}
	# One-degree sweep avoids assuming how many tiles each FACE_* mode contains.
	# It also catches flipped variants through the exact source runtime selector.
	for degree in range(360):
		for flip_roll in [false, true]:
			var selected_value: Variant = rig.call("_select_facing_source", facing_mode, float(degree), flip_roll)
			if selected_value is Dictionary:
				var tile := int((selected_value as Dictionary).get("tile", -1))
				if tile >= 0:
					tile_indices[tile] = true
	if tile_indices.is_empty():
		tile_indices[0] = true

	for tile_value in tile_indices.keys():
		var tile := int(tile_value)
		var x := int(range_data[0])
		var y := int(range_data[1])
		if bool(entry.get("extendX", false)):
			x += tile_w * row_index
			y += tile_h * tile
		else:
			x += tile_w * tile
			y += tile_h * row_index
		var key := _rect_key(x, y, tile_w, tile_h)
		var owner := {
			"node": node_name,
			"gfx_index": gfx_index,
			"entry": entry_name,
			"row": row_index,
			"pitch_range": str(row.get("pitchRange", "ALL")),
			"frame_keys": (row.get("frameKeys", []) as Array).duplicate() if row.get("frameKeys", []) is Array else [],
			"facing": facing_mode,
		}
		if not cells.has(key):
			cells[key] = {"x": x, "y": y, "w": tile_w, "h": tile_h, "owners": [owner]}
		else:
			var cell_value: Variant = cells[key]
			if cell_value is Dictionary:
				var cell := cell_value as Dictionary
				var owners_value: Variant = cell.get("owners", [])
				var owners := owners_value as Array if owners_value is Array else []
				owners.append(owner)
				cell["owners"] = owners
				cells[key] = cell


func _collect_visible_regions(records: Array, global_regions: Dictionary, animation_regions: Dictionary) -> void:
	for record_value in records:
		if not record_value is Dictionary:
			continue
		var record := record_value as Dictionary
		var sprite := record.get("sprite") as Sprite2D
		if sprite == null or not sprite.visible:
			continue
		var region := sprite.region_rect
		if region.size.x <= 0.0 or region.size.y <= 0.0:
			continue
		var x := roundi(region.position.x)
		var y := roundi(region.position.y)
		var w := roundi(region.size.x)
		var h := roundi(region.size.y)
		var key := _rect_key(x, y, w, h)
		var data := {
			"x": x, "y": y, "w": w, "h": h,
			"node": str(record.get("node", "")),
			"gfx_index": int(record.get("gfx_index", -1)),
		}
		global_regions[key] = data
		animation_regions[key] = data


func _build_per_node_summary(full_cells: Dictionary, core_cells: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for cell_value in full_cells.values():
		if not cell_value is Dictionary:
			continue
		var cell := cell_value as Dictionary
		var owners_value: Variant = cell.get("owners", [])
		if not owners_value is Array:
			continue
		var seen_nodes: Dictionary = {}
		for owner_value in owners_value as Array:
			if owner_value is Dictionary:
				seen_nodes[str((owner_value as Dictionary).get("node", ""))] = true
		for node_value in seen_nodes.keys():
			var node_name := str(node_value)
			if node_name.is_empty():
				continue
			var summary_value: Variant = result.get(node_name, {"defined": 0, "kept": 0, "excluded": 0})
			var summary := summary_value as Dictionary
			summary["defined"] = int(summary.get("defined", 0)) + 1
			result[node_name] = summary
	for cell_key_value in full_cells.keys():
		var cell_key := str(cell_key_value)
		var cell_value: Variant = full_cells[cell_key_value]
		if not cell_value is Dictionary:
			continue
		var owners_value: Variant = (cell_value as Dictionary).get("owners", [])
		if not owners_value is Array:
			continue
		var seen_nodes: Dictionary = {}
		for owner_value in owners_value as Array:
			if owner_value is Dictionary:
				seen_nodes[str((owner_value as Dictionary).get("node", ""))] = true
		for node_value in seen_nodes.keys():
			var node_name := str(node_value)
			if node_name.is_empty() or not result.has(node_name):
				continue
			var summary := result[node_name] as Dictionary
			if core_cells.has(cell_key):
				summary["kept"] = int(summary.get("kept", 0)) + 1
			else:
				summary["excluded"] = int(summary.get("excluded", 0)) + 1
			result[node_name] = summary
	return result


func _rect_key(x: int, y: int, w: int, h: int) -> String:
	return "%d,%d,%d,%d" % [x, y, w, h]


func _dict_to_rect(value: Dictionary) -> Rect2:
	return Rect2(
		float(value.get("x", 0)), float(value.get("y", 0)),
		float(value.get("w", 0)), float(value.get("h", 0))
	)


func _dict_to_recti(value: Dictionary) -> Rect2i:
	return Rect2i(
		int(value.get("x", 0)), int(value.get("y", 0)),
		int(value.get("w", 0)), int(value.get("h", 0))
	)


func _sort_cell(a: Dictionary, b: Dictionary) -> bool:
	var ay := int(a.get("y", 0))
	var by := int(b.get("y", 0))
	if ay != by:
		return ay < by
	return int(a.get("x", 0)) < int(b.get("x", 0))


func _fail(message: String) -> void:
	printerr("ALABASTER_JUNO_BASE_AUDIT_FAILURE: %s" % message)
	quit(1)
