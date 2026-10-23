class_name RadialSkillMenu
extends Control
## Радиальное меню на 10 умений: одна светящаяся кнопка вместо панели быстрого доступа.
##
## Касание кнопки — меню остаётся открытым, умение выбирается тапом.
## Удержание и движение пальца — умение выбирается направлением, отпускание применяет его.
## Вернуть палец в центр и отпустить — отмена.
## Узел растягивается на весь родительский Control; все размеры заданы для экрана высотой 576.

signal skill_activated(index: int, how: String) # how: "tap", "hold" или "flick"
signal skill_refused(index: int, seconds_left: float)
signal menu_opened(sticky: bool)
signal menu_closed

enum Style {
	BRONZE, SECTOR, FAN, ARCANE, HEX, NEON, STAR, PARCHMENT, DIAL, EMBER,
	HALO, ARCH, FLOWER, ORBIT, SHIELD, GLASS, GEARS, BUBBLES, INK, CLEAN,
}
enum Mode { CLOSED, PRESS, DRAG, STICKY, CLOSING }

const STYLE_NAMES := [
	"Бронзовый круг", "Колесо секторов", "Веер над кнопкой", "Магический круг", "Соты",
	"Неон", "Королевская звезда", "Пергамент", "Циферблат", "Кузнечное пламя",
	"Ореол", "Каменная арка", "Цветок", "Орбита", "Щит викинга",
	"Витраж", "Шестерни", "Пузыри", "Тушь", "Минимал",
]
const COUNT := 10
const RING := 0
const ARC := 1
const STAR := 2
const GAUGE := 3
const ELLIPSE := 4
const TIERS := 5
const SH_CIRCLE := 0
const SH_DIAMOND := 1
const SH_HEX := 2
const SH_RSQ := 3
const SH_SQ := 4
const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]

const BRONZE_MID := Color("b07a35")
const BRONZE_HI := Color("f6d896")
const BRONZE_LO := Color("5a3a14")
const GOLD_MID := Color("ffd25e")
const GOLD_HI := Color("fff4c8")
const GOLD_LO := Color("c58a1c")
const SILVER_MID := Color("aab0b9")
const SILVER_HI := Color("ffffff")
const SILVER_LO := Color("4b5059")

@export var style: Style = Style.BRONZE:
	set(value):
		style = value
		_reset_style_state()
@export var icons: Array[Texture2D] = []
@export var skill_names: PackedStringArray = [
	"Молния", "Огненный шар", "Ледяное копьё", "Исцеление", "Щит веры",
	"Вихрь", "Ядовитое облако", "Метеор", "Святой свет", "Теневой удар",
]
@export var skill_mp: PackedInt32Array = [24, 36, 30, 40, 28, 22, 34, 60, 45, 26]
@export var skill_cooldowns: PackedFloat32Array = [4, 6, 5, 8, 12, 5, 7, 15, 9, 4]
@export var skill_colors: PackedColorArray = [
	Color("ffe24d"), Color("ff7a2b"), Color("62d6ff"), Color("72f08f"), Color("ffd27a"),
	Color("6ff5d2"), Color("b77bff"), Color("ff5236"), Color("fff1b3"), Color("a184ff"),
]
## Сколько держать палец, прежде чем меню появится (0 — сразу при нажатии).
@export_range(0.0, 0.5, 0.05) var hold_delay := 0.0
## Радиус мёртвой зоны в единицах дизайна (экран высотой 576).
@export_range(8.0, 80.0, 1.0) var dead_zone := 26.0
@export_range(0.5, 2.0, 0.05) var size_mul := 1.0
## Не закрывать меню после выбора умения.
@export var keep_open := false
## Самому запускать перезарядку из skill_cooldowns при применении.
@export var auto_cooldown := true
## Рисовать мёртвую зону и границы секторов.
@export var show_zones := false
## Расстояние от нижнего края до центра кнопки, в единицах дизайна (-1 — как задано в стиле).
@export var trigger_bottom := -1.0
@export var vibrate := true


class Layout:
	var kind := 0
	var r := 142.0
	var r2 := 0.0
	var slot := 58.0
	var start := -PI / 2.0
	var sweep := 0.0
	var on_trigger := false
	var ext := 192.0
	var wext := 0.0
	var lift := 0.0
	var tol := -1.0
	var hit := Vector2(66, 204)
	var r_in := 0.0
	var r_out := 0.0
	var open_t := 0.26
	var close_t := 0.17
	var dim := 0.3
	var tb := 50.0
	var rx := 0.0
	var ry := 0.0
	var pts := PackedVector2Array()
	var tap_r := 34.0

	func _init(p_kind: int, p_r: float, p_slot: float, p_ext: float, p_hit: Vector2, p_open: float, p_close: float, p_dim: float) -> void:
		kind = p_kind
		r = p_r
		slot = p_slot
		ext = p_ext
		hit = p_hit
		open_t = p_open
		close_t = p_close
		dim = p_dim


class Ember:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var life := 0.0
	var max_life := 1.0
	var size := 2.0


var _layouts: Array = []
var _mode: Mode = Mode.CLOSED
var _raw := 0.0
var _open_at := 0.0
var _close_at := 0.0
var _close_from := 0.0
var _hover := -1
var _hover_t := PackedFloat32Array()
var _any := 0.0
var _cursor := Vector2.ZERO
var _has_cursor := false
var _p0 := Vector2.ZERO
var _touch := -1
var _left_dead := false
var _from_sticky := false
var _sticky_drag := false
var _press_at := 0.0
var _on_trig := false
var _pressed := 0.0
var _cast_index := -1
var _cast_at := -100.0
var _shake_at := PackedFloat32Array()
var _cd_end := PackedFloat32Array()
var _cd_total := PackedFloat32Array()
var _time := 0.0
var _interacted := false

var _s := 1.0
var _center := Vector2.ZERO
var _trig := Vector2.ZERO
var _mx := Transform2D.IDENTITY
var _cur := Transform2D.IDENTITY
var _ga := 1.0
var _ang := PackedFloat32Array()
var _rad := PackedFloat32Array()
var _par := PackedFloat32Array()
var _pos := PackedVector2Array()

var _needle := -PI / 2.0
var _needle_v := 0.0
var _embers: Array[Ember] = []
var _ember_acc := 0.0
var _parch_spots := PackedVector3Array()
var _orbit_stars := PackedVector3Array()
var _glow_tex: GradientTexture2D
var _font: Font


