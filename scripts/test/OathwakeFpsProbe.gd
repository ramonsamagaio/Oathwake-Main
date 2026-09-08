extends CanvasLayer
## Medidor de FPS com bisect A/B em jogo.
##
## Por que existe: adivinhar quem derruba o frame rate em cima do código dá
## palpite, não resposta. Este probe mede e, mais importante, deixa DESLIGAR um
## suspeito por vez e ver o delta de FPS na hora. É a diferença entre "acho que
## são os shaders" e "são os shaders, +14 fps".
##
## F9 abre/fecha. Fora de build de debug ele nem entra na árvore.

const SAMPLE_SECONDS := 1.0
const BASELINE_SETTLE_SECONDS := 1.5

var _panel: PanelContainer
var _label: RichTextLabel
var _elapsed := 0.0
var _frames := 0
var _fps_atual := 0.0
var _baseline_fps := 0.0
var _settle := 0.0

# id -> {"nome", "ligado", "fps_desligado"}
var _suspeitos: Dictionary = {}
var _ordem: Array[String] = []


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_process(false)
	set_process_unhandled_key_input(true)
	_registrar_suspeitos()
	_construir_ui()


func _registrar_suspeitos() -> void:
	_definir("shaders_terreno", "Shaders das camadas de terreno")
	_definir("post_process", "Pixelation / post-process")
	_definir("scheduler", "Scheduler de streaming do mundo")
	_definir("wildlife", "Wildlife (bichos do mundo)")
	_definir("props", "Props do mundo (árvores, rochas, mato)")
	_definir("inimigos", "Inimigos")
	_definir("ysort_props", "Y-sort da raiz de props")


func _definir(id: String, nome: String) -> void:
	_suspeitos[id] = {"nome": nome, "ligado": true, "fps_desligado": 0.0}
	_ordem.append(id)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_F9:
		visible = not visible
		set_process(visible)
		if visible:
			_baseline_fps = 0.0
			_settle = 0.0
		get_viewport().set_input_as_handled()
		return
	if not visible:
		return
	# F1..F7 alternam o suspeito correspondente.
	var index := key.keycode - KEY_F1
	if index >= 0 and index < _ordem.size():
		_alternar(_ordem[index])
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_frames += 1
	_elapsed += delta
	if _settle < BASELINE_SETTLE_SECONDS:
		_settle += delta
	if _elapsed < SAMPLE_SECONDS:
		return
	_fps_atual = float(_frames) / _elapsed
	_frames = 0
	_elapsed = 0.0
	if _baseline_fps <= 0.0 and _settle >= BASELINE_SETTLE_SECONDS and _todos_ligados():
		_baseline_fps = _fps_atual
	_atualizar_texto()


func _todos_ligados() -> bool:
	for id in _ordem:
		if not bool((_suspeitos[id] as Dictionary)["ligado"]):
			return false
	return true


func _alternar(id: String) -> void:
	var entrada: Dictionary = _suspeitos[id]
	var ligar := not bool(entrada["ligado"])
	var aplicou := _aplicar(id, ligar)
	if not aplicou:
		entrada["nome"] = str(entrada["nome"]) + " (não encontrado)"
		_suspeitos[id] = entrada
		_atualizar_texto()
		return
	entrada["ligado"] = ligar
	if not ligar:
		# Guarda o FPS medido logo depois de desligar, para comparar com a linha
		# de base. A leitura só vale depois da próxima amostra de 1 s.
		entrada["fps_desligado"] = 0.0
	_suspeitos[id] = entrada
	_settle = 0.0
	_elapsed = 0.0
	_frames = 0
	_atualizar_texto()


func _aplicar(id: String, ligar: bool) -> bool:
	match id:
		"shaders_terreno":
			return _alternar_shaders_terreno(ligar)
		"post_process":
			return _alternar_no_por_nome(["/root/PixelationPostProcess", "/root/PixelVFX"], ligar)
		"scheduler":
			return _alternar_scheduler(ligar)
		"wildlife":
			return _alternar_raiz("Enemies", ligar, true)
		"props":
			return _alternar_raiz("Props", ligar, false) or _alternar_raiz("Resources", ligar, false)
		"inimigos":
			return _alternar_raiz("Enemies", ligar, false)
		"ysort_props":
			return _alternar_ysort(ligar)
	return false


func _mundo() -> Node:
	return get_tree().get_first_node_in_group("procedural_resource_world")


