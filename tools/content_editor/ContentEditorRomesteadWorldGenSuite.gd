extends "res://tools/content_editor/ContentEditorPlayerCharacterExactSuite.gd"

# Romestead world-generation controls extend the existing Content Editor form.
# They are persisted by the inherited save path into data/world_gen.json, which
# is also the file consumed by the active procedural world at generation time.


func _build_world_gen_form() -> void:
	super._build_world_gen_form()

	_add_form_section_heading("Biomas Romestead")
	_add_float_spin_box(
		"Escala do ruído de biomas",
		"biome_noise_scale",
		float(current_record.get("biome_noise_scale", 1.0)),
		0.35,
		3.0,
		0.05
	)
	_add_field_hint("1.0 preserva a escala nativa. Menor cria massas maiores; maior fragmenta mais os biomas.")
	_add_float_spin_box(
		"Distância dos centros de bioma",
		"biome_keypoint_radius_ratio",
		float(current_record.get("biome_keypoint_radius_ratio", 0.375)),
		0.15,
		0.49,
		0.005
	)
	_add_field_hint("Fração do tamanho do mapa usada pelo anel de pontos-chave do Romestead. O valor nativo é 0.375.")

	_add_form_section_heading("Deserto")
	_add_spin_box(
		"Raio do núcleo (tiles)",
		"desert_radius_tiles",
		int(current_record.get("desert_radius_tiles", 100)),
		0,
		384,
		1
	)
	_add_field_hint("0 desliga o deserto. O centro continua sendo escolhido pelo algoritmo de pontos-chave do Romestead.")
	_add_spin_box(
		"Transição (tiles)",
		"desert_transition_tiles",
		int(current_record.get("desert_transition_tiles", 32)),
		0,
		192,
		1
	)
	_add_float_spin_box(
		"Irregularidade da borda",
		"desert_irregularity",
		float(current_record.get("desert_irregularity", 0.3)),
		0.0,
		1.0,
		0.01
	)
	_add_float_spin_box(
		"Densidade de props",
		"desert_prop_density",
		float(current_record.get("desert_prop_density", 0.22)),
		0.0,
		1.0,
		0.01
	)
	_add_field_hint("Controla pedras e arbustos roxos dentro do deserto sem alterar a densidade dos outros biomas.")

	_add_form_section_heading("Streaming / chunks")
	_add_spin_box(
		"Chunk de terreno (tiles)",
		"runtime_terrain_chunk_tiles",
		int(current_record.get("runtime_terrain_chunk_tiles", 8)),
		4,
		32,
		1
	)
	_add_field_hint("É o microchunk que o worldgen ativo realmente materializa em runtime. 8 = blocos de 8x8 tiles.")


func _get_world_gen_form_record() -> Dictionary:
	var record := super._get_world_gen_form_record()
	record["biome_noise_scale"] = _get_float_spin_box_value("biome_noise_scale")
	record["biome_keypoint_radius_ratio"] = _get_float_spin_box_value("biome_keypoint_radius_ratio")
	record["desert_radius_tiles"] = int(_get_spin_box_value("desert_radius_tiles"))
	record["desert_transition_tiles"] = int(_get_spin_box_value("desert_transition_tiles"))
	record["desert_irregularity"] = _get_float_spin_box_value("desert_irregularity")
	record["desert_prop_density"] = _get_float_spin_box_value("desert_prop_density")
	record["runtime_terrain_chunk_tiles"] = int(_get_spin_box_value("runtime_terrain_chunk_tiles"))
	return record