func _init() -> void:
	_layouts = _make_layouts()
	_hover_t.resize(COUNT)
	_shake_at.resize(COUNT)
	_shake_at.fill(-100.0)
	_cd_end.resize(COUNT)
	_cd_total.resize(COUNT)
	_cd_total.fill(1.0)
	_ang.resize(COUNT)
	_rad.resize(COUNT)
	_par.resize(COUNT)
	_pos.resize(COUNT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234567
	for k in 46:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * 170.0
		_parch_spots.append(Vector3(cos(a) * d, sin(a) * d, rng.randf_range(8.0, 34.0)))
	for k in 46:
		var a2 := fmod(k * 2.399, TAU)
		var d2 := sqrt(float((k * 7919) % 97) / 97.0)
		_orbit_stars.append(Vector3(cos(a2) * d2 * 222.0, sin(a2) * d2 * 132.0, 0.6 + float((k * 13) % 7) / 6.0))


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()
	_glow_tex = _make_glow_texture()
	_update_view()


# ---------------------------------------------------------------- public API

func open_menu() -> void:
	_interacted = true
	_open(Mode.STICKY)


func close_menu() -> void:
	_close()


func is_open() -> bool:
	return _mode == Mode.DRAG or _mode == Mode.STICKY


func start_cooldown(index: int, seconds: float) -> void:
	if index < 0 or index >= COUNT or seconds <= 0.0:
		return
	_cd_end[index] = _time + seconds
	_cd_total[index] = seconds


func cooldown_left(index: int) -> float:
	return maxf(0.0, _cd_end[index] - _time)


# ---------------------------------------------------------------- layouts

func _make_layouts() -> Array:
	var a: Array = []
	a.resize(Style.size())
	a[Style.BRONZE] = Layout.new(RING, 142, 58, 192, Vector2(66, 204), 0.26, 0.17, 0.3)
	var sector := Layout.new(RING, 124, 46, 194, Vector2(58, 204), 0.23, 0.15, 0.38)
	sector.r_in = 64.0
	sector.r_out = 184.0
	a[Style.SECTOR] = sector
	var fan := Layout.new(ARC, 206, 54, 272, Vector2(40, 250), 0.34, 0.17, 0.16)
	fan.start = PI + 0.17
	fan.sweep = PI - 0.34
	fan.on_trigger = true
	fan.wext = 245.0
	fan.tol = 0.42
	a[Style.FAN] = fan
	a[Style.ARCANE] = Layout.new(RING, 140, 60, 198, Vector2(62, 206), 0.42, 0.18, 0.42)
	a[Style.HEX] = Layout.new(RING, 140, 64, 194, Vector2(60, 204), 0.32, 0.16, 0.4)
	a[Style.NEON] = Layout.new(RING, 138, 54, 196, Vector2(58, 204), 0.28, 0.15, 0.55)
	var star := Layout.new(STAR, 112, 54, 214, Vector2(54, 214), 0.34, 0.17, 0.36)
	star.r2 = 170.0
	a[Style.STAR] = star
	a[Style.PARCHMENT] = Layout.new(RING, 138, 56, 200, Vector2(60, 206), 0.36, 0.18, 0.32)
	var dial := Layout.new(GAUGE, 146, 46, 206, Vector2(54, 212), 0.40, 0.17, 0.34)
	dial.start = 3.0 * PI / 4.0
	dial.sweep = 3.0 * PI / 2.0
	dial.lift = 164.0
	dial.tol = 0.3
	a[Style.DIAL] = dial
	a[Style.EMBER] = Layout.new(RING, 142, 54, 198, Vector2(62, 206), 0.30, 0.18, 0.36)
	# --- the menu opens around the button itself
	a[Style.HALO] = _around(Layout.new(RING, 104, 50, 172, Vector2(36, 156), 0.36, 0.17, 0.3), 142, 136)
	var arch := _around(Layout.new(ARC, 158, 42, 258, Vector2(40, 214), 0.44, 0.17, 0.26), 50, 214)
	arch.start = PI + PI / 20.0
	arch.sweep = PI * 0.9
	arch.tol = 0.4
	arch.r_in = 112.0
	arch.r_out = 204.0
	a[Style.ARCH] = arch
	var flower := _around(Layout.new(GAUGE, 116, 44, 224, Vector2(36, 180), 0.48, 0.17, 0.24), 112, 178)
	flower.start = PI * 5.0 / 6.0
	flower.sweep = PI * 4.0 / 3.0
	flower.tol = 0.26
	a[Style.FLOWER] = flower
	var orbit := _around(Layout.new(ELLIPSE, 184, 46, 172, Vector2(36, 150), 0.54, 0.18, 0.4), 136, 216)
	orbit.rx = 184.0
	orbit.ry = 104.0
	a[Style.ORBIT] = orbit
	var shield := _around(Layout.new(RING, 86, 40, 180, Vector2(36, 146), 0.38, 0.17, 0.3), 146, 140)
	shield.r_in = 38.0
	shield.r_out = 124.0
	a[Style.SHIELD] = shield
	a[Style.GLASS] = _around(Layout.new(RING, 90, 38, 188, Vector2(36, 150), 0.48, 0.17, 0.42), 150, 150)
	a[Style.GEARS] = _around(Layout.new(RING, 104, 40, 194, Vector2(36, 150), 0.56, 0.18, 0.34), 150, 196)
	var bubbles := _around(Layout.new(TIERS, 172, 50, 250, Vector2(38, 230), 0.46, 0.17, 0.28), 50, 206)
	for d in [202.5, 247.5, 292.5, 337.5]:
		bubbles.pts.append(Vector2.from_angle(deg_to_rad(d)) * 96.0)
	for d in [195.0, 225.0, 255.0, 285.0, 315.0, 345.0]:
		bubbles.pts.append(Vector2.from_angle(deg_to_rad(d)) * 172.0)
	a[Style.BUBBLES] = bubbles
	var ink := _around(Layout.new(GAUGE, 112, 42, 182, Vector2(36, 160), 0.56, 0.17, 0.22), 132, 170)
	ink.start = PI * 2.0 / 3.0
	ink.sweep = PI * 5.0 / 3.0
	ink.tol = 0.25
	a[Style.INK] = ink
	var clean := _around(Layout.new(ARC, 104, 46, 236, Vector2(36, 214), 0.38, 0.16, 0.42), 50, 200)
	clean.r2 = 166.0
	clean.start = PI + PI / 20.0
	clean.sweep = PI * 0.9
	clean.tol = 0.4
	a[Style.CLEAN] = clean
	return a


func _around(lay: Layout, tb: float, wext: float) -> Layout:
	lay.on_trigger = true
	lay.tb = tb
	lay.wext = wext
	return lay


func _layout() -> Layout:
	return _layouts[style]


func _slot_angle(lay: Layout, i: int) -> float:
	if lay.kind != ARC and lay.kind != GAUGE:
		return lay.start + i * TAU / COUNT
	return lay.start + i * lay.sweep / (COUNT - 1)


## Направление (угол вектора от точки касания) → номер умения или -1.
func _pick(a: float) -> int:
	var lay := _layout()
	if lay.kind != ARC and lay.kind != GAUGE:
		var step := TAU / COUNT
		return int(fposmod(a - lay.start + step * 0.5, TAU) / step) % COUNT
	var step2 := lay.sweep / (COUNT - 1)
	var rel := wrapf(a - (lay.start + lay.sweep * 0.5), -PI, PI) + lay.sweep * 0.5
	var tol := lay.tol if lay.tol >= 0.0 else step2 * 0.5
	if rel < -tol or rel > lay.sweep + tol:
		return -1
	return clampi(roundi(rel / step2), 0, COUNT - 1)


## Базовая позиция ячейки относительно центра меню.
func _slot_pos(lay: Layout, i: int) -> Vector2:
	if lay.kind == TIERS:
		return lay.pts[i]
	var a := _slot_angle(lay, i)
	if lay.kind == ELLIPSE:
		return Vector2(cos(a) * lay.rx, sin(a) * lay.ry)
	return Vector2.from_angle(a) * (lay.r2 if (lay.r2 > 0.0 and i % 2 == 1) else lay.r)


## Смещение пальца (в единицах дизайна) → номер умения. Два ряда выбирают ближайшую ячейку.
func _pick_vec(v: Vector2) -> int:
	var lay := _layout()
	if lay.kind == TIERS:
		var best := -1
		var bd := INF
		for i in lay.pts.size():
			var d := v.distance_to(lay.pts[i])
			if d < bd:
				bd = d
				best = i
		return best
	if lay.kind == ELLIPSE:
		return _pick(atan2(v.y / lay.ry, v.x / lay.rx))
	return _pick(v.angle())


func _band_dist(lay: Layout, v: Vector2) -> float:
	if lay.kind == ELLIPSE:
		return Vector2(v.x / lay.rx, v.y / lay.ry).length() * 100.0
	return v.length()


func _sticky_zone(p: Vector2) -> int:
	var lay := _layout()
	var v := (p - _center) / _s
	if lay.kind == TIERS:
		var k := _pick_vec(v)
		return k if v.distance_to(lay.pts[k]) <= lay.tap_r else -1
	var d := _band_dist(lay, v)
	if d < lay.hit.x or d > lay.hit.y:
		return -1
	return _pick_vec(v)


func _update_view() -> void:
	var lay := _layout()
	var lift := 0.0
	if not lay.on_trigger:
		lift = lay.lift if lay.lift > 0.0 else 44.0 + lay.ext
	var need_w := 2.0 * (lay.wext if lay.wext > 0.0 else lay.ext) + 16.0
	var tb := trigger_bottom if trigger_bottom >= 0.0 else lay.tb
	var need_h := tb + lift + lay.ext + 10.0
	_s = clampf(minf(size.y / 576.0, minf(size.x / need_w, size.y / need_h)), 0.3, 1.7) * size_mul
	_trig = Vector2(size.x * 0.5, size.y - tb * _s)
	_center = _trig - Vector2(0.0, lift * _s)
	if not lay.on_trigger:
		_center.y = maxf(_center.y, lay.ext * _s + 4.0)
	_mx = Transform2D(0.0, Vector2(_s, _s), 0.0, _center)
	for i in COUNT:
		var q := _slot_pos(lay, i)
		_pos[i] = q
		_par[i] = _slot_angle(lay, i)
		_rad[i] = q.length()
		_ang[i] = q.angle() if (lay.kind == TIERS or lay.kind == ELLIPSE) else _par[i]


func _reset_style_state() -> void:
	_mode = Mode.CLOSED
	_raw = 0.0
	_hover = -1
	_hover_t.fill(0.0)
	_touch = -1
	_has_cursor = false
	_cast_index = -1
	_needle = -PI / 2.0
	_needle_v = 0.0
	_embers.clear()
	_on_trig = false


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		var p := _to_local(st.position)
		if st.pressed:
			if _touch == -1 and _on_press(st.index, p):
				get_viewport().set_input_as_handled()
		elif st.index == _touch:
			_on_release(p)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _touch:
			_on_move(_to_local(sd.position))
			get_viewport().set_input_as_handled()


func _to_local(p: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * p


func _on_press(index: int, p: Vector2) -> bool:
	var on_trig := p.distance_to(_trig) <= 32.0 * _s * 1.35
	if _mode == Mode.CLOSED or _mode == Mode.CLOSING:
		if not on_trig:
			return false
		_touch = index
		_interacted = true
		_p0 = p
		_press_at = _time
		_left_dead = false
		_from_sticky = false
		_on_trig = true
		if hold_delay <= 0.0:
			_open(Mode.DRAG)
		else:
			_mode = Mode.PRESS
		return true
	if _mode != Mode.STICKY:
		return false
	_touch = index
	if on_trig:
		_p0 = p
		_press_at = _time
		_left_dead = false
		_from_sticky = true
		_on_trig = true
		_mode = Mode.DRAG
		_cursor = Vector2.ZERO
		_has_cursor = true
		_hover = -1
		return true
	var z := _sticky_zone(p)
	if z >= 0:
		_sticky_drag = true
		_hover = z
		_press_at = _time
		_buzz(6)
	else:
		_touch = -1
		_close()
	return true


func _on_move(p: Vector2) -> void:
	if _mode == Mode.PRESS:
		if p.distance_to(_p0) <= 10.0:
			return
		_open(Mode.DRAG)
	if _mode == Mode.DRAG:
		var v := (p - _p0) / _s
		_cursor = v
		_has_cursor = true
		var hv := -1
		if v.length() >= dead_zone:
			_left_dead = true
			hv = _pick_vec(v)
		_set_hover(hv)
	elif _mode == Mode.STICKY and _sticky_drag:
		_set_hover(_sticky_zone(p))


func _on_release(p: Vector2) -> void:
	_touch = -1
	_on_trig = false
	match _mode:
		Mode.PRESS:
			_open(Mode.STICKY)
		Mode.DRAG:
			if _hover >= 0:
				_activate(_hover, "flick" if _time - _press_at < 0.35 else "hold")
			elif not _left_dead and not _from_sticky:
				_mode = Mode.STICKY
				_has_cursor = false
				_hover = -1
				menu_opened.emit(true)
			else:
				_close()
		Mode.STICKY:
			if _sticky_drag:
				_sticky_drag = false
				var z := _sticky_zone(p)
				if z >= 0 and z == _hover:
					_activate(z, "tap")
				else:
					_hover = -1


func _set_hover(hv: int) -> void:
	if hv != _hover:
		_hover = hv
		if hv >= 0:
			_buzz(6)


func _open(mode: Mode) -> void:
	if _mode == Mode.CLOSED or _mode == Mode.CLOSING or _mode == Mode.PRESS:
		_open_at = _time - (_raw * _layout().open_t if _mode == Mode.CLOSING else 0.0)
		_hover = -1
		_cast_index = -1
		if _mode != Mode.CLOSING:
			_hover_t.fill(0.0)
	_mode = mode
	_has_cursor = mode == Mode.DRAG
	_cursor = Vector2.ZERO
	menu_opened.emit(mode == Mode.STICKY)


func _close() -> void:
	if _mode == Mode.CLOSED or _mode == Mode.CLOSING:
		return
	_mode = Mode.CLOSING
	_close_at = _time
	_close_from = _raw
	_has_cursor = false
	_sticky_drag = false
	menu_closed.emit()


func _activate(i: int, how: String) -> void:
	var left := _cd_end[i] - _time
	if left > 0.0:
		_shake_at[i] = _time
		_buzz(30)
		skill_refused.emit(i, left)
		if _mode == Mode.DRAG:
			_mode = Mode.STICKY
			_has_cursor = false
		_hover = -1
		return
	if auto_cooldown and i < skill_cooldowns.size():
		start_cooldown(i, skill_cooldowns[i])
	_buzz(18)
	_cast_index = i
	_cast_at = _time
	skill_activated.emit(i, how)
	if keep_open:
		_mode = Mode.STICKY
		_has_cursor = false
		_hover = -1
	else:
		_close()


func _buzz(ms: int) -> void:
	if vibrate:
		Input.vibrate_handheld(ms)


# ---------------------------------------------------------------- per-frame update

func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_time += delta
	var lay := _layout()
	if _mode == Mode.PRESS and _time - _press_at >= hold_delay:
		_open(Mode.DRAG)
		_buzz(12)
	if _mode == Mode.DRAG or _mode == Mode.STICKY:
		_raw = clampf((_time - _open_at) / lay.open_t, 0.0, 1.0)
	elif _mode == Mode.CLOSING:
		_raw = _close_from * (1.0 - clampf((_time - _close_at) / lay.close_t, 0.0, 1.0))
		if _raw <= 0.0:
			_mode = Mode.CLOSED
			_raw = 0.0
			_cast_index = -1
			_hover = -1
	var k := 1.0 - exp(-delta * 16.0)
	for i in COUNT:
		_hover_t[i] += ((1.0 if i == _hover else 0.0) - _hover_t[i]) * k
	_any += ((1.0 if _hover >= 0 else 0.0) - _any) * k
	_pressed += ((1.0 if _on_trig else 0.0) - _pressed) * (1.0 - exp(-delta * 30.0))
	_update_view()
	_update_style(delta)
	queue_redraw()


func _update_style(delta: float) -> void:
	if style == Style.DIAL:
		var target := -PI / 2.0
		if _hover >= 0:
			target = _ang[_hover]
		elif _has_cursor and _cursor.length() > 4.0:
			target = _cursor.angle()
		_needle_v += (wrapf(target - _needle, -PI, PI) * 170.0 - _needle_v * 15.0) * delta
		_needle += _needle_v * delta
		return
	if _mode == Mode.CLOSED or (style != Style.EMBER and style != Style.BUBBLES):
		return
	if style == Style.EMBER:
		_ember_acc += delta * 42.0 * _t()
		while _ember_acc > 1.0:
			_ember_acc -= 1.0
			var a := randf() * TAU
			_spawn_ember(Vector2.from_angle(a) * (142.0 + randf_range(-22.0, 22.0)), Vector2(randf_range(-7.0, 7.0), randf_range(-52.0, -18.0)), randf_range(0.7, 1.6), randf_range(1.4, 3.4))
		if _hover >= 0:
			var n := delta * 80.0 * _hover_t[_hover]
			var base := Vector2.from_angle(_ang[_hover]) * 142.0
			while n > 0.0:
				if n < 1.0 and randf() > n:
					break
				n -= 1.0
				_spawn_ember(base + Vector2(randf_range(-17.0, 17.0), randf_range(-17.0, 17.0)), Vector2(randf_range(-15.0, 15.0), randf_range(-100.0, -40.0)), randf_range(0.5, 1.2), randf_range(1.6, 4.0))
	else:
		_ember_acc += delta * 10.0 * _t()
		while _ember_acc > 1.0:
			_ember_acc -= 1.0
			_spawn_ember(Vector2(randf_range(-25.0, 25.0), -24.0), Vector2(0.0, randf_range(-80.0, -30.0)), randf_range(1.5, 3.0), randf_range(1.5, 4.5))
	for k in range(_embers.size() - 1, -1, -1):
		var e := _embers[k]
		e.life += delta
		if e.life > e.max_life:
			_embers.remove_at(k)
			continue
		e.pos += e.vel * delta
		if style == Style.EMBER:
			e.vel.x += randf_range(-20.0, 20.0) * delta
	while _embers.size() > 260:
		_embers.remove_at(0)


func _spawn_ember(pos: Vector2, vel: Vector2, life: float, sz: float) -> void:
	var e := Ember.new()
	e.pos = pos
	e.vel = vel
	e.max_life = life
	e.size = sz
	_embers.append(e)


# ---------------------------------------------------------------- drawing: frame

func _draw() -> void:
	var lay := _layout()
	var shown := _mode != Mode.CLOSED and _mode != Mode.PRESS
	var t := _t() if shown else 0.0
	_xf(Transform2D.IDENTITY)
	_ga = 1.0
	if shown:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.016, 0.024, 0.04, lay.dim * t))
	var on_top := shown and lay.on_trigger
	if not on_top:
		_draw_button(t)
	if shown:
		_xf(_mx)
		_ga = 1.0
		match style:
			Style.BRONZE:
				_draw_bronze()
			Style.SECTOR:
				_draw_sector()
			Style.FAN:
				_draw_fan()
			Style.ARCANE:
				_draw_arcane()
			Style.HEX:
				_draw_hex()
			Style.NEON:
				_draw_neon()
			Style.STAR:
				_draw_star()
			Style.PARCHMENT:
				_draw_parchment()
			Style.DIAL:
				_draw_dial()
			Style.EMBER:
				_draw_ember()
			Style.HALO:
				_draw_halo()
			Style.ARCH:
				_draw_arch()
			Style.FLOWER:
				_draw_flower()
			Style.ORBIT:
				_draw_orbit()
			Style.SHIELD:
				_draw_shield()
			Style.GLASS:
				_draw_glass()
			Style.GEARS:
				_draw_gears()
			Style.BUBBLES:
				_draw_bubbles()
			Style.INK:
				_draw_ink()
			Style.CLEAN:
				_draw_clean()
		_xf(_mx)
		_draw_cast_flash()
		if show_zones:
			_draw_zones()
	if on_top:
		_draw_button(t)
	_xf(Transform2D.IDENTITY)


func _draw_button(t: float) -> void:
	var ps := 1.0 - 0.08 * _pressed
	_xf(Transform2D(0.0, Vector2(_s * ps, _s * ps), 0.0, _trig))
	_draw_trigger(t)
	_xf(Transform2D(0.0, Vector2(_s, _s), 0.0, _trig))
	_ga = 1.0
	_hold_ring()
	if not _interacted:
		_draw_hint()


func _t() -> float:
	if _mode == Mode.CLOSING:
		return -(cos(PI * _raw) - 1.0) * 0.5
	return 1.0 - pow(1.0 - _raw, 3.0)


func _closing() -> bool:
	return _mode == Mode.CLOSING


func _out_cubic(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


func _out_back(x: float, k: float = 1.70158) -> float:
	var u := x - 1.0
	return 1.0 + (k + 1.0) * u * u * u + k * u * u


func _stag(i: int, spread: float = 0.4, rank: float = -1.0) -> float:
	if _mode == Mode.CLOSING:
		return _raw
	var r := rank if rank >= 0.0 else float(i) / (COUNT - 1)
	return clampf((_raw - spread * r) / (1.0 - spread), 0.0, 1.0)


func _order() -> PackedInt32Array:
	var o := PackedInt32Array()
	for i in COUNT:
		if i != _hover:
			o.append(i)
	if _hover >= 0:
		o.append(_hover)
	return o


func _shake(i: int) -> float:
	var st := _time - _shake_at[i]
	if st >= 0.42:
		return 0.0
	return sin(st * 90.0) * 6.0 * (1.0 - st / 0.42)


func _slot_alpha(p: float, mul: float = 1.7) -> float:
	return clampf(p * mul, 0.0, 1.0) * (_t() if _mode == Mode.CLOSING else 1.0)


func _skill_color(i: int) -> Color:
	return skill_colors[i] if i >= 0 and i < skill_colors.size() else Color.WHITE


func _skill_name(i: int) -> String:
	return skill_names[i] if i < skill_names.size() else "Умение %d" % (i + 1)


func _stat_line(i: int) -> String:
	var mp := skill_mp[i] if i < skill_mp.size() else 0
	var cd := skill_cooldowns[i] if i < skill_cooldowns.size() else 0.0
	return "MP %d · %d с" % [mp, roundi(cd)]


# ---------------------------------------------------------------- drawing: primitives

func _xf(t: Transform2D) -> void:
	_cur = t
	draw_set_transform_matrix(t)


func _local_xf(rot: float = 0.0, sc: float = 1.0) -> void:
	_xf(_mx * Transform2D(rot, Vector2(sc, sc), 0.0, Vector2.ZERO))


func _col(c: Color, a: float = 1.0) -> Color:
	return Color(c.r, c.g, c.b, clampf(c.a * a * _ga, 0.0, 1.0))


func _circ(p: Vector2, r: float, c: Color) -> void:
	if r > 0.05:
		draw_circle(p, r, _col(c))


func _ring(p: Vector2, r: float, w: float, c: Color, a0: float = 0.0, a1: float = TAU) -> void:
	if r <= 0.05 or w <= 0.0 or absf(a1 - a0) < 0.001:
		return
	var n := clampi(int(r * absf(a1 - a0) / 6.0), 12, 96)
	draw_arc(p, r, a0, a1, n, _col(c), w, true)


func _poly(pts: PackedVector2Array, c: Color) -> void:
	if pts.size() >= 3:
		draw_colored_polygon(pts, _col(c))


func _poly_grad(pts: PackedVector2Array, cols: PackedColorArray) -> void:
	if pts.size() < 3:
		return
	var cc := PackedColorArray()
	for c in cols:
		cc.append(_col(c))
	draw_polygon(pts, cc)


func _outline(pts: PackedVector2Array, c: Color, w: float) -> void:
	if pts.size() < 2:
		return
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, _col(c), w, true)


func _line(a: Vector2, b: Vector2, c: Color, w: float) -> void:
	draw_line(a, b, _col(c), w, true)


func _grad_line(a: Vector2, b: Vector2, w: float, c0: Color, c1: Color) -> void:
	var n := (b - a).orthogonal().normalized() * w * 0.5
	if n == Vector2.ZERO:
		return
	_poly_grad(PackedVector2Array([a + n, b + n, b - n, a - n]), PackedColorArray([c0, c1, c1, c0]))


func _dashed(a: Vector2, b: Vector2, c: Color, w: float) -> void:
	var dist := a.distance_to(b)
	if dist < 1.0:
		return
	var dir := (b - a) / dist
	var pts := PackedVector2Array()
	var d := 0.0
	while d < dist:
		pts.append(a + dir * d)
		pts.append(a + dir * minf(d + 3.0, dist))
		d += 8.0
	draw_multiline(pts, _col(c), w)


func _glow(p: Vector2, r: float, c: Color, a: float) -> void:
	if a <= 0.004 or r <= 0.0:
		return
	draw_texture_rect(_glow_tex, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, _col(c, minf(a, 1.0)))


func _bevel(p: Vector2, r: float, w: float, mid: Color, hi: Color, lo: Color) -> void:
	_ring(p, r, w, mid)
	_ring(p, r, w * 0.75, hi, PI * 0.95, PI * 1.6)
	_ring(p, r, w * 0.75, lo, -PI * 0.05, PI * 0.6)


