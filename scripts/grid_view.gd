## Draws the 8x8 combat grid with SPD tiles/sprites (nearest filter) and handles taps.
extends Control

signal tapped(cell: Vector2i)

var combat: Combat
var tex := {}
var tiles: Texture2D
var anim_t := 0.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	tiles = load("res://assets/tiles/tiles_sewers.png")
	for n in ["warrior","rat","gnoll","crab","snake"]:
		tex[n] = load("res://assets/sprites/%s.png" % n)
	resized.connect(queue_redraw)

func _process(d: float) -> void:
	anim_t += d
	queue_redraw()

func cell_size() -> float:
	# Integer-scale SPD's 16px tiles when possible (crisp pixels), else whole-pixel cells
	var raw := floorf(minf(size.x, size.y) / Combat.SIZE)
	if raw >= 16.0: return floorf(raw / 16.0) * 16.0
	return raw

func origin() -> Vector2:
	var cs := cell_size() * Combat.SIZE
	return ((size - Vector2(cs, cs)) / 2.0).floor()

# SPD tile sheet indices (16x16 px, 16 per row) from DungeonTileSheet.java
const TILE_IDX := {Combat.T.FLOOR: 0, Combat.T.GRASS: 66, Combat.T.WALL: 48, Combat.T.DOOR: 56, Combat.T.CHASM: 24}

func _draw() -> void:
	if combat == null: return
	var cs := cell_size(); var o := origin()
	for y in Combat.SIZE:
		for x in Combat.SIZE:
			var t: int = combat.terrain[y][x]
			var r := Rect2(o + Vector2(x, y) * cs, Vector2(cs, cs))
			if t == Combat.T.GRASS or t == Combat.T.DOOR:
				_tile(r, 0)
			_tile(r, TILE_IDX[t])
			if t == Combat.T.CHASM: draw_rect(r, Color(0,0,0,0.55))
	var hp: Vector2i = combat.hero.pos
	for d in Combat.DIRS:
		var n: Vector2i = hp + d
		if combat.passable(n) or combat.unit_at(n) != null:
			draw_rect(Rect2(o + Vector2(n) * cs, Vector2(cs, cs)).grow(-2), Color(1,1,1,0.18), false, 2.0)
	for dz in combat.danger:
		var pulse := 0.35 + 0.2 * sin(anim_t * 8.0)
		draw_rect(Rect2(o + Vector2(dz.pos) * cs, Vector2(cs, cs)), Color(1,0,0,pulse))
	for u in combat.units:
		if u.hp <= 0: continue
		var frame := 0 if fmod(anim_t, 1.0) < 0.6 else 1
		var src := Rect2(frame * u.fw, 0, u.fw, u.fh)
		var scale := floorf(cs / 16.0) if cs >= 16.0 else cs / 16.0
		var sz := Vector2(u.fw, u.fh) * scale
		var pos := (o + Vector2(u.pos) * cs + Vector2((cs - sz.x) / 2.0, cs - sz.y)).floor()
		draw_texture_rect_region(tex[u.sprite], Rect2(pos, sz), src)
		var bar := Rect2(o + Vector2(u.pos) * cs + Vector2(2, 1), Vector2((cs - 4) * float(u.hp) / u.ht, maxf(3, cs * 0.06)))
		draw_rect(bar, Color.GREEN if u == combat.hero else Color.RED)

func _tile(r: Rect2, idx: int) -> void:
	draw_texture_rect_region(tiles, r, Rect2((idx % 16) * 16, (idx / 16) * 16, 16, 16))

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var c: Vector2 = ((e.position - origin()) / cell_size()).floor()
		var cell := Vector2i(c)
		if cell.x >= 0 and cell.y >= 0 and cell.x < Combat.SIZE and cell.y < Combat.SIZE:
			tapped.emit(cell)
		accept_event()
