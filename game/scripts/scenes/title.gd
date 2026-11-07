extends Control
## Pantalla de título: Nueva partida, Unirse a una partida (experimental), Opciones, Salir.

var _buttons: Array[Button] = []
var _status: Label
var _error: Label
var _join: Control  ## panel "Unirse a una partida"
var _join_ip: LineEdit
var _join_name: LineEdit
var _join_list: VBoxContainer
var _join_msg: Label


func _ready() -> void:
	theme = UiKit.theme()
	UiKit.background(self)
	var col: VBoxContainer = UiKit.centered_column(self, 14)

	var title: Label = UiKit.label("Leyendas SV", 64, UiKit.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub: Label = UiKit.label("El Último Rezo de las Ánimas", 30)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	var town: Label = UiKit.label("San Jacinto de las Ánimas · víspera del Día de los Difuntos", 18, UiKit.MUTED)
	town.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(town)
	col.add_child(Control.new())  # aire

	for spec: Array in [["Nueva partida", _on_new_game], ["Unirse a una partida", _on_join_open],
			["Opciones", _on_options], ["Salir", _on_quit]]:
		var b: Button = UiKit.button(spec[0], spec[1])
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(b)
		_buttons.append(b)

	_error = UiKit.label("", 18, UiKit.DANGER)
	_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.custom_minimum_size = Vector2(640, 0)
	col.add_child(_error)

	_status = UiKit.label("", 16, UiKit.MUTED)
	_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	add_child(_status)
	_buttons[0].grab_focus()
	Sound.play_ambience("title")
	_build_join()
	_check_backend()
	for arg: String in OS.get_cmdline_user_args():  # -- --join=auto (o el id de una partida)
		if arg.begins_with("--join="):
			_auto_join(arg.substr(7))


func _check_backend() -> void:
	_status.text = "Backend: %s · comprobando…" % Backend.mode
	var r: Dictionary = await Backend.health()
	if not is_inside_tree():
		return
	if r["ok"]:
		var d: Dictionary = r["data"]
		_status.text = "Backend: %s · %s · modelo %s%s" % [
			Backend.mode, d.get("status", "?"), d.get("model", "?"),
			"" if bool(d.get("warm", false)) else " (calentando)"]
	else:
		_status.text = "Backend: %s · sin conexión (%s)" % [Backend.mode, r["error"].get("detail", "")]


func _set_enabled(enabled: bool) -> void:
	for b: Button in _buttons:
		b.disabled = not enabled


func _on_new_game() -> void:
	_set_enabled(false)
	_error.text = ""
	var r: Dictionary = await Backend.new_session()
	if r["ok"]:
		SceneRouter.go(SceneRouter.TOWN)
	else:
		_error.text = "No se pudo crear la partida: %s\nRevisa Opciones o usa el modo mock." % r["error"].get("detail", "")
		_set_enabled(true)


# ---------- unirse a una partida (experimental) ----------

func _build_join() -> void:
	_join = Control.new()
	_join.set_anchors_preset(Control.PRESET_FULL_RECT)
	_join.visible = false
	add_child(_join)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.02, 0.01, 0.04, 0.97)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_join.add_child(shade)
	var col: VBoxContainer = UiKit.centered_column(_join, 12)
	col.add_child(UiKit.label("Unirse a una partida", 36, UiKit.ACCENT))
	col.add_child(UiKit.label("IP de la computadora con el motor (Tailscale o red local)", 18, UiKit.MUTED))
	_join_ip = LineEdit.new()
	_join_ip.placeholder_text = "100.79.57.108"
	# Con servidor.txt (zip para todos) va la dirección pública completa; si no, la IP de siempre.
	if Backend.server_url != "":
		_join_ip.text = Backend.server_url
	else:
		_join_ip.text = host_of(Backend.base_url) if Backend.mode == "http" else ""
	_join_ip.custom_minimum_size = Vector2(560, 46)
	_join_ip.text_submitted.connect(func(_t: String) -> void: _on_join_search())  # Enter busca
	col.add_child(_join_ip)
	col.add_child(UiKit.label("Tu nombre", 18, UiKit.MUTED))
	_join_name = LineEdit.new()
	_join_name.placeholder_text = Presence.default_name()
	_join_name.text = Presence.player_name
	_join_name.max_length = 20
	_join_name.custom_minimum_size = Vector2(560, 46)
	_join_name.text_submitted.connect(func(_t: String) -> void: _on_join_search())
	col.add_child(_join_name)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(UiKit.button("Buscar partidas", _on_join_search, 270))
	row.add_child(UiKit.button("Volver", _on_join_close, 270))
	col.add_child(row)
	_join_msg = UiKit.label("", 18, UiKit.MUTED)
	_join_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_join_msg.custom_minimum_size = Vector2(560, 0)
	col.add_child(_join_msg)
	_join_list = VBoxContainer.new()
	_join_list.add_theme_constant_override("separation", 8)
	col.add_child(_join_list)