func _rrect_pts(rc: Rect2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	r = clampf(r, 0.5, minf(rc.size.x, rc.size.y) * 0.5 - 0.25)
	var cs := PackedVector2Array([
		rc.end - Vector2(r, r), Vector2(rc.position.x + r, rc.end.y - r),
		rc.position + Vector2(r, r), Vector2(rc.end.x - r, rc.position.y + r),
	])
	for k in 4:
		for j in 6:
			pts.append(cs[k] + Vector2.from_angle(PI * 0.5 * (k + j / 5.0)) * r)
	return pts


func _shape_pts(shape: int, p: Vector2, sz: float) -> PackedVector2Array:
	var h := maxf(sz, 0.0) * 0.5
	var pts := PackedVector2Array()
	match shape:
		SH_CIRCLE:
			var n := clampi(int(h * 0.9), 16, 40)
			for k in n:
				pts.append(p + Vector2.from_angle(TAU * k / n) * h)
		SH_DIAMOND:
			pts = PackedVector2Array([p + Vector2(0, -h), p + Vector2(h, 0), p + Vector2(0, h), p + Vector2(-h, 0)])
		SH_HEX:
			for k in 6:
				pts.append(p + Vector2.from_angle(-PI / 2.0 + k * PI / 3.0) * h)
		_:
			pts = _rrect_pts(Rect2(p - Vector2(h, h), Vector2(sz, sz)), sz * (0.2 if shape == SH_RSQ else 0.1))
	return pts


func _sector_pts(r0: float, r1: float, a0: float, a1: float, gap: float, off: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 10
	for k in n + 1:
		pts.append(off + Vector2.from_angle(lerpf(a0 + gap / r1, a1 - gap / r1, float(k) / n)) * r1)
	for k in n + 1:
		pts.append(off + Vector2.from_angle(lerpf(a1 - gap / r0, a0 + gap / r0, float(k) / n)) * r0)
	return pts


## Дуга-полоса со скруглёнными концами (подложка веера и шкалы).
func _band_pts(r: float, w: float, a0: float, a1: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var hw := w * 0.5
	var n := maxi(8, int(absf(a1 - a0) * r / 8.0))
	for k in n + 1:
		pts.append(Vector2.from_angle(lerpf(a0, a1, float(k) / n)) * (r + hw))
	var e1 := Vector2.from_angle(a1) * r
	for k in range(1, 8):
		pts.append(e1 + Vector2.from_angle(a1 + PI * k / 8.0) * hw)
	for k in n + 1:
		pts.append(Vector2.from_angle(lerpf(a1, a0, float(k) / n)) * (r - hw))
	var e0 := Vector2.from_angle(a0) * r
	for k in range(1, 8):
		pts.append(e0 + Vector2.from_angle(a0 + PI + PI * k / 8.0) * hw)
	return pts


func _wobble_pts(p: Vector2, r: float, seed_v: float, n: int = 18, amp: float = 0.07) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in n:
		var a := TAU * k / n
		pts.append(p + Vector2.from_angle(a) * r * (1.0 + amp * sin(k * 2.3 + seed_v)))
	return pts


## Иконка, обрезанная по форме ячейки: текстурированный полигон.
func _icon(i: int, p: Vector2, sz: float, shape: int = SH_CIRCLE, alpha: float = 1.0) -> void:
	if sz < 1.0:
		return
	var pts := _shape_pts(shape, p, sz)
	var tex: Texture2D = icons[i] if i < icons.size() else null
	if tex == null:
		_poly(pts, Color(_skill_color(i).darkened(0.45), alpha))
		_text_center(str((i + 1) % 10), p, sz * 0.42, Color(1, 1, 1, alpha))
		return
	var uvs := PackedVector2Array()
	var o := p - Vector2(sz, sz) * 0.5
	for q in pts:
		uvs.append((q - o) / sz)
	draw_colored_polygon(pts, _col(Color.WHITE, alpha), uvs, tex)


func _cooldown(i: int, p: Vector2, sz: float, shape: int = SH_CIRCLE) -> void:
	var left := _cd_end[i] - _time
	if left <= 0.0 or sz < 4.0:
		return
	var f := clampf(left / maxf(_cd_total[i], 0.01), 0.0, 0.999)
	var pie := PackedVector2Array([p])
	var n := maxi(3, int(40.0 * f))
	for k in n + 1:
		pie.append(p + Vector2.from_angle(-PI / 2.0 + TAU * f * k / n) * sz)
	for poly in Geometry2D.intersect_polygons(pie, _shape_pts(shape, p, sz)):
		_poly(poly, Color(0, 0, 0, 0.62))
	_text_center(str(ceili(left)), p, sz * 0.36, Color.WHITE, Color(0, 0, 0, 0.85), 3.0)


func _hotkey(i: int, p: Vector2) -> void:
	_text_center(str((i + 1) % 10), p + Vector2(4, 6), 12.0, Color("f5e04a"), Color(0, 0, 0, 0.9), 3.0)


# ---------------------------------------------------------------- drawing: text

func _text_w(s: String, fs: float) -> float:
	return _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(1, roundi(fs))).x


## Текст по центру точки. Рисуется в экранных пикселях, чтобы шрифт оставался чётким.
func _text_center(s: String, p: Vector2, fs: float, c: Color, outline: Color = Color(0, 0, 0, 0), ow: float = 0.0) -> void:
	var sc := _cur.get_scale().x
	var size_i := maxi(1, roundi(fs * sc))
	var sp := _cur * p
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_i).x
	var base := sp + Vector2(-w * 0.5, (_font.get_ascent(size_i) - _font.get_descent(size_i)) * 0.5)
	var saved := _cur
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if outline.a > 0.0 and ow > 0.0:
		draw_string_outline(_font, base, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_i, maxi(1, roundi(ow * sc)), _col(outline))
	draw_string(_font, base, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_i, _col(c))
	draw_set_transform_matrix(saved)


## Подгоняет текст под ширину: уменьшает шрифт, при необходимости переносит на две строки.
func _fit_text(s: String, p: Vector2, fs: float, max_w: float, c: Color, outline: Color = Color(0, 0, 0, 0), ow: float = 0.0) -> int:
	var z := fs
	while z > 9.0 and _text_w(s, z) > max_w:
		z -= 1.0
	if _text_w(s, z) <= max_w or s.find(" ") < 0:
		_text_center(s, p, z, c, outline, ow)
		return 1
	var best := -1
	var half := s.length() * 0.5
	for k in s.length():
		if s[k] == " " and (best < 0 or absf(k - half) < absf(best - half)):
			best = k
	var a := s.substr(0, best)
	var b := s.substr(best + 1)
	z = fs
	while z > 9.0 and maxf(_text_w(a, z), _text_w(b, z)) > max_w:
		z -= 1.0
	var lh := z * 1.12
	_text_center(a, p - Vector2(0, lh * 0.5), z, c, outline, ow)
	_text_center(b, p + Vector2(0, lh * 0.5), z, c, outline, ow)
	return 2


func _idle_text() -> String:
	return "Ведите к умению" if _mode == Mode.DRAG else "Выберите умение"


## Название и стоимость выбранного умения в центре меню (или подсказка, если ничего не выбрано).
func _center_info(y_name: float, y_stat: float, name_fs: float, stat_fs: float, max_w: float, name_col: Color, stat_col: Color, idle_col: Color, upper: bool = false, idle_y: float = 0.0, idle_fs: float = 15.0) -> void:
	var t := _t()
	if _hover >= 0:
		_ga = t * (0.35 + 0.65 * _hover_t[_hover])
		var nm := _skill_name(_hover)
		if upper:
			nm = nm.to_upper()
		var lines := _fit_text(nm, Vector2(0, y_name), name_fs, max_w, name_col)
		_fit_text(_stat_line(_hover), Vector2(0, y_stat + (lines - 1) * 7.0), stat_fs, max_w, stat_col)
	else:
		_ga = t
		var idle := _idle_text()
		if upper:
			idle = idle.to_upper()
		_fit_text(idle, Vector2(0, idle_y), idle_fs, max_w, idle_col)
	_ga = t


## Точка-«стик», показывающая, куда сейчас ведёт палец.
func _knob(c: Color, r: float = 6.0) -> void:
	if not _has_cursor:
		return
	var lay := _layout()
	var k := _cursor
	var n := Vector2(k.x / lay.rx, k.y / lay.ry).length() if lay.kind == ELLIPSE else k.length() / (lay.r2 if lay.r2 > 0.0 else lay.r)
	if n > 1.0:
		k /= n
	if k.length() < 2.0:
		return
	_ga = _t()
	_dashed(Vector2.ZERO, k, Color(c, 0.55), 1.5)
	_glow(k, r * 4.0, c, 0.9)
	_circ(k, r, Color.WHITE)
	_ring(k, r, 2.0, c)


# ---------------------------------------------------------------- drawing: trigger, hint, debug

func _wheel_glyph(c: Color, open_t: float, r: float = 13.0) -> void:
	var a0 := _ga
	_ga = a0 * (1.0 - open_t)
	var rot := open_t * PI / 4.0
	for k in 8:
		_circ(Vector2.from_angle(k * TAU / 8.0 - PI / 2.0 + rot) * r, 3.6 if k == 0 else 2.6, c)
	_circ(Vector2.ZERO, 4.2, c)
	_ga = a0
	_cross_glyph(c, open_t)


func _cross_glyph(c: Color, open_t: float) -> void:
	if open_t <= 0.01:
		return
	var a0 := _ga
	_ga = a0 * open_t
	var rot := (1.0 - open_t) * -PI / 4.0
	var d1 := Vector2.from_angle(PI / 4.0 + rot) * 12.7
	var d2 := Vector2.from_angle(-PI / 4.0 + rot) * 12.7
	_line(-d1, d1, c, 4.0)
	_line(-d2, d2, c, 4.0)
	_ga = a0


func _accent() -> Color:
	match style:
		Style.SECTOR:
			return Color("bfe6ff")
		Style.FAN:
			return Color("fff1cf")
		Style.ARCANE:
			return Color("63e6ff")
		Style.HEX:
			return Color("38f2d0")
		Style.NEON:
			return Color("ffe45c")
		Style.STAR:
			return Color("fff0b8")
		Style.PARCHMENT:
			return Color("ffd9a0")
		Style.EMBER, Style.GEARS:
			return Color("ffb347")
		Style.HALO:
			return Color("fff3c4")
		Style.ARCH:
			return Color("6fe3ff")
		Style.FLOWER:
			return Color("ffd1e6")
		Style.ORBIT:
			return Color("ffd27a")
		Style.SHIELD:
			return Color("f3c26a")
		Style.GLASS:
			return Color("fff1c8")
		Style.BUBBLES:
			return Color("9fe8ff")
		Style.INK:
			return Color("c8321e")
		Style.CLEAN:
			return Color("3d7bfd")
	return Color("ffe3a0")


func _hold_ring() -> void:
	if _mode != Mode.PRESS or hold_delay <= 0.0:
		return
	var h := clampf((_time - _press_at) / hold_delay, 0.0, 1.0)
	_ring(Vector2.ZERO, 40.0, 3.5, _accent(), -PI / 2.0, -PI / 2.0 + TAU * h)


func _draw_trigger(open_t: float) -> void:
	var pu := 0.5 + 0.5 * sin(_time * 3.0)
	var ga := (0.3 + 0.35 * pu) * (1.0 - open_t)
	_ga = 1.0
	match style:
		Style.BRONZE:
			_glow(Vector2.ZERO, 60.0 + 8.0 * pu, Color("ffb54a"), ga)
			_circ(Vector2.ZERO, 31, Color("1f1813"))
			_bevel(Vector2.ZERO, 32, 6, BRONZE_MID, BRONZE_HI, BRONZE_LO)
			_ring(Vector2.ZERO, 27, 1, Color(0, 0, 0, 0.7))
			_wheel_glyph(Color("f6d896"), open_t)
		Style.SECTOR:
			_glow(Vector2.ZERO, 60.0 + 8.0 * pu, Color("8fd3ff"), ga * 0.8)
			_circ(Vector2.ZERO, 31, Color(0.047, 0.063, 0.086, 0.9))
			_ring(Vector2.ZERO, 31, 2, Color(1, 1, 1, 0.7))
			_ga = 1.0 - open_t
			for k in COUNT:
				var a := -PI / 2.0 + k * TAU / COUNT
				_poly(_sector_pts(10, 21, a - PI / COUNT, a + PI / COUNT, 1.2), Color.WHITE if k == 0 else Color(1, 1, 1, 0.5))
			_ga = 1.0
			_cross_glyph(Color.WHITE, open_t)
		Style.FAN:
			_glow(Vector2.ZERO, 58.0 + 8.0 * pu, Color("ffe2a0"), ga * 0.85)
			var sq := _shape_pts(SH_RSQ, Vector2.ZERO, 62)
			_poly(sq, Color(0.055, 0.063, 0.08, 0.92))
			_outline(sq, SILVER_MID, 3.0)
			_ring(Vector2.ZERO, 30, 1.5, Color(1, 1, 1, 0.25), PI * 1.05, PI * 1.45)
			_wheel_glyph(Color("fff1cf"), open_t)
		Style.ARCANE:
			_glow(Vector2.ZERO, 62.0 + 8.0 * pu, Color("8a5cff"), ga * 1.1)
			_circ(Vector2.ZERO, 31, Color("130a28"))
			_ring(Vector2.ZERO, 31, 1.6, Color("63e6ff"))
			var ticks := PackedVector2Array()
			for k in 12:
				var a := _time * 0.8 + k * TAU / 12.0
				ticks.append(Vector2.from_angle(a) * 27.0)
				ticks.append(Vector2.from_angle(a) * (24.0 if k % 3 != 0 else 21.0))
			draw_multiline(ticks, _col(Color(0.78, 0.64, 1.0, 0.8)), 1.0)
			_wheel_glyph(Color("bff5ff"), open_t, 12.0)
		Style.HEX:
			_glow(Vector2.ZERO, 60.0 + 8.0 * pu, Color("38f2d0"), ga * 0.85)
			var hx := _shape_pts(SH_HEX, Vector2.ZERO, 72)
			_poly(hx, Color(0.016, 0.07, 0.086, 0.92))
			_outline(hx, Color("38f2d0"), 2.0)
			_outline(_shape_pts(SH_HEX, Vector2.ZERO, 60), Color(0.22, 0.95, 0.82, 0.35), 1.0)
			_wheel_glyph(Color("bffff1"), open_t, 12.0)
		Style.NEON:
			_glow(Vector2.ZERO, 62.0 + 8.0 * pu, Color("ff3fd2"), ga)
			_circ(Vector2.ZERO, 31, Color(0.03, 0.0, 0.07, 0.9))
			_neon_ring(Vector2.ZERO, 30, Color("ff3fd2"), 2.0)
			_neon_ring(Vector2.ZERO, 24, Color("28e7ff"), 1.1)
			_wheel_glyph(Color("ffe45c"), open_t, 12.0)
		Style.STAR:
			_glow(Vector2.ZERO, 60.0 + 8.0 * pu, Color("ffd36b"), ga * 0.9)
			var pts := PackedVector2Array()
			for k in 16:
				pts.append(Vector2.from_angle(-PI / 2.0 + k * TAU / 16.0) * (26.0 if k % 2 == 1 else 35.0))
			_poly(pts, Color("13235a"))
			_outline(pts, GOLD_MID, 2.5)
			_wheel_glyph(Color("fff0b8"), open_t, 12.0)
		Style.PARCHMENT:
			_glow(Vector2.ZERO, 58.0 + 8.0 * pu, Color("ff9a4a"), ga * 0.85)
			var wx := _wobble_pts(Vector2.ZERO, 32, 1.0)
			_poly(wx, Color("a8281c"))
			_circ(Vector2(-6, -8), 16, Color(0.85, 0.3, 0.24, 0.45))
			_outline(wx, Color(0.24, 0.03, 0.02, 0.7), 1.5)
			_ring(Vector2.ZERO, 22, 1.5, Color(1, 0.75, 0.67, 0.35))
			_wheel_glyph(Color("ffd9c9"), open_t, 12.0)
		Style.DIAL:
			_glow(Vector2.ZERO, 58.0 + 8.0 * pu, Color("ffcf73"), ga * 0.85)
			_circ(Vector2.ZERO, 32, GOLD_LO)
			_circ(Vector2(-4, -5), 26, Color(1.0, 0.86, 0.5, 0.5))
			var kn := PackedVector2Array()
			for k in 32:
				var a := k * TAU / 32.0
				kn.append(Vector2.from_angle(a) * 28.0)
				kn.append(Vector2.from_angle(a) * 32.0)
			draw_multiline(kn, _col(Color(0.27, 0.18, 0.04, 0.7)), 1.4)
			_circ(Vector2.ZERO, 25, Color("15120d"))
			_wheel_glyph(Color("f3e2b5"), open_t, 12.0)
		Style.EMBER:
			var fl := 0.5 + 0.5 * sin(_time * 9.0) * sin(_time * 3.7)
			_glow(Vector2.ZERO, 60.0 + 10.0 * fl, Color("ff7a1a"), (0.3 + 0.35 * fl) * (1.0 - open_t))
			_circ(Vector2.ZERO, 31, Color("24201d"))
			_circ(Vector2(-6, -8), 18, Color(0.29, 0.26, 0.24, 0.6))
			_ring(Vector2.ZERO, 31, 3, Color("6b625b"))
			for k in 8:
				_circ(Vector2.from_angle(k * TAU / 8.0 + PI / 8.0) * 26.0, 1.8, Color("9a8e84"))
			_wheel_glyph(Color("ffb347"), open_t, 13.0)
		_:
			_draw_trigger_around(open_t, pu, ga)


func _draw_hint() -> void:
	var txt := "Нажмите или зажмите"
	var y := -60.0 + sin(_time * 3.8) * 4.0
	var w := _text_w(txt, 13) + 24.0
	var pill := _rrect_pts(Rect2(-w * 0.5, y - 13.0, w, 26.0), 13.0)
	_poly(pill, Color(0.04, 0.043, 0.05, 0.85))
	_outline(pill, Color(0.94, 0.8, 0.55, 0.7), 1.0)
	_poly(PackedVector2Array([Vector2(-6, y + 13), Vector2(6, y + 13), Vector2(0, y + 20)]), Color(0.04, 0.043, 0.05, 0.85))
	_text_center(txt, Vector2(0, y), 13.0, Color("f3dfb2"))


func _draw_zones() -> void:
	var lay := _layout()
	_ga = 1.0
	_circ(Vector2.ZERO, dead_zone, Color(1, 0.3, 0.3, 0.18))
	_ring(Vector2.ZERO, dead_zone, 1.0, Color(1, 0.47, 0.47, 0.9))
	if lay.kind == TIERS:
		for q in lay.pts:
			_ring(q, lay.tap_r, 1.0, Color(0.47, 0.86, 1, 0.8))
		return
	if lay.kind == ELLIPSE:
		for b in [lay.hit.x, lay.hit.y]:
			draw_polyline(_ellipse_pts(lay.rx * b / 100.0, lay.ry * b / 100.0, 0.0, TAU, 64), _col(Color(0.47, 0.86, 1, 0.8)), 1.0, true)
		var el := PackedVector2Array()
		for i in COUNT:
			var a := _par[i] - PI / COUNT
			el.append(Vector2(cos(a) * lay.rx * 0.3, sin(a) * lay.ry * 0.3))
			el.append(Vector2(cos(a) * lay.rx * lay.hit.y / 100.0, sin(a) * lay.ry * lay.hit.y / 100.0))
		draw_multiline(el, _col(Color(1, 1, 1, 0.55)), 1.0)
		return
	_ring(Vector2.ZERO, lay.hit.x, 1.0, Color(0.47, 0.86, 1, 0.8))
	_ring(Vector2.ZERO, lay.hit.y, 1.0, Color(0.47, 0.86, 1, 0.8))
	var half := (lay.sweep / (COUNT - 1) if lay.kind == ARC or lay.kind == GAUGE else TAU / COUNT) * 0.5
	var lines := PackedVector2Array()
	for i in COUNT:
		lines.append(Vector2.from_angle(_ang[i] - half) * dead_zone)
		lines.append(Vector2.from_angle(_ang[i] - half) * lay.hit.y)
	if lay.kind == ARC or lay.kind == GAUGE:
		lines.append(Vector2.from_angle(_ang[COUNT - 1] + half) * dead_zone)
		lines.append(Vector2.from_angle(_ang[COUNT - 1] + half) * lay.hit.y)
	draw_multiline(lines, _col(Color(1, 1, 1, 0.55)), 1.0)


func _draw_cast_flash() -> void:
	if _cast_index < 0:
		return
	var k := clampf((_time - _cast_at) / 0.52, 0.0, 1.0)
	if k >= 1.0:
		return
	var pos := _pos[_cast_index]
	var c := _skill_color(_cast_index)
	_ga = 1.0
	_glow(pos, 40.0 + 50.0 * k, c, 1.0 - k)
	_ring(pos, 24.0 + 40.0 * _out_cubic(k), 3.0 * (1.0 - k) + 0.05, Color(c, 1.0 - k))


func _make_glow_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.22, 0.55, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.16), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 128
	t.height = 128
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


