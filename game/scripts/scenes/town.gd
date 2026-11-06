extends Control
## Pueblo PROVISIONAL de la fase A1: muestra el WorldState y los retratos de los
## testigos para comprobar Backend + GameState + ContentDB. A2 lo reemplaza por
## el pueblo top-down con TileMapLayer.

var _hud: Label
var _grid: GridContainer


func _ready() -> void:
	theme = UiKit.theme()
	UiKit.background(self)

	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	margin.add_child(col)

	var top: HBoxContainer = HBoxContainer.new()
	var town_name: Label = UiKit.label(str(ContentDB.world.get("town", "San Jacinto")), 34, UiKit.ACCENT)
	town_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(town_name)
	top.add_child(UiKit.button("Volver al título", _on_back, 220))
	col.add_child(top)

	_hud = UiKit.label("", 22)
	col.add_child(_hud)
	col.add_child(UiKit.label("Testigos (pueblo provisional de A1; el pueblo jugable llega en A2)", 16, UiKit.MUTED))

	_grid = GridContainer.new()
	_grid.columns = 6
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 16)
	col.add_child(_grid)

	GameState.world_changed.connect(_refresh)
	_refresh(GameState.world)


func _refresh(_state: Dictionary) -> void:
	_hud.text = "Acto %d · %s · Evidencias: %d · Deducciones: %d · Backend: %s" % [
		GameState.act(), GameState.clock_text(), GameState.evidence_ids().size(),
		(GameState.world.get("deductions", []) as Array).size(), Backend.mode]
	for c: Node in _grid.get_children():
		c.queue_free()
	for n: Dictionary in GameState.world.get("npcs", []):
		_grid.add_child(_card(n))


func _card(n: Dictionary) -> Control:
	var id: String = n["id"]
	var box: VBoxContainer = VBoxContainer.new()
	var pic: TextureRect = TextureRect.new()
	pic.texture = Portraits.get_texture(id, "neutral")
	pic.custom_minimum_size = Vector2(176, 176)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(pic)
	box.add_child(UiKit.label(ContentDB.display_name(id), 18))
	box.add_child(UiKit.label(GameState.level_name(str(n["level"])), 15, UiKit.MUTED))
	box.add_child(UiKit.label("Confianza %d · Miedo %d" % [int(n["trust"]), int(n["fear"])], 15, UiKit.MUTED))
	return box


func _on_back() -> void:
	SceneRouter.go(SceneRouter.TITLE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SceneRouter.go(SceneRouter.TITLE)
