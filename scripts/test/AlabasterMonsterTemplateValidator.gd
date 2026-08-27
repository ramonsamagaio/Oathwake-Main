extends SceneTree

# Regressão do template de monstro humanoide.
#
# Confere, sem abrir editor, que o par
#   data/labs/alabaster/characters/monster_humanoid_01.json
#   assets/sprites/characters/alabaster/monster_humanoid_01.png
# passa pelo loader canônico, respeita o contrato 672x120 + chroma, mantém todas
# as células dentro do atlas, e realmente desenha o corpo inteiro nas 16 direções.
#
# Rodar:
#   godot --headless --path . --script res://scripts/test/AlabasterMonsterTemplateValidator.gd
#
# Sucesso: ALABASTER_MONSTER_TEMPLATE_VALIDATION_OK ...

const RepoSkinSource := preload("res://scripts/labs/alabaster/AlabasterExternalSkinSource.gd")
const PlayableSkinRigScript := preload("res://scripts/labs/alabaster/AlabasterPlayableSkinRig.gd")

const PROFILE_ID := "monster_humanoid_01"
const FIGURE_NAME := "Monster-Humanoid-01"
const FIGURE_JSON := "res://data/labs/alabaster/characters/monster_humanoid_01.json"
const ATLAS_PATH := "res://assets/sprites/characters/alabaster/monster_humanoid_01.png"
const ATLAS_SIZE := Vector2i(672, 120)
const CHROMA_RGB := Vector3i(255, 0, 195)

const REQUIRED_NODES := [
	"root", "top", "head", "bottom",
	"hipL", "legL", "footL", "toeL",
	"hipR", "legR", "footR", "toeR",
	"shoulderL", "armL", "handL", "fingerL",
	"shoulderR", "armR", "handR", "fingerR",
]

# Famílias de facing permitidas neste template e quantas células únicas cada uma
# consome por linha. Manter fora dessa tabela é sinal de que o figure escapou do
# contrato reduzido e voltou a exigir arte de 8 ou 16 direções autoradas à mão.
const ALLOWED_FACINGS := {
	"FACE_4_MIRR": 3,
	"FACE_4_MIRR_FLIP": 3,
	"FACE_8_MIRR": 5,
	"FACE_8_MIRR_FLIP": 5,
}

const SWEEP_ANIMATIONS := ["walk", "run", "punch"]
# Mínimo de peças desenhadas por direção. O corpo tem 20 nós; ombros e quadris
# não têm gráfico, então o piso realista fica bem abaixo disso.
const MIN_VISIBLE_PIECES := 12

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_files()
	var figure := _check_figure()
	_check_atlas()
	if not _failures.is_empty():
		_finish(0, 0)
		return

	var summary: Dictionary = await _check_rig(figure)
	_finish(int(summary.get("directions", 0)), int(summary.get("min_pieces", 0)))


func _check_files() -> void:
	for path in [FIGURE_JSON, ATLAS_PATH]:
		if not FileAccess.file_exists(path) and not ResourceLoader.exists(path):
			_failures.append("arquivo ausente: %s" % path)