func _neon_ring(p: Vector2, r: float, c: Color, w: float, a0: float = 0.0, a1: float = TAU) -> void:
	_ring(p, r, w * 6.0, Color(c, 0.07), a0, a1)
	_ring(p, r, w * 3.0, Color(c, 0.16), a0, a1)
	_ring(p, r, w, Color(c, 0.95), a0, a1)
	_ring(p, r, maxf(0.6, w * 0.4), Color(1, 1, 1, 0.8), a0, a1)


func _neon_line(a: Vector2, b: Vector2, c: Color, w: float) -> void:
	_line(a, b, Color(c, 0.1), w * 5.0)
	_line(a, b, Color(c, 0.95), w)
	_line(a, b, Color(1, 1, 1, 0.8), maxf(0.6, w * 0.4))


# ---------------------------------------------------------------- styles

func _draw_bronze() -> void:
	var t := _t()
	var cl := _closing()
	var bs := (0.9 + 0.1 * t) if cl else (0.86 + 0.14 * _out_back(_raw))
	_local_xf(0.0, bs)
	_ga = t
	_circ(Vector2.ZERO, 186, Color(0.055, 0.043, 0.031, 0.82))
	_glow(Vector2.ZERO, 150, Color(0.16, 0.12, 0.08), 0.5)
	_bevel(Vector2.ZERO, 184, 5, BRONZE_MID, BRONZE_HI, BRONZE_LO)
	_ring(Vector2.ZERO, 181, 1, Color(0, 0, 0, 0.7))
	_ring(Vector2.ZERO, 142, 12, Color(0, 0, 0, 0.32))
	_ring(Vector2.ZERO, 84, 1.5, Color(0.77, 0.59, 0.35, 0.4))
	for i in COUNT:
		_poly(_shape_pts(SH_DIAMOND, Vector2.from_angle(_ang[i] + PI / COUNT) * 142.0, 9), Color("b8894e"))
	if _hover >= 0:
		var a := _ang[_hover]
		var side := Vector2.from_angle(a + PI / 2.0) * 10.0
		_poly(PackedVector2Array([Vector2.from_angle(a) * 175.0, Vector2.from_angle(a) * 193.0 + side, Vector2.from_angle(a) * 193.0 - side]), Color(1, 0.85, 0.54, _hover_t[_hover]))
	_local_xf()
	for i in _order():
		var p := _stag(i, 0.45)
		var e := p if cl else _out_back(p)
		var h := _hover_t[i]
		var r := 142.0 * (0.5 + 0.5 * e) * ((0.9 + 0.1 * p) if cl else 1.0)
		var pos := Vector2.from_angle(_ang[i]) * r + Vector2(_shake(i), 0)
		var sz := 58.0 * (0.55 + 0.45 * e) * (1.0 + 0.17 * h)
		_ga = _slot_alpha(p, 1.8)
		_glow(pos, sz * 1.1, Color("ffc45e"), h * 0.85)
		_circ(pos, sz * 0.5 + 1.0, Color("130f0b"))
		_icon(i, pos, sz * 0.8)
		_cooldown(i, pos, sz * 0.8)
		_bevel(pos, sz * 0.5 - 2.0, 5, BRONZE_MID.lerp(GOLD_MID, h), BRONZE_HI.lerp(GOLD_HI, h), BRONZE_LO.lerp(GOLD_LO, h))
		_ring(pos, sz * 0.4 + 0.5, 1, Color(0, 0, 0, 0.75))
		_hotkey(i, pos + Vector2(-sz * 0.38, -sz * 0.44))
	_ga = t
	_circ(Vector2.ZERO, 60, Color("120e0a"))
	_glow(Vector2(0, -14), 46, Color(0.17, 0.13, 0.09), 0.8)
	_bevel(Vector2.ZERO, 60, 3, BRONZE_MID, BRONZE_HI, BRONZE_LO)
	_ring(Vector2.ZERO, 54, 1, Color(0.96, 0.85, 0.59, 0.25))
	_center_info(-8, 22, 19, 11, 98, Color("f6d896"), Color("c9b48e"), Color(0.96, 0.85, 0.59, 0.72))
	_knob(Color("ffd27a"))


func _draw_sector() -> void:
	var lay := _layout()
	var t := _t()
	var cl := _closing()
	var step := TAU / COUNT
	var rot := 0.0 if cl else (1.0 - _out_cubic(_raw)) * -0.5
	var sc := (0.9 + 0.1 * t) if cl else (0.8 + 0.2 * _out_cubic(_raw))
	_local_xf(0.0, sc)
	for i in _order():
		var p := _stag(i, 0.35)
		var h := _hover_t[i]
		var a := _ang[i] + rot
		var col := _skill_color(i)
		_ga = _slot_alpha(p, 1.5)
		var off := Vector2.from_angle(a) * 10.0 * h + Vector2(_shake(i), 0)
		var r1 := lay.r_out + 8.0 * h
		var pts := _sector_pts(lay.r_in, r1, a - step * 0.5, a + step * 0.5, 2.5, off)
		_poly(pts, Color(0.047, 0.063, 0.086, 0.72))
		if h > 0.01:
			var cols := PackedColorArray()
			var half := int(pts.size() * 0.5)
			for k in pts.size():
				cols.append(Color(col, (0.85 if k < half else 0.2) * h))
			_poly_grad(pts, cols)
		_outline(pts, Color(1, 1, 1, 0.13), 1.0)
		_ring(off, r1 - 2.5, 4.0, Color(col, 0.25 + 0.75 * h), a - step * 0.5 + 3.0 / r1, a + step * 0.5 - 3.0 / r1)
		var ip := off + Vector2.from_angle(a) * (lay.r + 6.0 * h)
		var isz := 46.0 * (1.0 + 0.12 * h)
		_icon(i, ip, isz, SH_CIRCLE, 0.7 + 0.3 * h)
		_cooldown(i, ip, isz)
		_ring(ip, isz * 0.5, 1.5, Color(1, 1, 1, 0.95) if h > 0.5 else Color(0, 0, 0, 0.55))
	_local_xf()
	_ga = t
	_circ(Vector2.ZERO, 56, Color(0.03, 0.04, 0.055, 0.9))
	_ring(Vector2.ZERO, 56, 1, Color(1, 1, 1, 0.15))
	if _hover >= 0:
		var ha := _ang[_hover]
		_ring(Vector2.ZERO, 60, 3, _skill_color(_hover), ha - step * 0.5 + 0.04, ha + step * 0.5 - 0.04)
	_center_info(-7, 21, 14, 11, 90, Color.WHITE, _skill_color(_hover), Color(1, 1, 1, 0.6), true, 0.0, 12.0)
	_knob(Color.WHITE)


func _draw_fan() -> void:
	var lay := _layout()
	var t := _t()
	var cl := _closing()
	var rr := lay.r
	var mid := lay.start + lay.sweep * 0.5
	var span := (lay.sweep * 0.5 + 0.16) * (1.0 if cl else _out_cubic(_raw))
	_ga = t
	if span > 0.02:
		_poly(_band_pts(rr, 84, mid - span, mid + span), Color(0.03, 0.04, 0.047, 0.5))
		_ring(Vector2.ZERO, rr - 45.0, 1.2, Color(1, 0.93, 0.78, 0.35), mid - span, mid + span)
		_ring(Vector2.ZERO, rr + 45.0, 1.2, Color(1, 0.93, 0.78, 0.35), mid - span, mid + span)
	if _hover >= 0:
		var h := _hover_t[_hover]
		var a := _ang[_hover]
		var tip := Vector2.from_angle(a) * (rr + 16.0 * h)
		var n := Vector2.from_angle(a + PI / 2.0)
		var c := _skill_color(_hover)
		_poly_grad(PackedVector2Array([n * 5.0, tip + n * 24.0, tip - n * 24.0, -n * 5.0]), PackedColorArray([Color(c, 0), Color(c, 0.42 * h), Color(c, 0.42 * h), Color(c, 0)]))
	for i in _order():
		var rank := absf(i - (COUNT - 1) * 0.5) / ((COUNT - 1) * 0.5)
		var p := _stag(i, 0.5, rank)
		var e := p if cl else _out_back(p, 1.6)
		var h := _hover_t[i]
		var pos := Vector2.from_angle(_ang[i]) * (rr * e + 16.0 * h) + Vector2(_shake(i), 0)
		var sz := 54.0 * (1.0 + 0.14 * h) * (0.6 + 0.4 * minf(e, 1.0))
		_ga = _slot_alpha(p, 2.0)
		_glow(pos, sz * 1.05, _skill_color(i), 0.75 * h)
		_poly(_shape_pts(SH_RSQ, pos + Vector2(0, 3), sz), Color(0, 0, 0, 0.45))
		_icon(i, pos, sz, SH_RSQ)
		_cooldown(i, pos, sz, SH_RSQ)
		_outline(_shape_pts(SH_RSQ, pos, sz), SILVER_MID.lerp(SILVER_HI, h), 2.5)
		_outline(_shape_pts(SH_RSQ, pos, sz - 6.0), Color(0, 0, 0, 0.5), 1.0)
		_hotkey(i, pos + Vector2(-sz * 0.42, -sz * 0.46))
	if _hover >= 0:
		var h2 := _hover_t[_hover]
		var lp := Vector2.from_angle(_ang[_hover]) * (rr + 16.0 * h2) - Vector2(0, 54)
		var label := "%s · MP %d" % [_skill_name(_hover), skill_mp[_hover] if _hover < skill_mp.size() else 0]
		var w := _text_w(label, 14) + 24.0
		_ga = h2 * t
		var pill := _rrect_pts(Rect2(lp.x - w * 0.5, lp.y - 14.0, w, 28.0), 14.0)
		_poly(pill, Color(0.04, 0.047, 0.063, 0.9))
		_outline(pill, Color(_skill_color(_hover), 0.7), 1.0)
		_text_center(label, lp, 14.0, Color.WHITE)
	_knob(Color("ffe2a0"))


func _rune_segments(k: int) -> PackedVector2Array:
	match (k * 5 + 3) % 8:
		0:
			return PackedVector2Array([Vector2(0, -4), Vector2(0, 4), Vector2(0, -4), Vector2(3, -1)])
		1:
			return PackedVector2Array([Vector2(-3, -4), Vector2(-3, 4), Vector2(-3, 0), Vector2(3, -4), Vector2(-3, 0), Vector2(3, 4)])
		2:
			return PackedVector2Array([Vector2(0, -4), Vector2(0, 4), Vector2(-3, -1), Vector2(3, -1)])
		3:
			return PackedVector2Array([Vector2(-3, 4), Vector2(0, -4), Vector2(0, -4), Vector2(3, 4), Vector2(-1.5, 0), Vector2(1.5, 0)])
		4:
			return PackedVector2Array([Vector2(-3, -4), Vector2(3, 4), Vector2(3, -4), Vector2(-3, 4)])
		5:
			return PackedVector2Array([Vector2(0, -4), Vector2(0, 4), Vector2(0, -4), Vector2(3, -2), Vector2(0, 0), Vector2(3, -2)])
		6:
			return PackedVector2Array([Vector2(-3, -3), Vector2(3, -3), Vector2(0, -3), Vector2(0, 4), Vector2(-2, 1), Vector2(2, 1)])
	return PackedVector2Array([Vector2(-2, -4), Vector2(2, 0), Vector2(2, 0), Vector2(-2, 4)])