## "http://100.79.57.108:8000" -> "100.79.57.108"
static func host_of(url: String) -> String:
	var u: String = url.trim_prefix("http://").trim_prefix("https://")
	return u.get_slice("/", 0).get_slice(":", 0)


## "100.79.57.108" -> "http://100.79.57.108:8000" (ver Backend.normalize_url).
static func url_for(ip_or_url: String) -> String:
	return Backend.normalize_url(ip_or_url)


static func game_label(g: Dictionary) -> String:
	var n: int = (g.get("players", []) as Array).size()
	return "Partida de %s · Acto %s · %s · %d jugador%s" % [
		g.get("host", "?"), TownLayout.act_roman(int(g.get("act", 1))),
		GameState.format_clock(str(g.get("clock", "23:47"))), n, "" if n == 1 else "es"]


func _on_join_close() -> void:
	_join.visible = false
	_buttons[1].grab_focus()


func _on_join_open() -> void:
	_error.text = ""
	_join.visible = true
	_join_msg.text = "Escribe la IP y busca las partidas abiertas."
	_join_ip.grab_focus()
	if Backend.server_url != "":
		_on_join_search()  # el zip ya trae el servidor: busca solo


func _on_join_search() -> void:
	for c: Node in _join_list.get_children():
		c.queue_free()
	if url_for(_join_ip.text) == "":
		_join_msg.text = "Escribe la IP de la computadora con el motor (por ejemplo 100.79.57.108)."
		return
	Backend.set_mode("http")
	Backend.set_base_url(url_for(_join_ip.text))
	Presence.player_name = _join_name.text.strip_edges()
	Presence.enabled = true
	Backend.save_settings()
	Presence.save_settings()
	_join_msg.text = "Buscando en %s…" % Backend.base_url
	var r: Dictionary = await Backend.lobby()
	if not is_inside_tree():
		return
	if not r["ok"]:
		_join_msg.text = "No se pudo conectar: %s" % r["error"].get("detail", "")
		return
	var games: Array = r["data"].get("games", [])
	if games.is_empty():
		_join_msg.text = "No hay partidas abiertas. El anfitrión debe empezar una (Nueva partida) y estar en el pueblo."
		return
	_join_msg.text = "Elige la partida:"
	for g: Dictionary in games:
		var sid: String = str(g.get("session_id", ""))
		var b: Button = UiKit.button(game_label(g), func() -> void: _join_game(sid), 560)
		_join_list.add_child(b)
	(_join_list.get_child(0) as Button).grab_focus()


func _join_game(session_id: String) -> void:
	_join_msg.text = "Entrando…"
	var r: Dictionary = await Backend.join_session(session_id)
	if not is_inside_tree():
		return
	if r["ok"]:
		GameState.bell_rung = true  # la campanada de inicio ya sonó en la partida del anfitrión
		SceneRouter.go(SceneRouter.TOWN)
	else:
		_join_msg.text = "No se pudo entrar: %s" % r["error"].get("detail", "")


## Prueba automática: -- --join=auto entra a la primera partida abierta (o a la del id dado).
func _auto_join(which: String) -> void:
	var r: Dictionary = await Backend.lobby()
	var games: Array = r["data"].get("games", []) if r["ok"] else []
	for g: Dictionary in games:
		if which == "auto" or str(g.get("session_id", "")) == which:
			_join_game(str(g["session_id"]))
			return
	_error.text = "No encontré una partida abierta para unirme (%s)." % which


func _on_options() -> void:
	SceneRouter.go(SceneRouter.OPTIONS)


func _on_quit() -> void:
	Sound.quit_clean()
