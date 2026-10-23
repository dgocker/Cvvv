class_name RadialMenuMinimal
extends Control
## Радиальное меню «Минимал» на 10 умений: одна кнопка вместо панели быстрого доступа.
##
## Касание кнопки — меню остаётся открытым, умение выбирается тапом.
## Зажать кнопку и вести палец — выбор направлением, отпускание применяет умение.
## Вернуть палец в центр и отпустить — отмена. Тап мимо меню закрывает его.
## Узел растягивается на весь родительский Control. Размеры заданы для экрана высотой 576.

signal skill_activated(index: int, how: String) # how: "tap", "hold" или "flick"
signal skill_refused(index: int, seconds_left: float)
signal menu_opened(sticky: bool)
signal menu_closed

enum Mode { CLOSED, PRESS, DRAG, STICKY, CLOSING }

const COUNT := 10
const R_INNER := 104.0 # чётные ячейки
const R_OUTER := 166.0 # нечётные ячейки
const START := PI + PI / 20.0 # 189°: ячейка 0, слева
const STEP := PI / 10.0 # 18° на умение, ячейка 9 на 351°
const SWEEP := STEP * (COUNT - 1)
const TOLERANCE := 0.4 # насколько ниже горизонта ещё ловится крайнее умение, рад
const SLOT := 46.0
const HIT_MIN := 36.0 # тап ближе к центру — закрыть
const HIT_MAX := 214.0 # тап дальше — закрыть
const BUTTON_R := 31.0
const OPEN_TIME := 0.38
const CLOSE_TIME := 0.16
const DIM := 0.42
const ACCENT := Color("3d7bfd")
const INK := Color("1d2433")
const INK_QUIET := Color("4a5468")

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
## Радиус мёртвой зоны в единицах дизайна.
@export_range(8.0, 80.0, 1.0) var dead_zone := 26.0
@export_range(0.5, 2.0, 0.05) var size_mul := 1.0
## Не закрывать меню после выбора умения.
@export var keep_open := false
## Самому запускать перезарядку из skill_cooldowns при применении.
@export var auto_cooldown := true
## Рисовать мёртвую зону и границы секторов (для отладки).
@export var show_zones := false
## Расстояние от нижнего края экрана до центра кнопки, в единицах дизайна.
@export var trigger_bottom := 50.0
## Короткая вибрация на телефоне (Android: включите разрешение VIBRATE в пресете экспорта).
@export var vibrate := true

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

var _s := 1.0
var _trig := Vector2.ZERO
var _cur := Transform2D.IDENTITY
var _ga := 1.0
var _glow_tex: GradientTexture2D
var _font: Font


func _init() -> void:
	_hover_t.resize(COUNT)
	_shake_at.resize(COUNT)
	_shake_at.fill(-100.0)
	_cd_end.resize(COUNT)
	_cd_total.resize(COUNT)
	_cd_total.fill(1.0)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()
	_glow_tex = _make_glow_texture()
	_update_view()


# ---------------------------------------------------------------- public API

func open_menu() -> void:
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


# ---------------------------------------------------------------- geometry

## Позиция ячейки i относительно центра кнопки, в единицах дизайна.
func slot_position(i: int) -> Vector2:
	return Vector2.from_angle(START + i * STEP) * (R_OUTER if i % 2 == 1 else R_INNER)


## Смещение пальца (в единицах дизайна) → номер умения или -1. Выбор только по направлению.
func _pick(v: Vector2) -> int:
	var rel := wrapf(v.angle() - (START + SWEEP * 0.5), -PI, PI) + SWEEP * 0.5
	if rel < -TOLERANCE or rel > SWEEP + TOLERANCE:
		return -1
	return clampi(roundi(rel / STEP), 0, COUNT - 1)


## Тап по открытому меню: номер умения или -1 (центр или мимо меню).
func _sticky_zone(p: Vector2) -> int:
	var v := (p - _trig) / _s
	var d := v.length()
	if d < HIT_MIN or d > HIT_MAX:
		return -1
	return _pick(v)