func _check_figure() -> Dictionary:
	if RepoSkinSource.get_source_path(PROFILE_ID).is_empty():
		_failures.append("profile %s não registrado em AlabasterExternalSkinSource.PROFILE_JSON_PATHS" % PROFILE_ID)
		return {}
	if RepoSkinSource.get_repo_atlas_path(PROFILE_ID) != ATLAS_PATH:
		_failures.append("atlas registrado (%s) diferente de %s" % [
			RepoSkinSource.get_repo_atlas_path(PROFILE_ID), ATLAS_PATH,
		])

	# load_skin_figure já roda _validate_humanoid_figure e _validate_sprite_sheet_binding.
	var figure := RepoSkinSource.load_skin_figure(PROFILE_ID)
	if figure.is_empty():
		_failures.append("loader canônico rejeitou o figure %s (ver push_error acima)" % FIGURE_NAME)
		return {}

	var nodes: Dictionary = {}
	var nodes_value: Variant = figure.get("nodes", {})
	if nodes_value is Dictionary:
		nodes = nodes_value as Dictionary
	for node_name in REQUIRED_NODES:
		if not nodes.has(node_name):
			_failures.append("nó ausente: %s" % str(node_name))

	var anims: Dictionary = {}
	var anims_value: Variant = figure.get("anims", {})
	if anims_value is Dictionary:
		anims = anims_value as Dictionary
	for animation_name in SWEEP_ANIMATIONS:
		if not anims.has(animation_name):
			_failures.append("animação nativa ausente no figure: %s" % str(animation_name))

	_check_facings_and_bounds(nodes)
	return figure


func _check_facings_and_bounds(nodes: Dictionary) -> void:
	for node_name_variant in nodes.keys():
		var node_value: Variant = nodes[node_name_variant]
		if not node_value is Dictionary:
			continue
		var gfx_value: Variant = (node_value as Dictionary).get("gfx", [])
		if not gfx_value is Array:
			continue
		var gfx_list := gfx_value as Array
		for gfx_index in range(gfx_list.size()):
			var gfx_entry: Variant = gfx_list[gfx_index]
			if not gfx_entry is Dictionary:
				continue
			var tex_value: Variant = (gfx_entry as Dictionary).get("tex", {})
			if not tex_value is Dictionary:
				continue
			var multi_value: Variant = (tex_value as Dictionary).get("multi", {})
			if not multi_value is Dictionary:
				continue
			var entries_value: Variant = (multi_value as Dictionary).get("entries", {})
			if not entries_value is Dictionary:
				continue
			for entry_key in (entries_value as Dictionary).keys():
				var entry_value: Variant = (entries_value as Dictionary)[entry_key]
				if not entry_value is Dictionary:
					continue
				var entry := entry_value as Dictionary
				var facing := str(entry.get("facing", ""))
				var label := "%s gfx%d [%s]" % [str(node_name_variant), gfx_index, str(entry_key)]
				if not ALLOWED_FACINGS.has(facing):
					_failures.append("%s usa facing %s, fora do contrato reduzido %s" % [
						label, facing, str(ALLOWED_FACINGS.keys()),
					])
					continue

				var range_value: Variant = entry.get("range", [])
				if not range_value is Array or (range_value as Array).size() < 4:
					_failures.append("%s sem range válido" % label)
					continue
				var source_range := range_value as Array
				var origin_x := int(source_range[0])
				var origin_y := int(source_range[1])
				var tile_w := int(source_range[2])
				var tile_h := int(source_range[3])
				var rows_value: Variant = entry.get("rows", [])
				var row_count := 1
				if rows_value is Array:
					row_count = maxi(1, (rows_value as Array).size())
				var cells := int(ALLOWED_FACINGS[facing])

				var needed_x := origin_x + tile_w * cells
				var needed_y := origin_y + tile_h * row_count
				if needed_x > ATLAS_SIZE.x:
					_failures.append("%s estoura o atlas na horizontal: precisa de x até %d" % [label, needed_x])
				if needed_y > ATLAS_SIZE.y:
					_failures.append("%s estoura o atlas na vertical: precisa de y até %d" % [label, needed_y])


