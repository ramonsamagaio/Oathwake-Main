extends Node2D

# Lab isolado do monstro Oathwake. Nao toca em nenhuma cena ou sistema existente.
#
# Controles:
#   WASD / setas ....... gira o monstro (define a direcao)
#   Tab ................ proxima animacao
#   1 / 2 / 3 .......... walk / run / punch
#   O / P .............. diminui / aumenta a opacidade dos sprites
#   F1 ................. liga o desenho de debug do esqueleto
#   Espaco ............. pausa e despausa
#   [ / ] .............. quadro anterior / proximo (com a animacao pausada)

const MonsterRig := preload("res://scripts/monsters/OathwakeMonsterRig.gd")

var rig: Node2D
var _label: Label
var _profile := "golem_stone"
var _facing := Vector2(0.0, -1.0)
var _paused := false
var _frame := 0.0
var _opacity := 1.0


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.11, 0.14)
	bg.size = Vector2(1280, 720)
	bg.z_index = -100
	add_child(bg)

	_spawn_rig()

	_label = Label.new()
	_label.position = Vector2(24, 20)
	_label.add_theme_font_size_override("font_size", 16)
	add_child(_label)
	_update_label()


func _spawn_rig() -> void:
	if rig != null and is_instance_valid(rig):
		rig.queue_free()
	rig = MonsterRig.new()
	rig.name = "OathwakeMonster"
	rig.position = Vector2(640, 470)
	rig.scale = Vector2(4.0, 4.0)
	rig.call("configure_profile", _profile)
	add_child(rig)
	rig.call("set_facing_from_vector", _facing)
	if rig.has_method("set_sprite_opacity"):
		rig.call("set_sprite_opacity", _opacity)
	_frame = 0.0


func _set_profile(id: String) -> void:
	_profile = id
	_spawn_rig()


func _process(_delta: float) -> void:
	if rig != null and _paused:
		rig.call("seek_animation_frame", _frame)
	_update_label()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	match key:
		KEY_W, KEY_UP:
			_set_facing(Vector2(0.0, -1.0))
		KEY_S, KEY_DOWN:
			_set_facing(Vector2(0.0, 1.0))
		KEY_A, KEY_LEFT:
			_set_facing(Vector2(-1.0, 0.0))
		KEY_D, KEY_RIGHT:
			_set_facing(Vector2(1.0, 0.0))
		KEY_Q:
			_set_facing(_facing.rotated(deg_to_rad(-22.5)))
		KEY_E:
			_set_facing(_facing.rotated(deg_to_rad(22.5)))
		KEY_1:
			_play("walk")
		KEY_2:
			_play("run")
		KEY_3:
			_play("punch")
		KEY_7:
			_set_profile("monster_01")
		KEY_8:
			_set_profile("golem_stone")
		KEY_9:
			_set_profile("golem_jade")
		KEY_TAB:
			_cycle_animation()
		KEY_O:
			_set_opacity(_opacity - 0.1)
		KEY_P:
			_set_opacity(_opacity + 0.1)
		KEY_F1:
			if rig.has_method("set_debug_enabled"):
				rig.call("set_debug_enabled", not bool(rig.get("debug_enabled")))
		KEY_SPACE:
			_paused = not _paused
			rig.set_process(not _paused)
		KEY_BRACKETLEFT:
			_frame = maxf(_frame - 1.0, 0.0)
		KEY_BRACKETRIGHT:
			_frame += 1.0


func _set_facing(direction: Vector2) -> void:
	if direction.length_squared() < 0.0001:
		return
	_facing = direction.normalized()
	rig.call("set_facing_from_vector", _facing)


func _play(animation_name: String) -> void:
	if rig.has_method("has_animation") and not bool(rig.call("has_animation", animation_name)):
		return
	rig.call("set_animation", animation_name)
	_frame = 0.0


func _cycle_animation() -> void:
	var names: Array = rig.call("get_animation_names")
	if names.is_empty():
		return
	var current := str(rig.get("current_animation"))
	var index := names.find(current)
	_play(str(names[(index + 1) % names.size()]))


func _set_opacity(value: float) -> void:
	_opacity = clampf(value, 0.0, 1.0)
	if rig.has_method("set_sprite_opacity"):
		rig.call("set_sprite_opacity", _opacity)


func _update_label() -> void:
	if rig == null or _label == null:
		return
	var summary: Dictionary = {}
	var summary_value: Variant = rig.call("get_runtime_summary")
	if summary_value is Dictionary:
		summary = summary_value as Dictionary
	_label.text = "\n".join([
		"OATHWAKE MONSTER LAB — %s   (nenhum dado de Juno/Dummy carregado)" % str(summary.get("profile_label", _profile)),
		"animação: %s      disponíveis: %s" % [
			str(summary.get("animation", "")), str(summary.get("animations", []))],
		"direção: %.1f°   índice 16-dir: %d" % [
			float(summary.get("facing_degrees", 0.0)), int(summary.get("facing_index_16", 0))],
		"peças visíveis: %d de %d      opacidade: %d%%" % [
			int(summary.get("visible_pieces", 0)), int(summary.get("sprite_piece_count", 0)),
			roundi(_opacity * 100.0)],
		"%s   quadro %.0f" % ["PAUSADO" if _paused else "rodando", _frame],
		"WASD gira · Q/E gira 22.5° · 1/2/3 anim · Tab cicla · O/P opacidade · F1 debug · Espaço pausa · [ ] quadro",
		"7 placeholder · 8 golem pedra · 9 golem jade",
	])
