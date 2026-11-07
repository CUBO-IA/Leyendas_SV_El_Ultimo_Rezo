class_name Journal
extends CanvasLayer
## Diario del investigador (Tab): Evidencias, Deducciones, Testigos y Línea de tiempo.
##     var wants_accuse: bool = await journal.open()
## Todo sale de lo que el jugador ya descubrió (GameState); el cliente no trae
## textos del caso escritos de antemano.

signal closed(wants_accuse: bool)

const TABS: Array[String] = ["Evidencias", "Deducciones", "Testigos", "Línea de tiempo"]
const CATEGORY: Dictionary = {"objeto": "Objeto", "documento": "Documento", "testimonio": "Testimonio"}
const TIME_RE := "\\b(1[0-2]|[1-9]):([0-5][0-9])\\b"

var _root: Control
var _tabs: TabContainer
var _ev_list: ItemList
var _ev_detail: RichTextLabel
var _ded_text: RichTextLabel
var _wit_list: ItemList
var _wit_portrait: TextureRect
var _wit_detail: RichTextLabel
var _timeline: RichTextLabel
var _accuse_btn: Button
var _ev_ids: Array[String] = []
var _wit_ids: Array[String] = []


func _ready() -> void:
	layer = 9
	_build()
	_root.visible = false


func is_open() -> bool:
	return _root.visible


func open(tab: int = 0) -> bool:
	refresh()
	_tabs.current_tab = clampi(tab, 0, TABS.size() - 1)
	_root.visible = true
	_tabs.get_tab_bar().grab_focus()
	return await closed


func close(wants_accuse: bool = false) -> void:
	if not _root.visible:
		return
	_root.visible = false
	closed.emit(wants_accuse)


func _input(event: InputEvent) -> void:
	if not _root.visible:
		return
	if event.is_action_pressed("journal") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()


func refresh() -> void:
	_refresh_evidence()
	_refresh_deductions()
	_refresh_witnesses()
	_timeline.text = timeline_bbcode()
	var can: bool = GameState.can_accuse()
	_accuse_btn.disabled = not can
	_accuse_btn.tooltip_text = "" if can else "Todavía no sabes lo suficiente para acusar."


# ---------- pestañas ----------

func _refresh_evidence() -> void:
	_ev_list.clear()
	_ev_ids = GameState.evidence_ids()
	for id: String in _ev_ids:
		_ev_list.add_item(ContentDB.display_name(id))
	if _ev_ids.is_empty():
		_ev_detail.text = "[color=#9a90a8]Todavía no tienes evidencias. Examina lo que brilla en el pueblo (E).[/color]"
	else:
		_ev_list.select(0)
		_show_evidence(0)


func _show_evidence(i: int) -> void:
	var e: Dictionary = ContentDB.evidence_item(_ev_ids[i])
	_ev_detail.text = "[font_size=26][color=#e08a2c]%s[/color][/font_size]\n[color=#9a90a8]%s[/color]\n\n%s" % [
		_esc(str(e.get("name", ""))), CATEGORY.get(e.get("category", ""), ""), _esc(str(e.get("description", "")))]


func _refresh_deductions() -> void:
	var ds: Array = GameState.world.get("deductions", [])
	if ds.is_empty():
		_ded_text.text = "[color=#9a90a8]Todavía no has deducido nada. Presenta evidencias a los testigos para pillarles las mentiras.[/color]"
		return
	var lines: PackedStringArray = []
	for d: Dictionary in ds:
		lines.append("[color=#e08a2c]▸[/color] " + _esc(str(d.get("text", ""))))
	_ded_text.text = "\n\n".join(lines)


func _refresh_witnesses() -> void:
	_wit_list.clear()
	_wit_ids.clear()
	for n: Dictionary in GameState.world.get("npcs", []):
		_wit_ids.append(n["id"])
		var name_text: String = ContentDB.display_name(n["id"])
		if not bool(n.get("met", false)):
			name_text += "  (sin hablar)"
		_wit_list.add_item(name_text)
	if not _wit_ids.is_empty():
		_wit_list.select(0)
		_show_witness(0)


func _show_witness(i: int) -> void:
	var id: String = _wit_ids[i]
	var n: Dictionary = GameState.npc(id)
	var w: Dictionary = ContentDB.witness(id)
	_wit_portrait.texture = Portraits.get_texture(id, "neutral")
	var prof: Dictionary = ContentDB.profile(id)
	var head: String = "[font_size=24][color=#e08a2c]%s[/color][/font_size] · %s\n" % [
		_esc(str(w.get("name", id))), _esc(ContentDB.role_line(id))]
	if prof.has("bio"):
		head += "[color=#9a90a8]%s. %s[/color]\n" % [_esc(str(prof.get("full_name", ""))), _esc(str(prof["bio"]))]
	head += "Testimonio: [b]%s[/b] · Confianza %d/10 · Miedo %d/10\n" % [
		GameState.level_name(str(n.get("level", "inicial"))), int(n.get("trust", 0)), int(n.get("fear", 0))]
	var lines: PackedStringArray = []
	for line: Dictionary in GameState.transcript(id):
		match str(line["who"]):
			"player":
				lines.append("[color=#9a90a8]Tú: %s[/color]" % _esc(str(line["text"])))
			"npc":
				lines.append("[color=#e08a2c]%s:[/color] %s" % [_esc(str(w.get("name", id))), _esc(str(line["text"]))])
			_:
				lines.append("[color=#b58fe0][i]%s[/i][/color]" % _esc(str(line["text"])))
	if lines.is_empty():
		lines.append("[color=#9a90a8]Aún no hablas con %s. Lo encuentras en: %s.[/color]" % [
			_esc(str(w.get("name", id))), ContentDB.display_name(str(w.get("location", "")))])
	_wit_detail.text = head + "\n" + "\n".join(lines)