func _draw_arcane() -> void:
	var t := _t()
	var cl := _closing()
	var q := 1.0 if cl else _out_cubic(clampf(_raw / 0.7, 0.0, 1.0))
	var a0 := -PI / 2.0
	_ga = t
	_circ(Vector2.ZERO, 196, Color(0.07, 0.04, 0.16, 0.6))
	_glow(Vector2.ZERO, 200, Color(0.22, 0.12, 0.45), 0.6)
	_ring(Vector2.ZERO, 192, 1.6, Color(0.39, 0.9, 1, 0.85), a0, a0 + TAU * q)
	_ring(Vector2.ZERO, 174, 1.0, Color(0.66, 0.47, 1, 0.75), a0, a0 + TAU * q)
	_ring(Vector2.ZERO, 88, 1.2, Color(0.39, 0.9, 1, 0.6), a0, a0 + TAU * q)
	_ring(Vector2.ZERO, 80, 0.8, Color(0.66, 0.47, 1, 0.6), a0, a0 + TAU * q)
	var runes := PackedVector2Array()
	for k in 36:
		if float(k) / 36.0 > q:
			break
		var th := _time * 0.12 + k * TAU / 36.0
		for v in _rune_segments(k):
			runes.append((v + Vector2(0, -183)).rotated(th))
	if runes.size() >= 2:
		draw_multiline(runes, _col(Color(0.55, 0.92, 1, 0.65)), 1.2)
	var ticks := PackedVector2Array()
	for k in 48:
		var a := -_time * 0.2 + k * TAU / 48.0
		ticks.append(Vector2.from_angle(a) * 80.0)
		ticks.append(Vector2.from_angle(a) * (70.0 if k % 4 == 0 else 75.0))
	draw_multiline(ticks, _col(Color(0.66, 0.47, 1, 0.6)), 1.0)
	var star := PackedVector2Array()
	for k in COUNT + 1:
		star.append(Vector2.from_angle(_ang[(k * 3) % COUNT]) * 140.0)
	draw_polyline(star, _col(Color(0.66, 0.47, 1, 0.3)), 1.0, true)
	if _hover >= 0:
		var h := _hover_t[_hover]
		var tip := Vector2.from_angle(_ang[_hover]) * 140.0
		_grad_line(Vector2.ZERO, tip, 8.0, Color(0.39, 0.9, 1, 0), Color(0.55, 0.94, 1, 0.3 * h))
		_grad_line(Vector2.ZERO, tip, 2.0, Color(0.39, 0.9, 1, 0), Color(0.55, 0.94, 1, 0.95 * h))
	for i in _order():
		var p := _stag(i, 0.55)
		var e := p if cl else _out_back(p, 2.0)
		var h := _hover_t[i]
		var pos := Vector2.from_angle(_ang[i]) * 140.0 + Vector2(_shake(i), 0)
		var sz := 62.0 * e * (1.0 + 0.18 * h)
		if sz <= 1.0:
			continue
		_ga = _slot_alpha(p, 1.6)
		_glow(pos, sz * 0.95, Color("63e6ff"), 0.12 + 0.75 * h)
		var dm := _shape_pts(SH_DIAMOND, pos, sz)
		_poly(dm, Color(0.07, 0.043, 0.14, 0.93))
		_outline(dm, Color("95c4ff").lerp(Color("bff5ff"), h), 2.0 + 1.2 * h)
		_outline(_shape_pts(SH_DIAMOND, pos, sz - 9.0), Color(0.78, 0.64, 1, 0.45), 0.8)
		_icon(i, pos, sz * 0.56)
		_cooldown(i, pos, sz * 0.56)
	_ga = t
	_glow(Vector2.ZERO, 82, Color("7b4dff"), 0.45 + 0.1 * sin(_time * 2.0))
	_circ(Vector2.ZERO, 52, Color("120a26"))
	_glow(Vector2(0, -10), 40, Color(0.17, 0.09, 0.35), 0.8)
	_ring(Vector2.ZERO, 52, 1.2, Color(0.39, 0.9, 1, 0.6))
	_center_info(-8, 20, 18, 10.5, 86, Color("dff8ff"), Color("b9a3ff"), Color(0.87, 0.97, 1, 0.72), false, 0.0, 14.0)
	_knob(Color("63e6ff"))


func _hex_half_width(rr: float, y: float) -> float:
	var ay := absf(y)
	if ay <= rr * 0.5:
		return rr * 0.866
	return maxf(0.0, rr * 0.866 * (rr - ay) / (rr * 0.5))


func _draw_hex() -> void:
	var teal := Color("38f2d0")
	var t := _t()
	var cl := _closing()
	_ga = t
	_ring(Vector2.ZERO, 140, 1, Color(teal, 0.22))
	var ticks := PackedVector2Array()
	for k in 40:
		var a := k * TAU / 40.0
		ticks.append(Vector2.from_angle(a) * 181.0)
		ticks.append(Vector2.from_angle(a) * (193.0 if k % 4 == 0 else 186.0))
	draw_multiline(ticks, _col(Color(teal, 0.42)), 1.0)
	for i in _order():
		var p := _stag(i, 0.6)
		var e := p if cl else _out_back(p, 2.4)
		var h := _hover_t[i]
		var pos := Vector2.from_angle(_ang[i]) * 140.0 + Vector2(_shake(i), 0)
		var sz := 64.0 * e * (1.0 + 0.12 * h)
		if sz <= 9.0:
			continue
		_ga = _slot_alpha(p, 1.6)
		_glow(pos, sz, teal, 0.6 * h)
		var hx := _shape_pts(SH_HEX, pos, sz)
		_poly(hx, Color(0.016, 0.07, 0.086, 0.9))
		_icon(i, pos, sz - 8.0, SH_HEX, 1.0 - 0.55 * _any * (1.0 - h))
		if h > 0.01:
			_poly(_shape_pts(SH_HEX, pos, sz - 8.0), Color(teal, 0.16 * h))
			var rr := (sz - 8.0) * 0.5
			var sy := -rr + fposmod(_time * 1.4, 1.0) * 2.0 * rr
			var hw := _hex_half_width(rr, sy)
			if hw > 0.5:
				_line(pos + Vector2(-hw, sy), pos + Vector2(hw, sy), Color(0.85, 1, 0.96, 0.6 * h), 2.0)
		_cooldown(i, pos, sz - 8.0, SH_HEX)
		_outline(hx, Color(teal, 0.45 + 0.55 * h), 1.5 + 1.5 * h)
	_ga = t
	if _hover >= 0:
		var a := _ang[_hover]
		_ga = t * _hover_t[_hover]
		_line(Vector2.from_angle(a) * 56.0, Vector2.from_angle(a) * 104.0, teal, 1.5)
		_poly(_shape_pts(SH_SQ, Vector2.from_angle(a) * 80.0, 6), teal)
		_ga = t
	var ch := _shape_pts(SH_HEX, Vector2.ZERO, 118)
	_poly(ch, Color(0.012, 0.05, 0.063, 0.93))
	_outline(ch, Color(teal, 0.7), 1.5)
	_outline(_shape_pts(SH_HEX, Vector2.ZERO, 106), Color(teal, 0.25), 0.8)
	_center_info(-8, 19, 14, 11, 82, Color.WHITE, teal, Color(teal, 0.75), true, 0.0, 11.0)
	if _has_cursor:
		var k := _cursor
		if k.length() > _layout().r:
			k = k.normalized() * _layout().r
		if k.length() >= 2.0:
			_ga = t
			_glow(k, 22, teal, 0.8)
			var dm := _shape_pts(SH_DIAMOND, k, 14)
			_poly(dm, Color("e6fffa"))
			_outline(dm, teal, 2.0)


func _draw_neon() -> void:
	var magenta := Color("ff3fd2")
	var cyan := Color("28e7ff")
	var yellow := Color("ffe45c")
	var t := _t()
	var cl := _closing()
	var q := 1.0 if cl else _out_cubic(_raw)
	var a0 := -PI / 2.0
	var flick := 1.0
	if not cl and _raw < 0.5 and floori(_raw * 22.0) % 3 == 0:
		flick = 0.35
	_ga = t * flick
	_circ(Vector2.ZERO, 192, Color(0.024, 0.0, 0.055, 0.4))
	_neon_ring(Vector2.ZERO, 182, magenta, 2.0, a0, a0 + TAU * q)
	_neon_ring(Vector2.ZERO, 92, cyan, 1.5, a0 - TAU * q, a0)
	if _hover >= 0:
		var a := _ang[_hover]
		_ga = t * flick * _hover_t[_hover]
		_neon_ring(Vector2.ZERO, 182, yellow, 3.2, a - 0.27, a + 0.27)
		_neon_line(Vector2.from_angle(a) * 92.0, Vector2.from_angle(a) * 106.0, yellow, 1.4)
	for i in _order():
		var p := _stag(i, 0.4)
		var e := p if cl else _out_back(p, 1.4)
		var h := _hover_t[i]
		var pos := Vector2.from_angle(_ang[i]) * 138.0 * (0.7 + 0.3 * e) + Vector2(_shake(i), 0)
		var sz := 54.0 * (1.0 + 0.15 * h)
		_ga = _slot_alpha(p, 1.6) * flick
		_circ(pos, sz * 0.5, Color(0.02, 0.0, 0.055, 0.88))
		_icon(i, pos, sz - 12.0, SH_CIRCLE, 0.92)
		_cooldown(i, pos, sz - 12.0)
		_neon_ring(pos, sz * 0.5, (cyan if i % 2 == 1 else magenta).lerp(yellow, h), 1.6 + 1.0 * h)
	_ga = t
	if _hover >= 0:
		var nm := _skill_name(_hover).to_upper()
		var j := randf_range(-2.0, 2.0) if _hover_t[_hover] < 0.92 else 0.0
		_ga = t * (0.35 + 0.65 * _hover_t[_hover])
		_fit_text(nm, Vector2(-1.6 + j, -6), 16, 140, Color(cyan, 0.85))
		_fit_text(nm, Vector2(1.6 - j, -6), 16, 140, Color(magenta, 0.85))
		_fit_text(nm, Vector2(0, -6), 16, 140, Color.WHITE)
		_fit_text(_stat_line(_hover), Vector2(0, 22), 11, 140, yellow)
	else:
		_fit_text(_idle_text().to_upper(), Vector2.ZERO, 13, 140, Color(cyan, 0.85))
	_knob(yellow)


func _draw_star() -> void:
	var gold := Color("e7c46a")
	var t := _t()
	var cl := _closing()
	var rot := 0.0 if cl else (1.0 - _out_cubic(_raw)) * (-PI / 5.0)
	var sc := (0.9 + 0.1 * t) if cl else maxf(0.01, _out_back(_raw, 1.3))
	var v := PackedVector2Array()
	var vo := PackedVector2Array()
	for i in COUNT:
		v.append(Vector2.from_angle(_ang[i]) * _rad[i])
		vo.append(Vector2.from_angle(_ang[i]) * (_rad[i] + (46.0 if i % 2 == 1 else 20.0)))
	_local_xf(rot, sc)
	_ga = t
	_poly(vo, Color(0.07, 0.13, 0.3, 0.84))
	_glow(Vector2.ZERO, 170, Color(0.2, 0.33, 0.75), 0.55)
	_outline(vo, Color(gold, 0.85), 1.6)
	if _hover >= 0:
		var i0 := _hover
		var pr := vo[(i0 + COUNT - 1) % COUNT]
		var nx := vo[(i0 + 1) % COUNT]
		var c0 := vo[i0]
		var wc := Color(1, 0.88, 0.55, 0.4 * _hover_t[i0])
		_poly_grad(PackedVector2Array([Vector2.ZERO, (pr + c0) * 0.5, c0, (nx + c0) * 0.5]), PackedColorArray([Color(wc, 0), wc, wc, wc]))
	var spokes := PackedVector2Array()
	for q in v:
		spokes.append(Vector2.ZERO)
		spokes.append(q)
	draw_multiline(spokes, _col(Color(gold, 0.18)), 1.0)
	_outline(v, Color(gold, 0.3), 1.0)
	for i in _order():
		var p := _stag(i, 0.45)
		var e := 1.0 if cl else _out_back(p, 1.8)
		var h := _hover_t[i]
		var pos := v[i] + Vector2(_shake(i), 0)
		var sz := 56.0 * (1.0 + 0.18 * h) * maxf(0.0, e)
		if sz <= 10.0:
			continue
		_ga = _slot_alpha(p, 1.6)
		_glow(pos, sz * 1.1, Color("ffd36b"), 0.8 * h)
		_poly(_shape_pts(SH_RSQ, pos, sz), Color("0e1a3e"))
		_icon(i, pos, sz - 9.0, SH_RSQ)
		_cooldown(i, pos, sz - 9.0, SH_RSQ)
		_outline(_shape_pts(SH_RSQ, pos, sz), GOLD_MID.lerp(GOLD_HI, h), 2.6)
		_outline(_shape_pts(SH_RSQ, pos, sz - 5.0), Color(0, 0, 0, 0.6), 1.0)
	_local_xf()
	_ga = t
	_circ(Vector2.ZERO, 56, Color("0b1430"))
	_glow(Vector2(0, -12), 46, Color(0.16, 0.28, 0.62), 0.9)
	_bevel(Vector2.ZERO, 56, 3, GOLD_MID, GOLD_HI, GOLD_LO)
	for k in COUNT:
		_circ(Vector2.from_angle(_ang[k]) * 49.0, 2.6 if k == _hover else 1.5, gold)
	_center_info(-8, 20, 18, 10.5, 86, Color("fff0b8"), Color("c7d3ff"), Color(1, 0.94, 0.72, 0.75), false, 0.0, 14.0)
	_knob(Color("ffd36b"))


func _draw_parchment() -> void:
	var ink := Color("3b2412")
	var t := _t()
	var cl := _closing()
	var e := 1.0 if cl else _out_cubic(_raw)
	var sc := (0.85 + 0.15 * t) if cl else maxf(0.01, e)
	_local_xf((1.0 - e) * 0.25, sc)
	_ga = t if cl else 1.0
	_circ(Vector2(4, 8), 196, Color(0, 0, 0, 0.35))
	_circ(Vector2.ZERO, 196, Color("e8d3a6"))
	for sp in _parch_spots:
		_glow(Vector2(sp.x, sp.y), sp.z, Color(0.55, 0.38, 0.18), 0.16)
	_ring(Vector2.ZERO, 186, 20, Color(0.43, 0.25, 0.08, 0.18))
	_ring(Vector2.ZERO, 194, 5, Color(0.3, 0.16, 0.04, 0.55))
	_ring(Vector2.ZERO, 187, 2, Color(ink, 0.8))
	_ring(Vector2.ZERO, 181, 0.8, Color(ink, 0.5))
	_ring(Vector2.ZERO, 94, 1.5, Color(ink, 0.7))
	for i in COUNT:
		var a := _ang[i] + PI / COUNT
		var op := Vector2.from_angle(a) * 138.0
		_circ(op, 2.4, Color(ink, 0.8))
		_ring(op, 7.0, 1.0, Color(ink, 0.55), a + 0.5, a + 2.4)
		_ring(op, 7.0, 1.0, Color(ink, 0.55), a + PI + 0.5, a + PI + 2.4)
	var base_a := _ga
	for i in _order():
		var p := _stag(i, 0.45)
		var ee := 1.0 if cl else _out_back(p)
		var h := _hover_t[i]
		var pos := Vector2.from_angle(_ang[i]) * 138.0 + Vector2(_shake(i), 0)
		var sz := 56.0 * (1.0 + 0.12 * h) * (0.6 + 0.4 * minf(ee, 1.0))
		_ga = base_a * clampf(p * 1.8, 0.0, 1.0)
		if h > 0.01:
			var wax := _wobble_pts(pos, sz * 0.68, float(i))
			_poly(wax, Color(0.6, 0.12, 0.08, h))
			_circ(pos + Vector2(-6, -8), sz * 0.35, Color(0.85, 0.3, 0.22, 0.5 * h))
			_outline(wax, Color(0.24, 0.03, 0.02, 0.6 * h), 1.2)
		_icon(i, pos, sz - 6.0)
		_circ(pos, (sz - 6.0) * 0.5, Color(0.91, 0.84, 0.68, 0.22 * (1.0 - h)))
		_cooldown(i, pos, sz - 6.0)
		_ring(pos, sz * 0.5 - 2.0, 2.2, ink)
		_ring(pos, sz * 0.5 - 5.5, 0.9, Color("b8873b"))
	_ga = base_a
	if _hover >= 0:
		_ga = base_a * (0.35 + 0.65 * _hover_t[_hover])
		var lines := _fit_text(_skill_name(_hover), Vector2(0, -8), 20, 150, ink)
		var sy := 8.0 + (lines - 1) * 10.0
		var swash := PackedVector2Array()
		for k in 13:
			var u := k / 12.0
			swash.append(Vector2(lerpf(-46.0, 46.0, u), sy + 4.0 * sin(u * PI) - 2.0 * u))
		draw_polyline(swash, _col(Color(ink, 0.7)), 1.4, true)
		_fit_text(_stat_line(_hover), Vector2(0, sy + 14.0), 11.5, 140, Color(ink, 0.8))
	else:
		_fit_text(_idle_text(), Vector2.ZERO, 16, 140, Color(ink, 0.65))
	_local_xf()
	_ga = t
	_knob(ink)