func _alternar_shaders_terreno(ligar: bool) -> bool:
	var mundo := _mundo()
	if mundo == null:
		return false
	var materiais_value: Variant = mundo.get("_terrain_materials")
	if not materiais_value is Array:
		return false
	var materiais: Array = materiais_value
	if materiais.is_empty():
		return false
	if ligar:
		var guardados_value: Variant = get_meta("materiais_guardados", null)
		if not guardados_value is Array:
			return false
		var guardados: Array = guardados_value
		var camadas := _camadas_de_terreno(mundo)
		for index in range(mini(camadas.size(), guardados.size())):
			(camadas[index] as CanvasItem).material = guardados[index]
		return true
	var camadas_off := _camadas_de_terreno(mundo)
	var backup: Array = []
	for camada in camadas_off:
		backup.append((camada as CanvasItem).material)
		(camada as CanvasItem).material = null
	set_meta("materiais_guardados", backup)
	return true


func _camadas_de_terreno(mundo: Node) -> Array:
	var camadas: Array = []
	for child in mundo.get_children():
		if child is TileMapLayer:
			camadas.append(child)
	return camadas


func _alternar_no_por_nome(caminhos: Array, ligar: bool) -> bool:
	var achou := false
	for caminho in caminhos:
		var no := get_node_or_null(NodePath(str(caminho)))
		if no == null:
			continue
		achou = true
		no.process_mode = Node.PROCESS_MODE_INHERIT if ligar else Node.PROCESS_MODE_DISABLED
		if no is CanvasItem:
			(no as CanvasItem).visible = ligar
		if no is CanvasLayer:
			(no as CanvasLayer).visible = ligar
	return achou


func _alternar_scheduler(ligar: bool) -> bool:
	for no in get_tree().get_nodes_in_group("romestead_runtime_scheduler"):
		(no as Node).set_process(ligar)
		return true
	# Sem grupo: procura pela classe entre os irmãos do mundo.
	var mundo := _mundo()
	if mundo == null or mundo.get_parent() == null:
		return false
	for irmao in mundo.get_parent().get_children():
		if irmao.get_script() != null and str(irmao.get_script().resource_path).ends_with("RomesteadRuntimeScheduler.gd"):
			(irmao as Node).set_process(ligar)
			return true
	return false


func _alternar_raiz(nome: String, ligar: bool, so_processo: bool) -> bool:
	var mundo: Node = _mundo()
	var pai: Node = mundo.get_parent() if mundo != null else null
	var raiz: Node = pai.get_node_or_null(nome) if pai != null else null
	if raiz == null:
		raiz = get_tree().get_root().find_child(nome, true, false)
	if raiz == null:
		return false
	raiz.process_mode = Node.PROCESS_MODE_INHERIT if ligar else Node.PROCESS_MODE_DISABLED
	if not so_processo and raiz is CanvasItem:
		(raiz as CanvasItem).visible = ligar
	return true


func _alternar_ysort(ligar: bool) -> bool:
	var mundo: Node = _mundo()
	var pai: Node = mundo.get_parent() if mundo != null else null
	if pai == null:
		return false
	var achou := false
	for nome in ["Props", "Resources", "Enemies", "WindVegetation"]:
		var raiz: Node = pai.get_node_or_null(nome)
		if raiz == null and mundo != null:
			raiz = mundo.get_node_or_null(nome)
		if raiz is Node2D:
			(raiz as Node2D).y_sort_enabled = ligar
			achou = true
	return achou


func _construir_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.0
	_panel.anchor_top = 0.0
	_panel.offset_left = 12.0
	_panel.offset_top = 12.0
	add_child(_panel)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.custom_minimum_size = Vector2(430, 0)
	_label.scroll_active = false
	_panel.add_child(_label)
	_atualizar_texto()


func _atualizar_texto() -> void:
	if _label == null:
		return
	var linhas: Array[String] = []
	linhas.append("[b]Oathwake FPS Probe[/b]   F9 fecha")
	linhas.append("fps %.1f   base %.1f" % [_fps_atual, _baseline_fps])
	linhas.append("frame %.2f ms | process %.2f ms | fisica %.2f ms" % [
		1000.0 / maxf(_fps_atual, 0.001),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
	])
	linhas.append("draw calls %d | objetos %d | nos %d | orfaos %d" % [
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
	])
	linhas.append("vram %.1f MB" % (Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0))
	linhas.append("")
	linhas.append("[b]Desligue um por vez (F1..F%d)[/b]" % _ordem.size())
	for index in range(_ordem.size()):
		var entrada: Dictionary = _suspeitos[_ordem[index]]
		var ligado := bool(entrada["ligado"])
		var estado := "[color=#8fdc8f]on [/color]" if ligado else "[color=#ff9a7a]OFF[/color]"
		var ganho := ""
		if not ligado and _baseline_fps > 0.0 and _fps_atual > 0.0:
			ganho = "   %+.1f fps" % (_fps_atual - _baseline_fps)
		linhas.append("F%d %s %s%s" % [index + 1, estado, str(entrada["nome"]), ganho])
	linhas.append("")
	linhas.append("[i]Ligue tudo de volta antes de medir o proximo.[/i]")
	_label.text = "\n".join(linhas)