func _update_view() -> void:
	var need_w := 2.0 * 200.0 + 16.0
	var need_h := trigger_bottom + 236.0 + 10.0
	_s = clampf(minf(size.y / 576.0, minf(size.x / need_w, size.y / need_h)), 0.3, 1.7) * size_mul
	_trig = Vector2(size.x * 0.5, size.y - trigger_bottom * _s)


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
		# нажатие на кнопку при открытом меню: ведение пальцем выбирает, отпускание на месте закрывает
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
			hv = _pick(v)
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
		_open_at = _time - (_raw * OPEN_TIME if _mode == Mode.CLOSING else 0.0)
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
		# умение на перезарядке: ячейка трясётся, меню остаётся открытым для другого выбора
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
	if _mode == Mode.PRESS and _time - _press_at >= hold_delay:
		_open(Mode.DRAG)
		_buzz(12)
	if _mode == Mode.DRAG or _mode == Mode.STICKY:
		_raw = clampf((_time - _open_at) / OPEN_TIME, 0.0, 1.0)
	elif _mode == Mode.CLOSING:
		_raw = _close_from * (1.0 - clampf((_time - _close_at) / CLOSE_TIME, 0.0, 1.0))
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
	queue_redraw()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var shown := _mode != Mode.CLOSED and _mode != Mode.PRESS
	var t := _t() if shown else 0.0
	_xf(Transform2D.IDENTITY)
	_ga = 1.0
	if shown:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.016, 0.024, 0.04, DIM * t))
		_xf(Transform2D(0.0, Vector2(_s, _s), 0.0, _trig))
		_draw_menu(t)
		_draw_cast_flash()
		if show_zones:
			_draw_zones()
	_draw_button(t)
	_xf(Transform2D.IDENTITY)


func _draw_menu(t: float) -> void:
	var cl := _mode == Mode.CLOSING
	_ga = t * 0.6
	_ring(Vector2.ZERO, R_INNER, 1.0, Color(1, 1, 1, 0.35), START - 0.12, START + SWEEP + 0.12)
	_ring(Vector2.ZERO, R_OUTER, 1.0, Color(1, 1, 1, 0.35), START - 0.12, START + SWEEP + 0.12)
	for i in _order():
		# внутренний ряд вылетает раньше внешнего
		var p := _stag(0.5, (0.5 if i % 2 == 1 else 0.0) + i / 20.0)
		var e := 1.0 if cl else _out_back(p, 2.2)
		var h := _hover_t[i]
		var pos := slot_position(i) * e + Vector2(_shake(i), 0.0)
		var sz := SLOT * (1.0 + 0.18 * h) * (0.4 + 0.6 * minf(e, 1.0))
		_ga = clampf(p * 2.0, 0.0, 1.0) * (t if cl else 1.0) * (1.0 - 0.25 * _any * (1.0 - h))
		_circ(pos + Vector2(0, 4), sz * 0.5 + 3.0, Color(0, 0, 0, 0.2))
		_circ(pos, sz * 0.5 + 3.0, Color(1, 1, 1, 0.96))
		_icon(i, pos, sz - 4.0)
		_cooldown(i, pos, sz - 4.0)
		if h > 0.01:
			_ring(pos, sz * 0.5 + 4.5, 3.0, Color(ACCENT, h))
	_ga = t
	_label(-(R_OUTER + 55.0))
	_knob()


func _draw_button(t: float) -> void:
	var ps := 1.0 - 0.08 * _pressed
	_xf(Transform2D(0.0, Vector2(_s * ps, _s * ps), 0.0, _trig))
	_ga = 1.0
	var pu := 0.5 + 0.5 * sin(_time * 3.0)
	_glow(Vector2.ZERO, 54.0 + 8.0 * pu, Color("7fa8ff"), 0.18 + 0.22 * pu * (1.0 - t))
	_circ(Vector2(0, 4), BUTTON_R + 2.0, Color(0, 0, 0, 0.22))
	_circ(Vector2.ZERO, BUTTON_R, Color.WHITE)
	# «+» поворачивается в «×», пока меню открыто
	var d1 := Vector2.from_angle(t * PI / 4.0) * 11.0
	var d2 := d1.orthogonal()
	draw_line(-d1, d1, ACCENT, 4.5, true)
	draw_line(-d2, d2, ACCENT, 4.5, true)
	_xf(Transform2D(0.0, Vector2(_s, _s), 0.0, _trig))
	if _mode == Mode.PRESS and hold_delay > 0.0:
		var hold := clampf((_time - _press_at) / hold_delay, 0.0, 1.0)
		_ring(Vector2.ZERO, 40.0, 3.5, ACCENT, -PI / 2.0, -PI / 2.0 + TAU * hold)