func _check_atlas() -> void:
	var image := Image.new()
	if image.load(ATLAS_PATH) != OK or image.is_empty():
		_failures.append("não foi possível abrir o atlas %s" % ATLAS_PATH)
		return
	if image.get_width() != ATLAS_SIZE.x or image.get_height() != ATLAS_SIZE.y:
		_failures.append("atlas tem %dx%d, o runtime exige %dx%d" % [
			image.get_width(), image.get_height(), ATLAS_SIZE.x, ATLAS_SIZE.y,
		])
		return
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)

	var chroma_pixels := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if int(round(color.r * 255.0)) == CHROMA_RGB.x \
					and int(round(color.g * 255.0)) == CHROMA_RGB.y \
					and int(round(color.b * 255.0)) == CHROMA_RGB.z:
				chroma_pixels += 1
	if chroma_pixels == 0:
		_failures.append("atlas não usa o chroma RGB(255,0,195); o fundo não vai virar transparente")

	var texture := RepoSkinSource.load_skin_texture(PROFILE_ID)
	if texture == null:
		_failures.append("load_skin_texture devolveu null para %s" % PROFILE_ID)


func _check_rig(figure: Dictionary) -> Dictionary:
	if figure.is_empty():
		return {}
	var rig_value: Variant = PlayableSkinRigScript.new()
	if not rig_value is Node2D:
		_failures.append("AlabasterPlayableSkinRig não instanciou um Node2D")
		return {}
	var rig := rig_value as Node2D
	# Mesma ordem usada por AlabasterPlayerVisualController e pelo Mechanic Lab.
	rig.call("configure_skin_profile", PROFILE_ID)
	rig.name = "MonsterTemplateRig"
	root.add_child(rig)
	await process_frame

	if not bool(rig.call("initialize_skin")):
		_failures.append("initialize_skin() falhou para %s" % PROFILE_ID)
		rig.queue_free()
		await process_frame
		return {}
	if not bool(rig.call("is_skin_ready")):
		_failures.append("is_skin_ready() falso depois de initialize_skin()")
		rig.queue_free()
		await process_frame
		return {}

	var directions: Array[Vector2] = []
	for step in range(16):
		var radians := deg_to_rad(float(step) * 22.5)
		directions.append(Vector2(sin(radians), -cos(radians)))

	var min_pieces := 1 << 30
	var checked_directions := 0
	for animation_name in SWEEP_ANIMATIONS:
		rig.call("set_animation", animation_name)
		await process_frame
		for direction in directions:
			rig.call("set_facing_from_vector", direction)
			await process_frame
			checked_directions += 1
			var visible_pieces := -1
			if rig.has_method("_count_visible_pieces"):
				visible_pieces = int(rig.call("_count_visible_pieces"))
			if visible_pieces < 0:
				continue
			min_pieces = mini(min_pieces, visible_pieces)
			if visible_pieces < MIN_VISIBLE_PIECES:
				_failures.append("anim=%s direção=%.0f° desenhou só %d peças (mínimo %d)" % [
					animation_name,
					rad_to_deg(atan2(direction.x, -direction.y)),
					visible_pieces,
					MIN_VISIBLE_PIECES,
				])

	var summary: Dictionary = {}
	var summary_value: Variant = rig.call("get_runtime_summary")
	if summary_value is Dictionary:
		summary = summary_value as Dictionary
	print("ALABASTER_MONSTER_TEMPLATE_RUNTIME profile=%s figure=%s pieces=%d texture=%s data=%s" % [
		str(summary.get("skin_profile_id", "")),
		str(summary.get("figure_source", "")),
		int(summary.get("sprite_piece_count", 0)),
		str(summary.get("skin_texture_source", "")),
		str(summary.get("skin_data_source", "")),
	])

	rig.queue_free()
	await process_frame
	return {"directions": checked_directions, "min_pieces": 0 if min_pieces == (1 << 30) else min_pieces}


func _finish(directions: int, min_pieces: int) -> void:
	if _failures.is_empty():
		print("ALABASTER_MONSTER_TEMPLATE_VALIDATION_OK profile=%s directions=%d min_visible_pieces=%d" % [
			PROFILE_ID, directions, min_pieces,
		])
		quit(0)
		return
	for failure in _failures:
		printerr("ALABASTER_MONSTER_TEMPLATE_VALIDATION_FAILURE: %s" % failure)
	quit(1)
