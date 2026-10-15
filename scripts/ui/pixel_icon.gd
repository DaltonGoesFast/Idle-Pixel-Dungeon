## PixelIcon: an SPD item sprite drawn at an integer scale and centred on whole pixels (DECISIONS #89).
## SPD item frames are top-left anchored in their 16x16 cell with per-item sizes (ItemSpriteSheet.assignItemRect),
## so `texture` is trimmed to the visible w x h (data/item_rects.json) and that rect is centred, not the cell.
## The scale comes from the 16-px cell (`cell_px`), so every icon in one context is the same size.
## `badge` is SPD's second icon (item_icons.png): an 8px glyph centred in the top-right corner, the way
## ItemSlot lays out itemIcon once a ring, potion or scroll is identified (DECISIONS #108).
class_name PixelIcon
extends Control

var texture: Texture2D
var badge: Texture2D
var cell_px := 48

func _init() -> void:
	texture_filter = TEXTURE_FILTER_NEAREST
	mouse_filter = MOUSE_FILTER_IGNORE

func scale_k() -> int:
	return maxi(1, int(cell_px / 16))

## Integer rect the sprite occupies inside a box of `box` size (also used by the centring test).
static func layout(box: Vector2, tex_size: Vector2, k: int) -> Rect2:
	var sz := tex_size * k
	return Rect2(((box - sz) / 2.0).floor(), sz)

## SPD ItemSlot: the trimmed glyph is centred in an 8px cell flush with the top-right (Icons.SIZE).
static func badge_layout(box: Vector2, tex_size: Vector2, k: int) -> Rect2:
	var cell := 8.0 * k
	var bsz := tex_size * k
	var origin := Vector2(box.x - cell, 0.0)
	return Rect2(origin + ((Vector2(cell, cell) - bsz) / 2.0).floor(), bsz)

func _draw() -> void:
	if texture == null: return
	var k := scale_k()
	draw_texture_rect(texture, layout(size, texture.get_size(), k), false)
	if badge != null:
		draw_texture_rect(badge, badge_layout(size, badge.get_size(), k), false)