func _label(y: float) -> void:
	var on := _hover >= 0
	var t := _t()
	_ga = t * ((0.4 + 0.6 * _hover_t[_hover]) if on else 0.85)
	var mp := skill_mp[_hover] if (on and _hover < skill_mp.size()) else 0
	var text := ("%s · MP %d" % [_skill_name(_hover), mp]) if on else ("Ведите к умению" if _mode == Mode.DRAG else "Выберите умение")
	var fs := 14.0 if on else 13.0
	var w := _text_w(text, fs) + 24.0
	var h := fs + 14.0
	var pill := _rrect_pts(Rect2(-w * 0.5, y - h * 0.5, w, h), h * 0.5)
	_poly(pill, Color(1, 1, 1, 0.97))
	_outline(pill, Color(0.11, 0.14, 0.2, 0.12), 1.0)
	_text_center(text, Vector2(0, y), fs, INK if on else INK_QUIET)
	_ga = t


## Точка-«стик»: куда сейчас ведёт палец.
func _knob() -> void:
	if not _has_cursor:
		return
	var k := _cursor
	if k.length() > R_OUTER:
		k = k.normalized() * R_OUTER
	if k.length() < 2.0:
		return
	var dist := k.length()
	var dir := k / dist
	var dash := PackedVector2Array()
	var d := 0.0
	while d < dist:
		dash.append(dir * d)
		dash.append(dir * minf(d + 3.0, dist))
		d += 8.0
	draw_multiline(dash, _col(Color(ACCENT, 0.55)), 1.5)
	_glow(k, 24.0, ACCENT, 0.9)
	_circ(k, 6.0, Color.WHITE)
	_ring(k, 6.0, 2.0, ACCENT)


func _draw_cast_flash() -> void:
	if _cast_index < 0:
		return
	var k := clampf((_time - _cast_at) / 0.52, 0.0, 1.0)
	if k >= 1.0:
		return
	var pos := slot_position(_cast_index)
	var c := _skill_color(_cast_index)
	_ga = 1.0
	_glow(pos, 40.0 + 50.0 * k, c, 1.0 - k)
	_ring(pos, 24.0 + 40.0 * (1.0 - pow(1.0 - k, 3.0)), 3.0 * (1.0 - k) + 0.05, Color(c, 1.0 - k))


func _draw_zones() -> void:
	_ga = 1.0
	_circ(Vector2.ZERO, dead_zone, Color(1, 0.3, 0.3, 0.18))
	_ring(Vector2.ZERO, dead_zone, 1.0, Color(1, 0.47, 0.47, 0.9))
	_ring(Vector2.ZERO, HIT_MIN, 1.0, Color(0.47, 0.86, 1, 0.8))
	_ring(Vector2.ZERO, HIT_MAX, 1.0, Color(0.47, 0.86, 1, 0.8))
	var lines := PackedVector2Array()
	for i in COUNT + 1:
		var a := START + (i - 0.5) * STEP
		lines.append(Vector2.from_angle(a) * dead_zone)
		lines.append(Vector2.from_angle(a) * HIT_MAX)
	draw_multiline(lines, _col(Color(1, 1, 1, 0.55)), 1.0)


# ---------------------------------------------------------------- helpers

func _t() -> float:
	if _mode == Mode.CLOSING:
		return -(cos(PI * _raw) - 1.0) * 0.5
	return 1.0 - pow(1.0 - _raw, 3.0)


func _out_back(x: float, k: float = 1.70158) -> float:
	var u := x - 1.0
	return 1.0 + (k + 1.0) * u * u * u + k * u * u


func _stag(spread: float, rank: float) -> float:
	if _mode == Mode.CLOSING:
		return _raw
	return clampf((_raw - spread * rank) / (1.0 - spread), 0.0, 1.0)


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


