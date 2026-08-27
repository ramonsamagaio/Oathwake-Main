extends "res://scripts/labs/alabaster/AlabasterRigRuntimeSource.gd"
class_name OathwakeMonsterRig

# Rig de monstro humanoide do Oathwake.
#
# ADITIVO: nao altera nenhuma classe existente. Ele se pendura direto em
# AlabasterRigRuntimeSource, que e a camada de TECNICA pura do lab Alabaster
# (hierarquia 3D -> projecao 2D -> escolha de celula por direcao e pitch).
#
# Tudo acima dessa camada na cadeia original ja carrega dado da Juno:
#   AlabasterRigRuntimeSourceLive  -> junta o banco de animacoes da Juno
#   BonesSystem / PlayableSkinRig  -> HumanoidRetarget.install_juno_gameplay()
# Por isso este rig NAO herda de nenhuma delas. Aqui nao existe idle/walk/run
# da Juno, nem atlas da Juno, nem figure do Male-Dummy.
#
# O figure e o atlas sao proprios:
#   - hierarquia e proporcoes vindas do esqueleto de rest dos FBX do Mixamo
#   - animacoes retargetadas dos FBX em assets/anims
#   - atlas 672x120 autoral, chroma RGB(255,0,195)

# Um figure + um atlas = um profile. Trocar de monstro e trocar de entrada
# aqui; nenhuma outra classe do jogo sabe que estes existem.
const PROFILES := {
	"monster_01": {
		"label": "PLACEHOLDER",
		"json": "res://data/monsters/oathwake_monster_01.json",
		"figure": "Oathwake-Monster-01",
		"atlas": "res://assets/sprites/characters/monsters/oathwake_monster_01.png",
	},
	"golem_stone": {
		"label": "GOLEM PEDRA",
		"json": "res://data/monsters/oathwake_golem_01.json",
		"figure": "Oathwake-Golem-01",
		"atlas": "res://assets/sprites/characters/monsters/oathwake_golem_01.png",
	},
	"golem_jade": {
		"label": "GOLEM JADE",
		"json": "res://data/monsters/oathwake_golem_01.json",
		"figure": "Oathwake-Golem-01",
		"atlas": "res://assets/sprites/characters/monsters/oathwake_golem_jade_01.png",
	},
}
const DEFAULT_PROFILE := "golem_stone"
const ATLAS_SIZE := Vector2i(672, 120)
const CHROMA_RGB := Vector3i(255, 0, 195)
const DEFAULT_ANIMATION := "walk"

var profile_id := DEFAULT_PROFILE
var monster_ready := false
var _sprite_opacity := 1.0
var _load_report := {}


func configure_profile(id: String) -> void:
	if not PROFILES.has(id):
		push_error("OathwakeMonsterRig: profile desconhecido '%s'; disponiveis=%s" % [
			id, str(PROFILES.keys()),
		])
		return
	profile_id = id
	monster_ready = false


func get_profile_ids() -> Array:
	return PROFILES.keys()


func get_profile_label() -> String:
	var entry: Variant = PROFILES.get(profile_id, {})
	return str((entry as Dictionary).get("label", profile_id)) if entry is Dictionary else profile_id


func _profile_value(key: String) -> String:
	var entry: Variant = PROFILES.get(profile_id, {})
	return str((entry as Dictionary).get(key, "")) if entry is Dictionary else ""


func _ready() -> void:
	# _ready() da base carrega o runtime da Juno. Nao chamamos super de proposito.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	initialize_monster()


func initialize_monster() -> bool:
	if monster_ready:
		return true
	monster_ready = false
	_load_report = {}

	if not _load_figure():
		return false
	if not _load_atlas():
		return false

	_build_sprite_records()
	if _sprite_records.is_empty():
		push_error("OathwakeMonsterRig: nenhum sprite construido a partir de %s" % _profile_value("json"))
		return false

	current_animation = DEFAULT_ANIMATION if _anims.has(DEFAULT_ANIMATION) else ""
	animation_time = 0.0
	_apply_pose()

	var visible_pieces := count_visible_pieces()
	monster_ready = visible_pieces > 0
	set_process(monster_ready)
	_apply_sprite_opacity()

	print("OATHWAKE_MONSTER_READY profile=%s figure=%s nodes=%d anims=%s pieces=%d visible=%d atlas=%dx%d ready=%s" % [
		profile_id,
		_profile_value("figure"),
		_nodes.size(),
		str(get_animation_names()),
		_sprite_records.size(),
		visible_pieces,
		_atlas.get_width(), _atlas.get_height(),
		str(monster_ready),
	])
	if not monster_ready:
		push_error("OathwakeMonsterRig: figure carregou mas nenhuma peca ficou visivel")
	return monster_ready