## Línea de tiempo: cada hora que aparece en tus evidencias o deducciones,
## ordenada de la noche hacia la madrugada.
func timeline_entries() -> Array[Dictionary]:
	var re: RegEx = RegEx.create_from_string(TIME_RE)
	var out: Array[Dictionary] = []
	var sources: Array[Dictionary] = []
	for id: String in GameState.evidence_ids():
		var e: Dictionary = ContentDB.evidence_item(id)
		sources.append({"source": str(e.get("name", id)), "text": str(e.get("description", ""))})
	for d: Dictionary in GameState.world.get("deductions", []):
		sources.append({"source": "Deducción", "text": str(d.get("text", ""))})
	for s: Dictionary in sources:
		var seen: Dictionary = {}
		for m: RegExMatch in re.search_all(s["text"]):
			var h: int = int(m.get_string(1))
			var key: int = (24 if h == 12 else h + 12) * 60 + int(m.get_string(2))  # noche -> madrugada
			if seen.has(key):
				continue
			seen[key] = true
			out.append({"key": key, "time": m.get_string(0), "source": s["source"],
				"text": _sentence_with(s["text"], m.get_string(0))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["key"]) < int(b["key"]))
	return out


## La frase del texto que contiene la hora (sin cortar en "p. m.").
static func _sentence_with(text: String, time: String) -> String:
	# "p. m." lleva puntos que no son fin de frase: se cambian por un marcador sin punto.
	var norm: String = text.replace("p. m.", "p·m·").replace("a. m.", "a·m·")
	var i: int = norm.find(time)
	if i < 0:
		return text
	var start: int = norm.rfind(". ", i)
	start = 0 if start < 0 else start + 2
	var end: int = norm.find(". ", i)
	end = norm.length() if end < 0 else end + 1
	var s: String = norm.substr(start, end - start).strip_edges().lstrip("«").rstrip("»")
	return s.replace("p·m·", "p. m.").replace("a·m·", "a. m.")


func timeline_bbcode() -> String:
	var entries: Array[Dictionary] = timeline_entries()
	if entries.is_empty():
		return "[color=#9a90a8]A las 11:47 p. m. se fue la luz en todo San Jacinto. Las horas que descubras aparecerán aquí, en orden.[/color]"
	var lines: PackedStringArray = []
	for e: Dictionary in entries:
		var h: int = int(str(e["time"]).get_slice(":", 0))
		var suffix: String = "a. m." if h == 12 else "p. m."
		lines.append("[font_size=22][color=#e08a2c]%s %s[/color][/font_size]  [color=#9a90a8]%s[/color]\n%s" % [
			e["time"], suffix, _esc(str(e["source"])), _esc(str(e["text"]))])
	return "\n\n".join(lines)


static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


# ---------- construcción ----------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiKit.theme()
	add_child(_root)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.03, 0.02, 0.06, 0.9)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	_root.add_child(margin)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var top: HBoxContainer = HBoxContainer.new()
	var title: Label = UiKit.label("Diario del investigador", 32, UiKit.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_accuse_btn = UiKit.button("Acusar a una entidad", func() -> void: close(true), 300)
	top.add_child(_accuse_btn)
	top.add_child(UiKit.button("Cerrar (Tab)", func() -> void: close(), 180))
	col.add_child(top)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 20)
	col.add_child(_tabs)

	# Evidencias
	var ev: HBoxContainer = _tab(TABS[0])
	_ev_list = _list(ev, 340)
	_ev_list.item_selected.connect(_show_evidence)
	_ev_detail = _rich(ev)
	# Deducciones
	var ded: HBoxContainer = _tab(TABS[1])
	_ded_text = _rich(ded)
	# Testigos
	var wit: HBoxContainer = _tab(TABS[2])
	_wit_list = _list(wit, 300)
	_wit_list.item_selected.connect(_show_witness)
	var wcol: VBoxContainer = VBoxContainer.new()
	wcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wit.add_child(wcol)
	_wit_portrait = TextureRect.new()
	_wit_portrait.custom_minimum_size = Vector2(150, 150)
	_wit_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wit_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_wit_portrait.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	wcol.add_child(_wit_portrait)
	_wit_detail = _rich(wcol)
	# Línea de tiempo
	var tl: HBoxContainer = _tab(TABS[3])
	_timeline = _rich(tl)


func _tab(title: String) -> HBoxContainer:
	var box: HBoxContainer = HBoxContainer.new()
	box.name = title
	box.add_theme_constant_override("separation", 18)
	_tabs.add_child(box)
	return box


func _list(parent: Control, width: int) -> ItemList:
	var l: ItemList = ItemList.new()
	l.custom_minimum_size = Vector2(width, 0)
	l.add_theme_font_size_override("font_size", 19)
	parent.add_child(l)
	return l


func _rich(parent: Control) -> RichTextLabel:
	var r: RichTextLabel = RichTextLabel.new()
	r.bbcode_enabled = true
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r.add_theme_font_size_override("normal_font_size", 19)
	r.add_theme_font_size_override("bold_font_size", 19)
	r.add_theme_font_size_override("italics_font_size", 18)
	r.add_theme_color_override("default_color", UiKit.INK)
	parent.add_child(r)
	return r
