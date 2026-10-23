extends Control
## Демо-сцена: скриншот игры, кнопка радиального меню, эффекты применения и переключатель стилей.
## Мышь работает как палец (input_devices/pointing/emulate_touch_from_mouse).

const MenuScript := preload("res://radial_menu/radial_skill_menu.gd")
const FxScript := preload("res://fx_layer.gd")
const SELF_SKILLS := [3, 4, 8]
const ENEMY_POS := Vector2(478, 300)
const PLAYER_POS := Vector2(637, 318)
const HOW_TEXT := {"tap": "касанием", "hold": "удержанием", "flick": "взмахом"}

var menu: MenuScript
var fx: FxScript
var title: Label
var log_label: Label
var hold_button: Button
var _log := PackedStringArray()
var _hold_steps := PackedFloat32Array([0.0, 0.15, 0.3])
var _hold_index := 0


func _ready() -> void:
	var bg := TextureRect.new()
	bg.texture = load("res://assets/game-bg.jpg")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)

	fx = FxScript.new()
	add_child(fx)
	fx.set_anchors_preset(Control.PRESET_FULL_RECT)

	menu = MenuScript.new()
	for i in 10:
		menu.icons.append(load("res://assets/icons/skill_%02d.png" % (i + 1)))
	add_child(menu)
	menu.skill_activated.connect(_on_skill_activated)
	menu.skill_refused.connect(_on_skill_refused)

	_build_toolbar()
	_build_log()
	_apply_style(0, false)


func _build_toolbar() -> void:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.043, 0.05, 0.8)
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(20)
	sb.set_content_margin_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	row.add_child(_button("‹", func() -> void: _apply_style(int(menu.style) - 1)))
	title = Label.new()
	title.custom_minimum_size = Vector2(230, 0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)
	row.add_child(_button("›", func() -> void: _apply_style(int(menu.style) + 1)))
	hold_button = _button("", _cycle_hold)
	row.add_child(hold_button)
	var zones := CheckButton.new()
	zones.text = "Зоны"
	zones.focus_mode = Control.FOCUS_NONE
	zones.toggled.connect(func(on: bool) -> void: menu.show_zones = on)
	row.add_child(zones)
	add_child(panel)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 8)
	_update_hold_text()


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(40, 36)
	b.pressed.connect(cb)
	return b


func _build_log() -> void:
	log_label = Label.new()
	log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	log_label.add_theme_font_size_override("font_size", 15)
	log_label.add_theme_color_override("font_color", Color("e6f0ff"))
	log_label.add_theme_color_override("font_outline_color", Color.BLACK)
	log_label.add_theme_constant_override("outline_size", 5)
	add_child(log_label)
	log_label.anchor_left = 0.0
	log_label.anchor_right = 0.0
	log_label.anchor_top = 1.0
	log_label.anchor_bottom = 1.0
	log_label.offset_left = 14.0
	log_label.offset_right = 520.0
	log_label.offset_top = -140.0
	log_label.offset_bottom = -12.0


## preview — сразу открыть меню, чтобы увидеть стиль.
func _apply_style(i: int, preview: bool = true) -> void:
	menu.style = posmod(i, MenuScript.STYLE_NAMES.size()) as MenuScript.Style
	title.text = "%d/10  %s" % [int(menu.style) + 1, MenuScript.STYLE_NAMES[int(menu.style)]]
	if preview:
		menu.open_menu()


func _cycle_hold() -> void:
	_hold_index = (_hold_index + 1) % _hold_steps.size()
	menu.hold_delay = _hold_steps[_hold_index]
	_update_hold_text()


func _update_hold_text() -> void:
	var v := _hold_steps[_hold_index]
	hold_button.text = "Удержание: сразу" if v <= 0.0 else "Удержание: %.2f с" % v


func _say(text: String) -> void:
	_log.append(text)
	if _log.size() > 4:
		_log.remove_at(0)
	log_label.text = "\n".join(_log)


func _on_skill_activated(index: int, how: String) -> void:
	_say("[Система] Вы применили «%s» %s" % [menu.skill_names[index], HOW_TEXT.get(how, how)])
	var is_self := index in SELF_SKILLS
	var value := randi_range(150, 270) if is_self else randi_range(90, 260)
	var text := ("+%d" if is_self else "−%d") % value
	fx.spawn(_image_to_screen(PLAYER_POS if is_self else ENEMY_POS), menu.skill_colors[index], text, is_self)


func _on_skill_refused(index: int, seconds_left: float) -> void:
	_say("[Система] «%s» ещё перезаряжается: %d с" % [menu.skill_names[index], ceili(seconds_left)])


## Точка на скриншоте (1280×576) → точка на экране с учётом растяжения фона «cover».
func _image_to_screen(p: Vector2) -> Vector2:
	var tex := Vector2(1280, 576)
	var s := maxf(size.x / tex.x, size.y / tex.y)
	return (size - tex * s) * 0.5 + p * s


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_RIGHT:
		_apply_style(int(menu.style) + 1)
	elif key.keycode == KEY_LEFT:
		_apply_style(int(menu.style) - 1)