func _load_figure() -> bool:
	var figure_json := _profile_value("json")
	var figure_name := _profile_value("figure")
	if not FileAccess.file_exists(figure_json):
		push_error("OathwakeMonsterRig: figure ausente %s" % figure_json)
		return false
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(figure_json)) != OK:
		push_error("OathwakeMonsterRig: JSON invalido em %s linha %d: %s" % [
			figure_json, json.get_error_line(), json.get_error_message(),
		])
		return false
	var parsed: Variant = json.data
	if not parsed is Dictionary:
		push_error("OathwakeMonsterRig: raiz do JSON nao e dicionario")
		return false

	var figures_value: Variant = (parsed as Dictionary).get("figures", {})
	if not figures_value is Dictionary:
		push_error("OathwakeMonsterRig: bloco 'figures' ausente")
		return false
	var figure_value: Variant = (figures_value as Dictionary).get(figure_name, {})
	if not figure_value is Dictionary or (figure_value as Dictionary).is_empty():
		push_error("OathwakeMonsterRig: figure %s nao encontrado; disponiveis=%s" % [
			figure_name, str((figures_value as Dictionary).keys()),
		])
		return false

	_figure = (figure_value as Dictionary).duplicate(true)
	var nodes_value: Variant = _figure.get("nodes", {})
	var anims_value: Variant = _figure.get("anims", {})
	_nodes = (nodes_value as Dictionary).duplicate(true) if nodes_value is Dictionary else {}
	_anims = (anims_value as Dictionary).duplicate(true) if anims_value is Dictionary else {}
	_track_cache.clear()
	_root_dirs.clear()

	if _nodes.is_empty():
		push_error("OathwakeMonsterRig: figure sem nós")
		return false
	if _anims.is_empty():
		push_error("OathwakeMonsterRig: figure sem animações")
		return false
	_load_report["nodes"] = _nodes.size()
	_load_report["anims"] = _anims.size()
	return true


func _load_atlas() -> bool:
	var atlas_path := _profile_value("atlas")
	var image := Image.new()
	if ResourceLoader.exists(atlas_path):
		var resource := load(atlas_path)
		if resource is Texture2D:
			image = (resource as Texture2D).get_image()
	if image == null or image.is_empty():
		image = Image.new()
		if image.load(atlas_path) != OK or image.is_empty():
			push_error("OathwakeMonsterRig: nao foi possivel carregar o atlas %s" % atlas_path)
			return false
	if image.get_width() != ATLAS_SIZE.x or image.get_height() != ATLAS_SIZE.y:
		push_error("OathwakeMonsterRig: atlas %s tem %dx%d, esperado %dx%d" % [
			atlas_path, image.get_width(), image.get_height(), ATLAS_SIZE.x, ATLAS_SIZE.y,
		])
		return false
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)

	var rgba := image.get_data()
	var keyed := 0
	var index := 0
	while index + 3 < rgba.size():
		if int(rgba[index]) == CHROMA_RGB.x \
				and int(rgba[index + 1]) == CHROMA_RGB.y \
				and int(rgba[index + 2]) == CHROMA_RGB.z:
			rgba[index + 3] = 0
			keyed += 1
		index += 4
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, rgba)
	_atlas = ImageTexture.create_from_image(image)
	_load_report["chroma_pixels"] = keyed
	return _atlas != null


# --------------------------------------------------------------- API publica
func has_animation(animation_name: String) -> bool:
	return _anims.has(animation_name)


func get_animation_names() -> Array:
	var names := _anims.keys()
	names.sort()
	return names


func count_visible_pieces() -> int:
	var visible_pieces := 0
	for record_variant in _sprite_records:
		if not record_variant is Dictionary:
			continue
		var sprite := (record_variant as Dictionary).get("sprite") as Sprite2D
		if sprite != null and sprite.visible:
			visible_pieces += 1
	return visible_pieces


func set_sprite_opacity(value: float) -> void:
	_sprite_opacity = clampf(value, 0.0, 1.0)
	_apply_sprite_opacity()


func _apply_sprite_opacity() -> void:
	for record_variant in _sprite_records:
		if not record_variant is Dictionary:
			continue
		var sprite := (record_variant as Dictionary).get("sprite") as Sprite2D
		if sprite != null:
			sprite.modulate.a = _sprite_opacity


func seek_animation_frame(frame: float) -> void:
	var anim_value: Variant = _anims.get(current_animation, {})
	if not anim_value is Dictionary:
		return
	var frame_repeat: float = maxf(float((anim_value as Dictionary).get("frameRepeat", 1.0)), 1.0)
	animation_time = frame * frame_repeat / SRC_FPS
	_apply_pose()


func get_runtime_summary() -> Dictionary:
	var result := super.get_runtime_summary()
	result["profile_id"] = profile_id
	result["profile_label"] = get_profile_label()
	result["figure"] = _profile_value("figure")
	result["figure_json"] = _profile_value("json")
	result["atlas_path"] = _profile_value("atlas")
	result["monster_ready"] = monster_ready
	result["animations"] = get_animation_names()
	result["visible_pieces"] = count_visible_pieces()
	result["load_report"] = _load_report.duplicate(true)
	result["juno_data_used"] = false
	return result