func _draw_dial() -> void:
	var lay := _layout()
	var gold := Color("d8b56a")
	var t := _t()
	var cl := _closing()
	var e := 1.0 if cl else _out_back(_raw, 1.2)
	var a0 := lay.start
	var a1 := lay.start + lay.sweep
	var step := lay.sweep / (COUNT - 1)
	_local_xf((1.0 - e) * -0.6, 0.85 + 0.15 * e)
	_ga = t
	_poly(_band_pts(184, 38, a0 - 0.12, a1 + 0.12), Color(0.04, 0.035, 0.03, 0.86))
	if _hover >= 0:
		var ha := _ang[_hover]
		_ring(Vector2.ZERO, 184, 36, Color(gold, 0.2 * _hover_t[_hover]), ha - step * 0.5, ha + step * 0.5)
	_ring(Vector2.ZERO, 165, 1.2, Color(gold, 0.85), a0 - 0.1, a1 + 0.1)
	_ring(Vector2.ZERO, 203, 1.2, Color(gold, 0.85), a0 - 0.1, a1 + 0.1)
	_circ(Vector2.ZERO, 121, Color("0b0a08"))
	_glow(Vector2(0, -20), 100, Color(0.14, 0.12, 0.09), 0.7)
	_ring(Vector2.ZERO, 121, 1.2, Color(gold, 0.6))
	var ticks := PackedVector2Array()
	for k in 55:
		if k % 6 == 0:
			continue
		var a := a0 + k * lay.sweep / 54.0
		ticks.append(Vector2.from_angle(a) * 172.0)
		ticks.append(Vector2.from_angle(a) * (184.0 if k % 3 == 0 else 180.0))
	draw_multiline(ticks, _col(Color(gold, 0.65)), 1.0)
	for i in COUNT:
		_text_center(ROMAN[i], Vector2.from_angle(_ang[i]) * 185.0, 14.0, Color("fff1c8") if i == _hover else Color(gold, 0.9))
	_local_xf()
	for i in _order():
		var p := _stag(i, 0.5)
		var ee := 1.0 if cl else _out_back(p, 1.8)
		var h := _hover_t[i]
		var pos := Vector2.from_angle(_ang[i]) * 146.0 * (0.8 + 0.2 * ee) + Vector2(_shake(i), 0)
		var sz := 46.0 * (1.0 + 0.16 * h) * clampf(ee, 0.0, 1.1)
		if sz <= 7.0:
			continue
		_ga = _slot_alpha(p, 1.7)
		_glow(pos, sz * 1.1, Color("ffcf73"), 0.7 * h)
		_circ(pos, sz * 0.5, Color("0b0a08"))
		_icon(i, pos, sz - 6.0)
		_cooldown(i, pos, sz - 6.0)
		_bevel(pos, sz * 0.5 - 1.0, 1.5 + 1.5 * h, GOLD_MID, GOLD_HI, GOLD_LO)
	_ga = t
	var needle := PackedVector2Array([Vector2(-26, -3.5), Vector2(0, -5.5), Vector2(108, -1.4), Vector2(116, 0), Vector2(108, 1.4), Vector2(0, 5.5), Vector2(-26, 3.5)])
	for k in needle.size():
		needle[k] = needle[k].rotated(_needle)
	var hi := Color("fff1c8")
	var lo := Color("7a5a1e")
	_poly_grad(needle, PackedColorArray([hi, hi, hi, gold, lo, lo, lo]))
	_outline(needle, Color(0, 0, 0, 0.6), 0.8)
	_circ(Vector2.ZERO, 9, Color("8a1010"))
	_circ(Vector2(-2, -3), 4.5, Color(1, 0.6, 0.54, 0.8))
	_bevel(Vector2.ZERO, 9, 2, GOLD_MID, GOLD_HI, GOLD_LO)
	if _hover >= 0:
		_ga = t * (0.35 + 0.65 * _hover_t[_hover])
		_text_center(ROMAN[_hover], Vector2(0, -50), 26.0, gold)
		_ga = t
	_center_info(44, 66, 17, 11, 150, Color("f3e2b5"), Color("bba67a"), Color(0.95, 0.89, 0.71, 0.7), false, 48.0, 15.0)


func _draw_ember() -> void:
	var t := _t()
	var cl := _closing()
	var e := 1.0 if cl else _out_cubic(_raw)
	var sc := (0.92 + 0.08 * t) if cl else (1.08 - 0.08 * e)
	_local_xf(0.0, sc)
	_ga = t
	if not cl:
		_glow(Vector2.ZERO, 230, Color("ffb347"), (1.0 - _raw) * 0.6)
	for k in 20:
		var a := k * TAU / 20.0 + _time * 0.05
		var fl := 0.5 + 0.5 * sin(_time * 7.0 + k * 1.7) * sin(_time * 3.1 + k)
		_glow(Vector2.from_angle(a) * 142.0, 42.0 + 10.0 * fl, Color("ff6a1a"), 0.16 + 0.14 * fl)
	_ring(Vector2.ZERO, 142, 48, Color("2c2724"))
	_ring(Vector2.ZERO, 142, 18, Color(0.29, 0.26, 0.24, 0.6))
	_ring(Vector2.ZERO, 166, 1.6, Color("6b625b"))
	_ring(Vector2.ZERO, 118, 1.6, Color("6b625b"))
	_ring(Vector2.ZERO, 161, 1.0, Color(0, 0, 0, 0.55))
	for k in 20:
		var a := k * TAU / 20.0 + PI / 20.0
		for r in [157.0, 127.0]:
			var rp := Vector2.from_angle(a) * float(r)
			_circ(rp, 2.4, Color("8a7f76"))
			_circ(rp - Vector2(0.7, 0.7), 0.9, Color("e0d6cc"))
	for em in _embers:
		var k2: float = em.life / em.max_life
		var ec := Color("ffe08a") if k2 < 0.3 else (Color("ff8a2a") if k2 < 0.7 else Color("d8341c"))
		_glow(em.pos, float(em.size) * 4.0, ec, (1.0 - k2) * 0.9)
	_local_xf()
	for i in _order():
		var p := _stag(i, 0.4)
		var ee := 1.0 if cl else _out_back(p, 1.5)
		var h := _hover_t[i]
		var pos := Vector2.from_angle(_ang[i]) * 142.0 + Vector2(_shake(i), 0)
		var sz := 54.0 * (1.0 + 0.14 * h) * (0.6 + 0.4 * minf(ee, 1.0))
		_ga = _slot_alpha(p, 1.7)
		_glow(pos, sz * 1.2, Color("ff7a1a"), 0.9 * h)
		_poly(_shape_pts(SH_RSQ, pos + Vector2(0, 3), sz), Color(0, 0, 0, 0.5))
		_poly(_shape_pts(SH_RSQ, pos, sz), Color("1c1917"))
		_icon(i, pos, sz - 11.0, SH_RSQ)
		_cooldown(i, pos, sz - 11.0, SH_RSQ)
		_outline(_shape_pts(SH_RSQ, pos, sz), Color("7a6f66").lerp(Color("ffb347"), h), 3.0)
		var q := sz * 0.5 - 4.5
		for d in [Vector2(-q, -q), Vector2(q, -q), Vector2(q, q), Vector2(-q, q)]:
			_circ(pos + d, 1.8, Color("ffd38a") if h > 0.5 else Color("9a8e84"))
	_ga = t
	_circ(Vector2.ZERO, 58, Color("1d1a18"))
	_glow(Vector2(-10, -14), 44, Color(0.23, 0.2, 0.19), 0.9)
	_ring(Vector2.ZERO, 58, 2, Color("7a6e66"))
	_ring(Vector2.ZERO, 52, 1, Color(0, 0, 0, 0.55))
	_center_info(-8, 21, 18, 11, 92, Color("ffd38a"), Color("e0a96a"), Color(1, 0.83, 0.54, 0.72), false, 0.0, 14.0)
	_knob(Color("ff8a2a"))


# ---------------------------------------------------------------- styles 11–20: the menu opens around the button