func _skill_color(i: int) -> Color:
	return skill_colors[i] if i >= 0 and i < skill_colors.size() else Color.WHITE


func _skill_name(i: int) -> String:
	return skill_names[i] if i < skill_names.size() else "Умение %d" % (i + 1)


func _xf(t: Transform2D) -> void:
	_cur = t
	draw_set_transform_matrix(t)


func _col(c: Color, a: float = 1.0) -> Color:
	return Color(c.r, c.g, c.b, clampf(c.a * a * _ga, 0.0, 1.0))


func _circ(p: Vector2, r: float, c: Color) -> void:
	if r > 0.05:
		draw_circle(p, r, _col(c))


func _ring(p: Vector2, r: float, w: float, c: Color, a0: float = 0.0, a1: float = TAU) -> void:
	if r <= 0.05 or w <= 0.0 or absf(a1 - a0) < 0.001:
		return
	draw_arc(p, r, a0, a1, clampi(int(r * absf(a1 - a0) / 6.0), 12, 96), _col(c), w, true)


func _poly(pts: PackedVector2Array, c: Color) -> void:
	if pts.size() >= 3:
		draw_colored_polygon(pts, _col(c))


func _outline(pts: PackedVector2Array, c: Color, w: float) -> void:
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, _col(c), w, true)


func _circle_pts(p: Vector2, sz: float) -> PackedVector2Array:
	var h := maxf(sz, 0.0) * 0.5
	var n := clampi(int(h * 0.9), 16, 40)
	var pts := PackedVector2Array()
	for k in n:
		pts.append(p + Vector2.from_angle(TAU * k / n) * h)
	return pts


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


## Иконка, обрезанная по кругу: текстурированный полигон.
func _icon(i: int, p: Vector2, sz: float) -> void:
	if sz < 1.0:
		return
	var pts := _circle_pts(p, sz)
	var tex: Texture2D = icons[i] if i < icons.size() else null
	if tex == null:
		_poly(pts, _skill_color(i).darkened(0.45))
		_text_center(str((i + 1) % 10), p, sz * 0.42, Color.WHITE)
		return
	var uvs := PackedVector2Array()
	var o := p - Vector2(sz, sz) * 0.5
	for q in pts:
		uvs.append((q - o) / sz)
	draw_colored_polygon(pts, _col(Color.WHITE), uvs, tex)


func _cooldown(i: int, p: Vector2, sz: float) -> void:
	var left := _cd_end[i] - _time
	if left <= 0.0 or sz < 4.0:
		return
	var f := clampf(left / maxf(_cd_total[i], 0.01), 0.0, 0.999)
	var pie := PackedVector2Array([p])
	var n := maxi(3, int(40.0 * f))
	for k in n + 1:
		pie.append(p + Vector2.from_angle(-PI / 2.0 + TAU * f * k / n) * sz * 0.5)
	_poly(pie, Color(0, 0, 0, 0.62))
	_text_center(str(ceili(left)), p, sz * 0.36, Color.WHITE, Color(0, 0, 0, 0.85), 3.0)


func _glow(p: Vector2, r: float, c: Color, a: float) -> void:
	if a <= 0.004 or r <= 0.0:
		return
	draw_texture_rect(_glow_tex, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, _col(c, minf(a, 1.0)))


func _make_glow_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.22, 0.55, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.16), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex


func _text_w(s: String, fs: float) -> float:
	return _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(1, roundi(fs))).x


## Текст по центру точки; рисуется в экранных пикселях, чтобы шрифт оставался чётким.
func _text_center(s: String, p: Vector2, fs: float, c: Color, outline: Color = Color(0, 0, 0, 0), ow: float = 0.0) -> void:
	var sc := _cur.get_scale().x
	var size_i := maxi(1, roundi(fs * sc))
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_i).x
	var base := _cur * p + Vector2(-w * 0.5, (_font.get_ascent(size_i) - _font.get_descent(size_i)) * 0.5)
	var saved := _cur
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if outline.a > 0.0 and ow > 0.0:
		draw_string_outline(_font, base, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_i, maxi(1, roundi(ow * sc)), _col(outline))
	draw_string(_font, base, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_i, _col(c))
	draw_set_transform_matrix(saved)
