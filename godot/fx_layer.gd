extends Control
## Вспышки и всплывающие числа на месте цели. Нужен только для демо-сцены.

class Burst:
	var pos := Vector2.ZERO
	var color := Color.WHITE
	var t := 0.0
	var text := ""
	var heal := false
	var sparks := PackedVector2Array()


var _bursts: Array[Burst] = []
var _glow: GradientTexture2D
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
	_glow = GradientTexture2D.new()
	_glow.gradient = g
	_glow.width = 64
	_glow.height = 64
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)


func spawn(pos: Vector2, color: Color, text: String, heal: bool) -> void:
	var b := Burst.new()
	b.pos = pos
	b.color = color
	b.text = text
	b.heal = heal
	for k in 14:
		b.sparks.append(Vector2.from_angle(randf() * TAU) * randf_range(60.0, 200.0) + Vector2(0, -40))
	_bursts.append(b)


func _process(delta: float) -> void:
	for k in range(_bursts.size() - 1, -1, -1):
		_bursts[k].t += delta / 1.1
		if _bursts[k].t >= 1.0:
			_bursts.remove_at(k)
	queue_redraw()


func _draw() -> void:
	var s := size.y / 576.0
	for b in _bursts:
		var k: float = b.t
		var e := 1.0 - pow(1.0 - minf(1.0, k * 1.6), 3.0)
		var col: Color = b.color
		var center: Vector2 = b.pos
		var r := (40.0 + 60.0 * e) * s
		draw_texture_rect(_glow, Rect2(center - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(col, 1.0 - k))
		draw_arc(center, (10.0 + 70.0 * e) * s, 0.0, TAU, 48, Color(col, 1.0 - k), maxf(0.5, 4.0 * (1.0 - e) * s), true)
		var tt := k * 1.1
		for v in b.sparks:
			var sp: Vector2 = center + (v * tt + Vector2(0, 120.0 * tt * tt)) * s
			draw_texture_rect(_glow, Rect2(sp - Vector2(8, 8) * s, Vector2(16, 16) * s), false, Color(col, 1.0 - k))
		var fs := maxi(8, roundi(26.0 * s))
		var label: String = b.text
		var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tp := center + Vector2(-w * 0.5, -(46.0 + 46.0 * e) * s)
		var a := 1.0 - maxf(0.0, k - 0.6) / 0.4
		var heal: bool = b.heal
		draw_string_outline(_font, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.85 * a))
		draw_string(_font, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Color("8dffa8") if heal else Color("ffe9a6"), a))