func _ellipse_pts(rx: float, ry: float, a0: float, a1: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in n + 1:
		var a := lerpf(a0, a1, float(k) / n)
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _closed_ellipse(rx: float, ry: float) -> PackedVector2Array:
	var pts := _ellipse_pts(rx, ry, 0.0, TAU, 48)
	pts.remove_at(pts.size() - 1)
	return pts


## Лепесток: две кубические кривые Безье, ось лепестка повёрнута на rot.
func _petal_pts(r0: float, r1: float, w: float, rot: float) -> PackedVector2Array:
	var ln := r1 - r0
	var a := Vector2(r0, 0)
	var b := Vector2(r1, 0)
	var pts := PackedVector2Array()
	for k in 13:
		pts.append(a.bezier_interpolate(Vector2(r0 + ln * 0.3, -w * 0.9), Vector2(r1 - ln * 0.25, -w * 1.15), b, k / 12.0).rotated(rot))
	for k in range(1, 12):
		pts.append(b.bezier_interpolate(Vector2(r1 - ln * 0.25, w * 1.15), Vector2(r0 + ln * 0.3, w * 0.9), a, k / 12.0).rotated(rot))
	return pts


func _quad_pt(a: Vector2, c: Vector2, b: Vector2, u: float) -> Vector2:
	return a * (1.0 - u) * (1.0 - u) + c * 2.0 * (1.0 - u) * u + b * u * u


## Стрельчатое окно витража, ось повёрнута на rot.
func _lancet_pts(r0: float, r1: float, step: float, rot: float, off: Vector2) -> PackedVector2Array:
	var w0 := r0 * tan(step * 0.5) * 0.78
	var rm := r1 - 30.0
	var w1 := rm * tan(step * 0.5) * 0.82
	var local := PackedVector2Array([Vector2(r0, -w0), Vector2(rm, -w1)])
	for k in range(1, 9):
		local.append(_quad_pt(Vector2(rm, -w1), Vector2(r1 - 6.0, -w1 * 0.85), Vector2(r1, 0), k / 8.0))
	for k in range(1, 9):
		local.append(_quad_pt(Vector2(r1, 0), Vector2(r1 - 6.0, w1 * 0.85), Vector2(rm, w1), k / 8.0))
	local.append(Vector2(r0, w0))
	return _rot_pts(local, rot, off)


func _rot_pts(pts: PackedVector2Array, rot: float, off: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in pts:
		out.append(Vector2(q).rotated(rot) + off)
	return out


func _gear_teeth(c: Vector2, r0: float, r1: float, teeth: int, rot: float, col: Color) -> void:
	var st := TAU / teeth
	for k in teeth:
		var a := rot + k * st
		_poly(PackedVector2Array([
			c + Vector2.from_angle(a) * (r0 - 1.0), c + Vector2.from_angle(a + st * 0.18) * r1,
			c + Vector2.from_angle(a + st * 0.47) * r1, c + Vector2.from_angle(a + st * 0.65) * (r0 - 1.0),
		]), col)


func _dashed_arc(r: float, a0: float, a1: float, c: Color, w: float) -> void:
	if a1 <= a0 or r <= 0.0:
		return
	var pattern := PackedFloat32Array([18.0, 7.0, 5.0, 9.0])
	var pts := PackedVector2Array()
	var a := a0
	var k := 0
	while a < a1:
		var len_a := pattern[k % 4] / r
		if k % 2 == 0:
			var b := minf(a + len_a, a1)
			var steps := maxi(1, int((b - a) * r / 6.0))
			for j in steps:
				pts.append(Vector2.from_angle(lerpf(a, b, float(j) / steps)) * r)
				pts.append(Vector2.from_angle(lerpf(a, b, float(j + 1) / steps)) * r)
		a += len_a
		k += 1
	if pts.size() >= 2:
		draw_multiline(pts, _col(c), w)


## Название выбранного умения (или подсказка) в плашке над меню.
func _around_label(y: float, bg: Color, border: Color, fg: Color, idle_fg: Color) -> void:
	var on := _hover >= 0
	var t := _t()
	_ga = t * ((0.4 + 0.6 * _hover_t[_hover]) if on else 0.85)
	var mp := skill_mp[_hover] if (on and _hover < skill_mp.size()) else 0
	var text := ("%s · MP %d" % [_skill_name(_hover), mp]) if on else _idle_text()
	var fs := 14.0 if on else 13.0
	var w := _text_w(text, fs) + 24.0
	var h := fs + 14.0
	var pill := _rrect_pts(Rect2(-w * 0.5, y - h * 0.5, w, h), h * 0.5)
	_poly(pill, bg)
	_outline(pill, border, 1.0)
	_text_center(text, Vector2(0, y), fs, fg if on else idle_fg)
	_ga = t


func _draw_trigger_around(open_t: float, pu: float, ga: float) -> void:
	match style:
		Style.HALO:
			_glow(Vector2.ZERO, 64.0 + 8.0 * pu, Color("ffe6a0"), 0.35 + 0.35 * pu * (1.0 - open_t * 0.6))
			for k in 12:
				var d := Vector2.from_angle(_time * 0.3 + k * TAU / 12.0)
				var n := d.orthogonal() * 1.6
				_poly(PackedVector2Array([d * 34.0 + n, d * (42.0 if k % 2 == 1 else 48.0), d * 34.0 - n]), Color(1, 0.95, 0.77, 0.55))
			_circ(Vector2.ZERO, 31, Color("f3cf7a"))
			_circ(Vector2(-5, -7), 20, Color(1, 0.98, 0.91, 0.55))
			_ring(Vector2.ZERO, 31, 1.5, Color(1, 1, 1, 0.85))
			_wheel_glyph(Color("5a3d0c"), open_t)
		Style.ARCH:
			_glow(Vector2.ZERO, 58.0 + 8.0 * pu, Color("6fe3ff"), ga * 0.75)
			_circ(Vector2.ZERO, 31, Color("7a7468"))
			_circ(Vector2(-6, -8), 20, Color(0.7, 0.67, 0.61, 0.5))
			_ring(Vector2.ZERO, 31, 2, Color("2b2723"))
			_ring(Vector2.ZERO, 25, 1.2, Color(0.44, 0.89, 1, 0.45 + 0.4 * pu))
			_wheel_glyph(Color("e8fbff"), open_t)
		Style.FLOWER:
			_glow(Vector2.ZERO, 58.0 + 8.0 * pu, Color("ff9cc8"), ga * 0.9)
			for k in 6:
				var pt := _petal_pts(4, 34, 12, k * TAU / 6.0 + _time * 0.2)
				_poly(pt, Color("f07fb0"))
				_outline(pt, Color(0.47, 0.12, 0.27, 0.5), 1.0)
			_circ(Vector2.ZERO, 12, Color("f0c040"))
			_circ(Vector2(-3, -3), 6, Color(1, 0.96, 0.76, 0.8))
			_cross_glyph(Color("5a1d3a"), open_t)
		Style.ORBIT:
			_glow(Vector2.ZERO, 70.0 + 10.0 * pu, Color("ffb347"), 0.4 + 0.3 * pu)
			var rays := PackedVector2Array()
			for k in 16:
				var d2 := Vector2.from_angle(_time * 0.5 + k * TAU / 16.0)
				rays.append(d2 * 33.0)
				rays.append(d2 * (38.0 if k % 2 == 1 else 42.0))
			draw_multiline(rays, _col(Color(1, 0.82, 0.47, 0.7)), 2.0)
			_circ(Vector2.ZERO, 30, Color("ffb13a"))
			_circ(Vector2(-6, -7), 18, Color(1, 0.96, 0.82, 0.7))
			_wheel_glyph(Color("7a3a06"), open_t, 12.0)
		Style.SHIELD:
			_glow(Vector2.ZERO, 60.0 + 8.0 * pu, Color("f3b45a"), ga * 0.85)
			_circ(Vector2.ZERO, 31, Color("5f5853"))
			_circ(Vector2(-7, -9), 18, Color(0.85, 0.82, 0.78, 0.45))
			_ring(Vector2.ZERO, 31, 2.5, Color("24201d"))
			for k in 8:
				_circ(Vector2.from_angle(k * TAU / 8.0) * 26.0, 1.8, Color("d8d0c8"))
			_wheel_glyph(Color("f3e2c0"), open_t, 12.0)
		Style.GLASS:
			_glow(Vector2.ZERO, 60.0 + 8.0 * pu, Color("fff1c8"), ga * 0.85)
			_circ(Vector2.ZERO, 31, Color("1d1b19"))
			for k in 6:
				var a := -PI / 2.0 + k * TAU / 6.0
				_poly(_sector_pts(9, 28, a - PI / 6.0, a + PI / 6.0, 1.6), Color(_skill_color((k * 3) % COUNT), 0.85))
			_circ(Vector2.ZERO, 8, Color("fff1c8"))
			_ring(Vector2.ZERO, 30, 2, Color("6f6a62"))
			_cross_glyph(Color.WHITE, open_t)
		Style.GEARS:
			_glow(Vector2.ZERO, 60.0 + 8.0 * pu, Color("ffb347"), ga * 0.85)
			_circ(Vector2.ZERO, 28, Color("c9963f"))
			_gear_teeth(Vector2.ZERO, 28, 35, 10, _time * 0.6, Color("c9963f"))
			_circ(Vector2.ZERO, 22, Color("2a1d10"))
			_ring(Vector2.ZERO, 22, 2, Color("6e4a1c"))
			_wheel_glyph(Color("ffd38a"), open_t, 12.0)
		Style.BUBBLES:
			_glow(Vector2.ZERO, 60.0 + 8.0 * pu, Color("7fdcff"), ga * 0.85)
			_circ(Vector2.ZERO, 31, Color(0.2, 0.62, 0.82, 0.9))
			_circ(Vector2(-6, -8), 18, Color(0.86, 0.98, 1, 0.5))
			_ring(Vector2.ZERO, 31, 1.5, Color(0.9, 0.98, 1, 0.9))
			_ring(Vector2.ZERO, 25, 3, Color(1, 1, 1, 0.8), PI * 1.1, PI * 1.45)
			_wheel_glyph(Color("0d3a50"), open_t, 12.0)
		Style.INK:
			_glow(Vector2.ZERO, 56.0 + 8.0 * pu, Color("ff6a4a"), ga * 0.6)
			_poly(_wobble_pts(Vector2.ZERO, 31, 2.0, 36, 0.05), Color("1a1714"))
			_circ(Vector2(14, -14), 5, Color("c8321e"))
			_wheel_glyph(Color("f4eee0"), open_t, 12.0)
		Style.CLEAN:
			_glow(Vector2.ZERO, 54.0 + 8.0 * pu, Color("7fa8ff"), ga * 0.6)
			_circ(Vector2(0, 4), 33, Color(0, 0, 0, 0.22))
			_circ(Vector2.ZERO, 31, Color.WHITE)
			var d1 := Vector2.from_angle(open_t * PI / 4.0) * 11.0
			var d3 := d1.orthogonal()
			_line(-d1, d1, Color("3d7bfd"), 4.5)
			_line(-d3, d3, Color("3d7bfd"), 4.5)


func _draw_halo() -> void:
	var rr := 104.0
	var t := _t()
	var cl := _closing()
	if not cl and _raw < 1.0:
		_ga = 1.0
		_glow(Vector2.ZERO, 120.0 + 80.0 * _raw, Color("fff0c0"), 0.55 * (1.0 - _raw))
		_ring(Vector2.ZERO, 34.0 + 150.0 * _out_cubic(_raw), 6.0 * (1.0 - _raw) + 0.05, Color(1, 0.95, 0.77, 0.85 * (1.0 - _raw)))
	_ga = t
	_ring(Vector2.ZERO, rr, 48, Color(1, 0.93, 0.7, 0.12))
	_ring(Vector2.ZERO, rr, 1.6, Color(1, 0.95, 0.77, 0.6))
	for k in 20:
		var d := Vector2.from_angle(_time * 0.15 + k * TAU / 20.0)
		var n := d.orthogonal() * 3.0
		_poly(PackedVector2Array([d * 36.0 + n, d * 150.0, d * 36.0 - n]), Color(1, 0.94, 0.78, 0.07))
	if _hover >= 0:
		var h := _hover_t[_hover]
		_grad_line(Vector2.ZERO, _pos[_hover], 10.0, Color(1, 0.95, 0.77, 0), Color(1, 0.98, 0.88, 0.3 * h))
		_grad_line(Vector2.ZERO, _pos[_hover], 2.2, Color(1, 0.95, 0.77, 0), Color(1, 0.98, 0.88, 0.9 * h))
	for i in _order():
		var p := _stag(i, 0.5)
		var e := p if cl else _out_back(p, 1.8)
		var h := _hover_t[i]
		var pos := Vector2.from_angle(_ang[i]) * (rr * e + 8.0 * h) + Vector2(_shake(i), 0)
		var sz := 50.0 * (0.5 + 0.5 * minf(e, 1.0)) * (1.0 + 0.2 * h)
		_ga = _slot_alpha(p, 2.0)
		_glow(pos, sz * 1.15, Color("ffe6a0"), 0.3 + 0.6 * h)
		_circ(pos, sz * 0.5, Color("1b1830"))
		_icon(i, pos, sz - 6.0)
		_cooldown(i, pos, sz - 6.0)
		_ring(pos, sz * 0.5 - 1.0, 2.0 + 1.5 * h, Color("f3d58e").lerp(Color.WHITE, h))
		_ring(pos, sz * 0.5 - 4.0, 2.0, Color(1, 1, 1, 0.6), PI * 1.1, PI * 1.45)
	_around_label(-(rr + 53.0), Color(1, 0.97, 0.88, 0.94), Color(0.66, 0.47, 0.16, 0.6), Color("5a3d0c"), Color("8a6a2a"))
	_knob(Color("ffd36b"))


func _draw_arch() -> void:
	var lay := _layout()
	var t := _t()
	var cl := _closing()
	var step := PI / 10.0
	_ga = t * 0.6
	_poly(_rot_pts(_closed_ellipse(222, 20), 0.0, Vector2(0, 6)), Color(0, 0, 0, 0.35))
	for i in _order():
		var p := _stag(i, 0.6)
		var e := 1.0 if cl else _out_back(p, 1.3)
		var h := _hover_t[i]
		var a := _ang[i]
		var dir := Vector2.from_angle(a)
		var off := dir * 10.0 * h + Vector2(_shake(i), -(1.0 - e) * 70.0)
		_ga = _slot_alpha(p, 2.2)
		var r1 := lay.r_out + 6.0 * h
		var pts := _sector_pts(lay.r_in, r1, a - step * 0.5, a + step * 0.5, 1.6, off)
		var cols := PackedColorArray()
		var half := int(pts.size() * 0.5)
		for k in pts.size():
			cols.append(Color("a9a294") if k < half else Color("56514a"))
		_poly_grad(pts, cols)
		_outline(pts, Color(0.11, 0.094, 0.078, 0.85), 1.5)
		_ring(off, r1 - 2.5, 1.5, Color(1, 0.98, 0.92, 0.35), a - step * 0.5 + 0.02, a + step * 0.5 - 0.02)
		_line(off + dir * (lay.r_in + 12.0), off + dir * (lay.r_in + 20.0) + dir.orthogonal() * 5.0, Color(0.12, 0.1, 0.086, 0.5), 1.0)
		if h > 0.01:
			_outline(_sector_pts(lay.r_in + 4.0, r1 - 4.0, a - step * 0.5 + 0.02, a + step * 0.5 - 0.02, 1.6, off), Color(0.44, 0.89, 1, 0.85 * h), 2.0)
			_glow(off + dir * lay.r, 64, Color("6fe3ff"), 0.35 * h)
		var ip := off + dir * lay.r
		var sz := 40.0 * (1.0 + 0.12 * h)
		_circ(ip, sz * 0.5 + 3.0, Color("2f2b26"))
		_icon(i, ip, sz, SH_CIRCLE, 1.0 - 0.35 * _any * (1.0 - h))
		_cooldown(i, ip, sz)
		_ring(ip, sz * 0.5 + 1.5, 2.0, Color(0, 0, 0, 0.6))
	_ga = t
	var ro := lay.r_out
	var key := PackedVector2Array([Vector2(-10, -ro + 2), Vector2(10, -ro + 2), Vector2(6, -ro - 16), Vector2(-6, -ro - 16)])
	_poly(key, Color("9c9587"))
	_outline(key, Color(0.11, 0.094, 0.078, 0.85), 1.2)
	_around_label(-(ro + 40.0), Color(0.18, 0.16, 0.145, 0.94), Color("8a8274"), Color("efe6d2"), Color("bdb4a3"))
	_knob(Color("6fe3ff"))


func _draw_flower() -> void:
	var lay := _layout()
	var t := _t()
	var cl := _closing()
	var mid := lay.start + lay.sweep * 0.5
	var grow := 1.0 if cl else _out_cubic(_raw)
	_ga = t
	if grow > 0.05:
		for k in 8:
			var leaf := _petal_pts(24, 24.0 + 30.0 * grow, 9, k * TAU / 8.0 + 0.2)
			_poly(leaf, Color("4a9f55"))
			_outline(leaf, Color(0.08, 0.24, 0.1, 0.6), 1.0)
	for i in _order():
		var rank := absf(i - (COUNT - 1) * 0.5) / ((COUNT - 1) * 0.5)
		var p := _stag(i, 0.45, rank)
		var e := 1.0 if cl else _out_back(p, 1.4)
		var h := _hover_t[i]
		var a := lerpf(mid, _ang[i], minf(1.0, e))
		var r1 := 34.0 + 126.0 * e + 18.0 * h
		var dir := Vector2.from_angle(a)
		_ga = _slot_alpha(p, 2.0)
		if r1 - 34.0 > 3.0:
			var pts := _petal_pts(34, r1, 24, a)
			var mid_col := Color("f07fb0").lerp(Color("ff5fa2"), h)
			var cols := PackedColorArray()
			for q in pts:
				var u := clampf((Vector2(q).dot(dir) - 34.0) / (r1 - 34.0), 0.0, 1.0)
				cols.append(Color("ffe3ef").lerp(mid_col, u / 0.55) if u < 0.55 else mid_col.lerp(Color("c94f86"), (u - 0.55) / 0.45))
			_poly_grad(pts, cols)
			if _any > 0.0 and h < 1.0:
				_poly(pts, Color(0.16, 0.04, 0.12, 0.25 * _any * (1.0 - h)))
			_outline(pts, Color(1, 1, 1, 0.95) if h > 0.5 else Color(0.47, 0.12, 0.27, 0.45), 1.2 + h)
			_line(dir * 40.0, dir * (r1 - 14.0), Color(1, 1, 1, 0.35), 1.0)
		var ip := dir * (116.0 * minf(e, 1.05) + 10.0 * h) + Vector2(_shake(i), 0)
		var sz := 44.0 * (1.0 + 0.14 * h) * clampf(e, 0.0, 1.0)
		if sz > 2.0:
			_circ(ip, sz * 0.5 + 2.5, Color("fff4f8"))
			_icon(i, ip, sz)
			_cooldown(i, ip, sz)
	_ga = t
	if _hover >= 0:
		var h2 := _hover_t[_hover]
		for k in 7:
			var tw := 0.5 + 0.5 * sin(_time * 4.0 + k * 1.7)
			var rr := 128.0 + 44.0 * float((k * 37) % 10) / 10.0
			var aa := _ang[_hover] + ((k % 3) - 1) * 0.13
			_glow(Vector2.from_angle(aa) * rr, 6.0 + 5.0 * tw, Color("fff2a8"), h2 * tw)
	_around_label(-208.0, Color(1, 0.96, 0.97, 0.95), Color(0.79, 0.31, 0.53, 0.6), Color("5a1d3a"), Color("8a4a68"))
	_knob(Color("ff9cc8"))


func _draw_orbit() -> void:
	var lay := _layout()
	var t := _t()
	var cl := _closing()
	var e0 := 1.0 if cl else _out_cubic(_raw)
	_ga = t
	_poly(_closed_ellipse(lay.rx + 50.0, lay.ry + 30.0), Color(0.05, 0.08, 0.2, 0.45))
	_poly(_closed_ellipse(lay.rx + 10.0, lay.ry + 6.0), Color(0.08, 0.12, 0.3, 0.4))
	_poly(_closed_ellipse(lay.rx * 0.6, lay.ry * 0.6), Color(0.1, 0.15, 0.36, 0.3))
	for k in _orbit_stars.size():
		var st := _orbit_stars[k]
		_circ(Vector2(st.x, st.y), st.z, Color(0.86, 0.92, 1, 0.25 + 0.5 * (0.5 + 0.5 * sin(_time * 2.0 + k * 0.7))))
	if e0 > 0.01:
		draw_polyline(_ellipse_pts(lay.rx, lay.ry, -PI / 2.0, -PI / 2.0 + TAU * e0, 72), _col(Color(0.63, 0.78, 1, 0.5)), 1.2, true)
	for f in [0.6, 1.18]:
		var dots := _ellipse_pts(lay.rx * f, lay.ry * f, 0.0, TAU, 64)
		var seg := PackedVector2Array()
		for k in range(0, dots.size() - 1, 2):
			seg.append(dots[k])
			seg.append(dots[k + 1])
		draw_multiline(seg, _col(Color(0.63, 0.78, 1, 0.28)), 1.0)
	_glow(Vector2.ZERO, 92, Color("ffb347"), 0.5)
	if _hover >= 0:
		var tp := _par[_hover]
		draw_polyline(_ellipse_pts(lay.rx, lay.ry, tp - 0.32, tp + 0.32, 16), _col(Color(0.84, 0.93, 1, 0.9 * _hover_t[_hover])), 3.0, true)
	var ord := Array(_order())
	ord.sort_custom(func(a: int, b: int) -> bool:
		if (a == _hover) != (b == _hover):
			return b == _hover
		return _pos[a].y < _pos[b].y)
	for i in ord:
		var p := _stag(i, 0.5)
		var e := 1.0 if cl else _out_cubic(p)
		var h := _hover_t[i]
		var tp2 := _par[i] - (1.0 - e) * 1.4
		var rs := 0.3 + 0.7 * e
		var pos := Vector2(cos(tp2) * lay.rx * rs + _shake(i), sin(tp2) * lay.ry * rs)
		var depth := 0.84 + 0.16 * ((sin(tp2) + 1.0) * 0.5)
		var sz := 46.0 * depth * (1.0 + 0.22 * h) * (0.4 + 0.6 * e)
		_ga = _slot_alpha(p, 2.0)
		_glow(pos, sz * 0.95, _skill_color(i), 0.25 + 0.5 * h)
		_icon(i, pos, sz)
		var sun := -pos.normalized()
		var circ := _shape_pts(SH_CIRCLE, pos, sz)
		var shade := PackedColorArray()
		for q in circ:
			var dd := (Vector2(q) - pos).normalized().dot(sun)
			shade.append(Color(0.01, 0.02, 0.06, clampf(-dd * 0.65, 0.0, 0.62)))
		_poly_grad(circ, shade)
		_cooldown(i, pos, sz)
		_ring(pos, sz * 0.5, 1.0 + 1.5 * h, Color("d6ecff") if h > 0.5 else Color(0.63, 0.78, 1, 0.5))
		if h > 0.05:
			var ma := _time * 2.4
			_circ(pos + Vector2(cos(ma) * sz * 0.78, sin(ma) * sz * 0.3), 3.2, Color(0.9, 0.94, 1, h))
	_around_label(-(lay.ry + 52.0), Color(0.05, 0.08, 0.2, 0.92), Color(0.63, 0.78, 1, 0.55), Color("d6ecff"), Color("9fb8d8"))
	_knob(Color("a0c8ff"))


func _draw_shield() -> void:
	var lay := _layout()
	var t := _t()
	var cl := _closing()
	var step := TAU / COUNT
	var e := 1.0 if cl else _out_back(_raw, 1.6)
	var sc := (0.9 + 0.1 * t) if cl else maxf(0.05, e)
	_local_xf((1.0 - minf(e, 1.0)) * -0.5, sc)
	_ga = t
	_circ(Vector2(3, 6), 134, Color(0, 0, 0, 0.35))
	for i in _order():
		var h := _hover_t[i]
		var a := _ang[i]
		var off := Vector2.from_angle(a) * 6.0 * h + Vector2(_shake(i), 0)
		var pts := _sector_pts(lay.r_in, lay.r_out, a - step * 0.5, a + step * 0.5, 0.6, off)
		_poly(pts, Color("e3d3b2") if i % 2 == 1 else Color("9e2b25"))
		var grain := Color(0.47, 0.35, 0.2, 0.22) if i % 2 == 1 else Color(0.16, 0.03, 0.02, 0.25)
		for k in 6:
			_ring(off, 48.0 + k * 13.0 + (i * 7) % 5, 1.0, grain, a - step * 0.5 + 0.02, a + step * 0.5 - 0.02)
		if h > 0.01:
			_poly(pts, Color(1, 0.93, 0.75, 0.3 * h))
		if _any > 0.0 and h < 1.0:
			_poly(pts, Color(0.04, 0.02, 0.016, 0.3 * _any * (1.0 - h)))
		_outline(pts, Color(0.12, 0.07, 0.04, 0.8), 1.5)
		var ip := off + Vector2.from_angle(a) * lay.r
		var sz := 40.0 * (1.0 + 0.14 * h)
		_circ(ip, sz * 0.5 + 2.5, Color(0.094, 0.055, 0.03, 0.88))
		_icon(i, ip, sz)
		_cooldown(i, ip, sz)
		_ring(ip, sz * 0.5 + 1.0, 1.5 + h, Color("f3c26a") if h > 0.5 else Color("2a1a10"))
	_ga = t
	_ring(Vector2.ZERO, lay.r_out + 5.0, 10.0, Color("4a4440"))
	_ring(Vector2.ZERO, lay.r_out + 8.0, 2.0, Color(0.86, 0.82, 0.78, 0.35), PI * 1.05, PI * 1.6)
	for k in 20:
		_circ(Vector2.from_angle(k * TAU / 20.0 + step / 4.0) * (lay.r_out + 5.0), 2.4, Color("9a918a"))
	_ring(Vector2.ZERO, lay.r_in, 4.0, Color("3a3532"))
	if _hover >= 0:
		var d := Vector2.from_angle(_ang[_hover])
		var n := d.orthogonal() * 8.0
		_poly(PackedVector2Array([d * (lay.r_out + 4.0), d * (lay.r_out + 18.0) + n, d * (lay.r_out + 18.0) - n]), Color(0.95, 0.76, 0.42, _hover_t[_hover]))
	_local_xf()
	_around_label(-(lay.r_out + 44.0), Color(0.23, 0.16, 0.11, 0.95), Color("c9a46a"), Color("f3e2c0"), Color("cdb58f"))
	_knob(Color("f3c26a"))


func _draw_glass() -> void:
	var t := _t()
	var cl := _closing()
	var step := TAU / COUNT
	var sweep_a := TAU + 1.0 if cl else (TAU + 1.0) * (-(cos(PI * clampf(_raw / 0.85, 0.0, 1.0)) - 1.0) * 0.5)
	_ga = t
	_circ(Vector2.ZERO, 140, Color(0.063, 0.055, 0.078, 0.62))
	_ring(Vector2.ZERO, 136, 9, Color("6f6a62"))
	_ring(Vector2.ZERO, 131, 1.5, Color(1, 0.98, 0.94, 0.3))
	for i in _order():
		var a := _ang[i]
		var h := _hover_t[i]
		var col := _skill_color(i)
		var appear := clampf((sweep_a - fposmod(a + PI / 2.0, TAU)) / 0.6, 0.0, 1.0)
		var off := Vector2(_shake(i), 0)
		var d := Vector2.from_angle(a)
		_ga = t * appear
		var pts := _lancet_pts(44, 128, step, a, off)
		_poly(pts, col.darkened(0.55))
		_poly(_lancet_pts(54, 118, step * 0.74, a, off), Color(col, 0.78 + 0.22 * h))
		if _any > 0.0 and h < 1.0:
			_poly(pts, Color(0.047, 0.04, 0.08, 0.5 * _any * (1.0 - h)))
		_outline(pts, Color("1d1b19"), 3.0)
		_line(off + d * 50.0, off + d * 68.0, Color("1d1b19"), 2.0)
		_line(off + d * 112.0, off + d * 124.0, Color("1d1b19"), 2.0)
		if h > 0.01:
			_ga = t
			_glow(d * 90.0, 84, col, 0.75 * h)
		_ga = t * appear
		var ip := d * 90.0 + off
		var sz := 38.0 * (1.0 + 0.16 * h)
		_circ(ip, sz * 0.5 + 3.0, Color("1d1b19"))
		_icon(i, ip, sz, SH_CIRCLE, 0.85 + 0.15 * h)
		_cooldown(i, ip, sz)
	_ga = t
	for i in COUNT:
		var rp := Vector2.from_angle(_ang[i] + step * 0.5) * 124.0
		_circ(rp, 7, Color(1, 0.77, 0.35, 0.78))
		_ring(rp, 7, 2.2, Color("1d1b19"))
	_ring(Vector2.ZERO, 40, 4, Color("1d1b19"))
	if not cl and _raw < 1.0:
		var sa := -PI / 2.0 + sweep_a
		var wedge := PackedVector2Array([Vector2.ZERO])
		for k in 9:
			wedge.append(Vector2.from_angle(sa - 0.4 + 0.4 * k / 8.0) * 136.0)
		_poly(wedge, Color(1, 0.98, 0.9, 0.22))
	var on := _hover >= 0
	_around_label(-170.0, Color(0.11, 0.106, 0.098, 0.95), _skill_color(_hover) if on else Color("6f6a62"), _skill_color(_hover) if on else Color("e8e2d6"), Color("b9b2a6"))
	_knob(Color("fff1c8"))


func _draw_gears() -> void:
	var t := _t()
	var cl := _closing()
	var step := TAU / COUNT
	var rot := 0.0 if cl else (1.0 - _out_back(_raw, 2.2)) * -0.63
	var brass_c := Color("c9963f")
	var dark := Color("4a3210")
	_ga = t
	var sp := Vector2.from_angle(-2.36) * 164.0
	_circ(sp, 18, brass_c)
	_gear_teeth(sp, 18, 26, 9, -rot * 4.4 - 0.3, brass_c)
	_ring(sp, 18, 1.2, dark)
	_circ(sp, 6, Color("2a1d10"))
	_ring(Vector2.ZERO, 104, 48, brass_c)
	_gear_teeth(Vector2.ZERO, 128, 138, 40, rot, brass_c)
	_ring(Vector2.ZERO, 126, 3, Color("f0c96e"), PI * 0.95, PI * 1.6)
	_ring(Vector2.ZERO, 82, 3, Color("6e4a1c"), PI * 0.95, PI * 1.6)
	_ring(Vector2.ZERO, 128, 1.5, dark)
	_ring(Vector2.ZERO, 80, 1.5, dark)
	for k in 5:
		var d := Vector2.from_angle(rot - PI / 2.0 + step * 0.5 + k * 2.0 * step)
		_line(d * 44.0, d * 82.0, Color("a87a30"), 10.0)
	_ring(Vector2.ZERO, 44, 8, Color("b8893a"))
	for i in COUNT:
		var sock := Vector2.from_angle(_ang[i] + rot) * 104.0
		_circ(sock, 23, Color("2a1d10"))
		_ring(sock, 23, 2, Color("6e4a1c"))
	for i in _order():
		var p := _stag(i, 0.4)
		var h := _hover_t[i]
		var pos := Vector2.from_angle(_ang[i] + rot) * 104.0 + Vector2(_shake(i), 0)
		var sz := 38.0 * (1.0 + 0.16 * h) * (0.5 + 0.5 * _out_cubic(p))
		_ga = _slot_alpha(p, 1.8)
		if h > 0.01:
			_glow(pos, 44, Color("ffb347"), 0.9 * h)
		_icon(i, pos, sz)
		_cooldown(i, pos, sz)
		_ring(pos, sz * 0.5 + 1.0, 2.0, Color("6e4a1c").lerp(Color("ffb347"), h))
	_ga = t
	if _hover >= 0:
		var d2 := Vector2.from_angle(_ang[_hover] + rot)
		var n := d2.orthogonal() * 7.0
		_poly(PackedVector2Array([d2 * 140.0, d2 * 156.0 + n, d2 * 156.0 - n]), Color(1, 0.7, 0.28, _hover_t[_hover]))
	_around_label(-182.0, Color(0.165, 0.114, 0.063, 0.95), brass_c, Color("ffd38a"), Color("c9a46a"))
	_knob(Color("ffb347"))


func _draw_bubbles() -> void:
	var t := _t()
	var cl := _closing()
	_ga = t
	for b in _embers:
		var k: float = b.life / b.max_life
		var bp: Vector2 = b.pos
		var br: float = b.size
		_ring(bp + Vector2(sin(_time * 3.0 + br * 7.0) * 3.0, 0), br, 1.0, Color(0.78, 0.96, 1, 0.6 * (1.0 - k)))
	for i in _order():
		var outer := i >= 4
		var p := _stag(i, 0.5, (0.45 + (i - 4) / 11.0) if outer else i / 10.0)
		var e := 1.0 if cl else _out_back(p, 1.7)
		var h := _hover_t[i]
		var pos := _pos[i] * e + Vector2(_shake(i), sin(_time * 2.0 + i * 1.3) * 2.5)
		var sz := (48.0 if outer else 54.0) * (0.5 + 0.5 * minf(e, 1.0)) * (1.0 + 0.2 * h) * (1.0 + 0.02 * sin(_time * 3.0 + i))
		_ga = _slot_alpha(p, 2.0)
		_glow(pos, sz, Color("7fdcff"), 0.2 + 0.5 * h)
		_circ(pos, sz * 0.5, Color(Color("1b6f8f").lerp(_skill_color(i), 0.3 * h), 0.38 + 0.12 * h))
		_icon(i, pos, sz * 0.74, SH_CIRCLE, 0.92)
		_cooldown(i, pos, sz * 0.74)
		_ring(pos, sz * 0.5, 1.4 + 1.2 * h, Color("e8fbff") if h > 0.5 else Color(0.62, 0.91, 1, 0.8))
		_ring(pos, sz * 0.5 - 4.0, 2.5, Color(1, 1, 1, 0.75), PI * 1.1, PI * 1.5)
		_circ(pos + Vector2(sz * 0.22, sz * 0.22), 2, Color(1, 1, 1, 0.6))
	_around_label(-230.0, Color(0.04, 0.16, 0.22, 0.92), Color(0.62, 0.91, 1, 0.6), Color("e8fbff"), Color("a9d8e8"))
	_knob(Color("9fe8ff"))


func _draw_ink() -> void:
	var lay := _layout()
	var t := _t()
	var cl := _closing()
	var q := 1.0 if cl else -(cos(PI * clampf(_raw / 0.8, 0.0, 1.0)) - 1.0) * 0.5
	var rr := lay.r
	var a0 := lay.start - 0.18
	var full := lay.sweep + 0.36
	var span := full * q
	_ga = t * 0.94
	_poly(_wobble_pts(Vector2.ZERO, 150, 1.0, 48, 0.012), Color(0.957, 0.933, 0.878, 0.9))
	_ga = t
	if span > 0.02:
		var outer := PackedVector2Array()
		var inner := PackedVector2Array()
		for k in 73:
			var u := k / 72.0
			var a := a0 + span * u
			var w := (14.0 + 4.0 * sin(u * 9.0 + 1.0)) * minf(1.0, u * full / 0.2) * pow(1.0 - pow(u * q, 3.0), 0.7) + 1.0
			outer.append(Vector2.from_angle(a) * (rr + w * 0.5))
			inner.append(Vector2.from_angle(a) * (rr - w * 0.5))
		inner.reverse()
		outer.append_array(inner)
		_poly(outer, Color("1a1714"))
		for o in [-12.0, 10.0, 14.0]:
			_dashed_arc(rr + o, a0 + 0.12, a0 + span * 0.92, Color(0.1, 0.09, 0.08, 0.55), 1.2)
	for i in _order():
		var a := _ang[i]
		var appear := clampf((span - (a - a0)) / 0.3, 0.0, 1.0)
		if appear <= 0.0:
			continue
		var h := _hover_t[i]
		var pos := Vector2.from_angle(a) * rr + Vector2(_shake(i), 0)
		var sz := 42.0 * (1.0 + 0.18 * h) * (0.7 + 0.3 * appear)
		_ga = appear * (t if cl else 1.0)
		_circ(pos, sz * 0.5 + 4.0, Color("f4eee0"))
		_icon(i, pos, sz)
		_cooldown(i, pos, sz)
		_ring(pos, sz * 0.5 + 1.0, 2.5, Color("1a1714"))
		if h > 0.01:
			var sp := Vector2.from_angle(a) * (rr - 40.0)
			var s := 22.0 * (0.6 + 0.4 * h)
			_ga = appear * h
			_poly(_rot_pts(_rrect_pts(Rect2(-s * 0.5, -s * 0.5, s, s), 3.0), -0.12, sp), Color("c8321e"))
			_outline(_rot_pts(_rrect_pts(Rect2(-s * 0.5 + 3.0, -s * 0.5 + 3.0, s - 6.0, s - 6.0), 2.0), -0.12, sp), Color(1, 0.94, 0.9, 0.85), 1.0)
			_text_center(str((i + 1) % 10), sp, s * 0.55, Color("fff4ec"))
	_ga = t
	_around_label(-(rr + 53.0), Color(0.957, 0.933, 0.878, 0.96), Color("1a1714"), Color("1a1714"), Color("5a534a"))
	_knob(Color("c8321e"))


func _draw_clean() -> void:
	var lay := _layout()
	var t := _t()
	var cl := _closing()
	_ga = t * 0.6
	_ring(Vector2.ZERO, lay.r, 1.0, Color(1, 1, 1, 0.35), lay.start - 0.12, lay.start + lay.sweep + 0.12)
	_ring(Vector2.ZERO, lay.r2, 1.0, Color(1, 1, 1, 0.35), lay.start - 0.12, lay.start + lay.sweep + 0.12)
	for i in _order():
		var p := _stag(i, 0.5, (0.5 if i % 2 == 1 else 0.0) + i / 20.0)
		var e := 1.0 if cl else _out_back(p, 2.2)
		var h := _hover_t[i]
		var pos := _pos[i] * e + Vector2(_shake(i), 0)
		var sz := 46.0 * (1.0 + 0.18 * h) * (0.4 + 0.6 * minf(e, 1.0))
		_ga = _slot_alpha(p, 2.0) * (1.0 - 0.25 * _any * (1.0 - h))
		_circ(pos + Vector2(0, 4), sz * 0.5 + 3.0, Color(0, 0, 0, 0.2))
		_circ(pos, sz * 0.5 + 3.0, Color(1, 1, 1, 0.96))
		_icon(i, pos, sz - 4.0)
		_cooldown(i, pos, sz - 4.0)
		if h > 0.01:
			_ring(pos, sz * 0.5 + 4.5, 3.0, Color(0.24, 0.48, 0.99, h))
	_ga = t
	_around_label(-(lay.r2 + 55.0), Color(1, 1, 1, 0.97), Color(0.11, 0.14, 0.2, 0.12), Color("1d2433"), Color("4a5468"))
	_knob(Color("3d7bfd"))
