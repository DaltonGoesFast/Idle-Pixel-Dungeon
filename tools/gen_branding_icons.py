#!/usr/bin/env python3
"""Generate editable Idle PD app-icon templates with safe-zone guides."""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1] / "assets" / "branding"

BG = (26, 22, 19, 255)
STONE = (58, 52, 46, 255)
SAFE = (255, 210, 122, 180)
SUBJECT = (255, 140, 40, 255)
TRANS = (0, 0, 0, 0)


def checker(img, cell=16, a=(40, 36, 32, 255), b=(32, 28, 24, 255)):
	d = ImageDraw.Draw(img)
	w, h = img.size
	for y in range(0, h, cell):
		for x in range(0, w, cell):
			fill = a if ((x // cell) + (y // cell)) % 2 == 0 else b
			d.rectangle([x, y, x + cell - 1, y + cell - 1], fill=fill)


def draw_campfire(draw, cx, cy, s):
	draw.rectangle([cx - s, cy + s // 2, cx + s, cy + s], fill=(90, 55, 30, 255))
	draw.rectangle([cx - s // 2, cy + s // 3, cx + s // 2, cy + s // 2], fill=(70, 40, 20, 255))
	pts = [
		(cx, cy - s),
		(cx + s * 2 // 3, cy + s // 4),
		(cx + s // 4, cy),
		(cx, cy + s // 3),
		(cx - s // 4, cy),
		(cx - s * 2 // 3, cy + s // 4),
	]
	draw.polygon(pts, fill=SUBJECT)
	pts2 = [
		(cx, cy - s // 2),
		(cx + s // 3, cy + s // 8),
		(cx, cy + s // 5),
		(cx - s // 3, cy + s // 8),
	]
	draw.polygon(pts2, fill=(255, 230, 120, 255))


def draw_pd_glyph(draw, cx, cy, s):
	# P
	thick = max(1, s // 3)
	draw.rectangle([cx - s, cy - s, cx - s + thick, cy + s], fill=SUBJECT)
	draw.rectangle([cx - s, cy - s, cx, cy - s + thick], fill=SUBJECT)
	draw.rectangle([cx - s, cy - s // 4, cx, cy - s // 4 + thick], fill=SUBJECT)
	draw.rectangle([cx - max(1, s // 6), cy - s, cx, cy - s // 4], fill=SUBJECT)
	# D
	ox = cx + s // 4
	draw.rectangle([ox, cy - s, ox + thick, cy + s], fill=SUBJECT)
	draw.rectangle([ox, cy - s, ox + s, cy - s + thick], fill=SUBJECT)
	draw.rectangle([ox, cy + s - thick, ox + s, cy + s], fill=SUBJECT)
	draw.rectangle([ox + s - thick, cy - s, ox + s, cy + s], fill=SUBJECT)


def upscale_nn(src, factor):
	return src.resize((src.width * factor, src.height * factor), Image.NEAREST)


def master_32():
	img = Image.new("RGBA", (32, 32), BG)
	d = ImageDraw.Draw(img)
	d.rectangle([0, 0, 31, 31], outline=(220, 60, 60, 255))
	margin = 5
	d.rectangle([margin, margin, 31 - margin, 31 - margin], outline=(255, 210, 122, 255))
	draw_campfire(d, 16, 17, 7)
	return img


def master_512_from_32(m32):
	big = upscale_nn(m32, 16)
	d = ImageDraw.Draw(big)
	d.rectangle([8, 480, 24, 496], fill=(220, 60, 60, 255))
	d.rectangle([32, 480, 48, 496], fill=(255, 210, 122, 255))
	d.rectangle([56, 480, 72, 496], fill=SUBJECT)
	return big


def guide_512():
	img = Image.new("RGBA", (512, 512), BG)
	checker(img, 32)
	d = ImageDraw.Draw(img)
	cx = cy = 256
	safe_r = int(512 * 0.33)
	for r in range(safe_r + 1, 256):
		d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(220, 60, 60, 50))
	d.ellipse([cx - safe_r, cy - safe_r, cx + safe_r, cy + safe_r], outline=SAFE, width=4)
	d.rectangle([0, 0, 511, 511], outline=(220, 60, 60, 200), width=4)
	sb = int(safe_r * 0.85)
	d.rectangle([cx - sb, cy - sb, cx + sb, cy + sb], outline=(100, 180, 255, 200), width=2)
	draw_campfire(d, cx, cy, sb // 2)
	d.rectangle([16, 16, 40, 40], fill=(220, 60, 60, 255))
	d.rectangle([48, 16, 72, 40], fill=(255, 210, 122, 255))
	d.rectangle([80, 16, 104, 40], fill=(100, 180, 255, 255))
	d.rectangle([112, 16, 136, 40], fill=SUBJECT)
	return img


def android_template(size=432, with_subject=True, mono=False, bg_only=False):
	img = Image.new("RGBA", (size, size), TRANS if not bg_only else STONE)
	d = ImageDraw.Draw(img)
	cx = cy = size // 2
	# Adaptive keyline: 66dp subject on 108dp canvas
	safe_r = int(size * (66 / 108) / 2)

	if bg_only:
		for i in range(0, size, 24):
			d.line([(i, 0), (i, size)], fill=(48, 44, 40, 255), width=1)
			d.line([(0, i), (size, i)], fill=(48, 44, 40, 255), width=1)
		m = 8
		for x0, y0 in [(0, 0), (size - m, 0), (0, size - m), (size - m, size - m)]:
			d.rectangle([x0, y0, x0 + m - 1, y0 + m - 1], fill=(255, 210, 122, 80))
		# faint safe circle so you know what stays visible under round masks
		d.ellipse(
			[cx - safe_r, cy - safe_r, cx + safe_r, cy + safe_r],
			outline=(255, 210, 122, 100),
			width=2,
		)
		return img

	d.rectangle([0, 0, size - 1, size - 1], outline=(220, 60, 60, 200), width=max(2, size // 108))
	outer_r = size // 2 - 2
	for r in range(safe_r + 1, outer_r + 1):
		alpha = 40 if r > safe_r + 8 else 90
		d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(220, 60, 60, alpha))
	d.ellipse(
		[cx - safe_r, cy - safe_r, cx + safe_r, cy + safe_r],
		outline=SAFE,
		width=max(2, size // 72),
	)
	d.line([(cx, cy - 12), (cx, cy + 12)], fill=SAFE, width=2)
	d.line([(cx - 12, cy), (cx + 12, cy)], fill=SAFE, width=2)

	if not with_subject:
		return img

	if mono:
		tmp = Image.new("RGBA", (size, size), TRANS)
		td = ImageDraw.Draw(tmp)
		draw_campfire(td, cx, cy, safe_r // 2)
		px = tmp.load()
		out = Image.new("RGBA", (size, size), TRANS)
		op = out.load()
		for y in range(size):
			for x in range(size):
				if px[x, y][3] > 0:
					op[x, y] = (255, 255, 255, 255)
		guide = Image.new("RGBA", (size, size), TRANS)
		gd = ImageDraw.Draw(guide)
		gd.ellipse(
			[cx - safe_r, cy - safe_r, cx + safe_r, cy + safe_r],
			outline=(128, 128, 128, 160),
			width=2,
		)
		gd.rectangle([0, 0, size - 1, size - 1], outline=(80, 80, 80, 120), width=2)
		return Image.alpha_composite(out, guide)

	draw_campfire(d, cx, cy, safe_r // 2)
	return img


def favicon(size, use_pd=False):
	img = Image.new("RGBA", (size, size), BG)
	d = ImageDraw.Draw(img)
	d.rectangle([0, 0, size - 1, size - 1], outline=(220, 60, 60, 255))
	inset = max(1, size // 8)
	d.rectangle([inset, inset, size - 1 - inset, size - 1 - inset], outline=(255, 210, 122, 255))
	if use_pd or size <= 16:
		draw_pd_glyph(d, size // 2, size // 2, max(3, size // 3))
	else:
		draw_campfire(d, size // 2, size // 2 + 1, max(4, size // 3))
	return img


def make_ico(path, master):
	import io
	import struct

	sizes = [16, 24, 32, 48, 64, 128, 256]
	images = []
	for s in sizes:
		if s <= 32:
			images.append(favicon(s, use_pd=(s <= 24)))
		else:
			images.append(master.resize((s, s), Image.NEAREST))
	# Manual PNG-in-ICO so every size is embedded (Pillow's append_images path is flaky).
	entries = []
	blobs = []
	offset = 6 + 16 * len(images)
	for im in images:
		buf = io.BytesIO()
		im.convert("RGBA").save(buf, format="PNG")
		data = buf.getvalue()
		w, h = im.size
		entries.append((0 if w >= 256 else w, 0 if h >= 256 else h, len(data), offset))
		blobs.append(data)
		offset += len(data)
	out = bytearray()
	out += struct.pack("<HHH", 0, 1, len(images))
	for w, h, size, off in entries:
		out += struct.pack("<BBBBHHII", w, h, 0, 0, 1, 32, size, off)
	for blob in blobs:
		out += blob
	path.write_bytes(out)


def write_readme():
	(ROOT / "README.md").write_text(
		"""# Idle PD — app icon templates

Edit these placeholders, then copy finals into Godot export slots.

Regenerate guides (overwrites PNGs): `python tools/gen_branding_icons.py`

## Color legend

| Color | Meaning |
|-------|---------|
| Red | Outside / mask risk — clipped on Android shapes & tiny sizes |
| Gold | Safe zone — keep the mark inside this |
| Blue (`idle_pd_guide_512`) | Suggested subject box |
| Orange | Placeholder art (campfire / PD glyph) — replace with real mark |
| Grey (mono) | Safe-circle guide on white silhouette |

## Files

| File | Size | Role |
|------|------|------|
| `idle_pd_master_32.png` | 32×32 | Pixel source of truth — edit this first |
| `idle_pd_512.png` | 512×512 | NN upscale of master → replace `res://icon.png` when done |
| `idle_pd_guide_512.png` | 512×512 | Checker + safe-circle overlay (reference only) |
| `idle_pd_fg_432.png` | 432×432 | Android adaptive **foreground** (transparent + guides) |
| `idle_pd_bg_432.png` | 432×432 | Android adaptive **background** (opaque stone) |
| `idle_pd_mono_432.png` | 432×432 | Android **monochrome** / themed icon |
| `idle_pd.ico` | multi | Windows icon (16–256) |
| `favicon_16.png` | 16×16 | Browser tab / bookmark |
| `favicon_32.png` | 32×32 | Retina tab / bookmark |

## Edit order

1. Redraw `idle_pd_master_32.png` (keep art inside the gold square).
2. Nearest-neighbor scale ×16 → `idle_pd_512.png`.
3. Place the same mark inside the gold circle on `idle_pd_fg_432.png`; delete the red guide ring when final.
4. Fill `idle_pd_bg_432.png` with a flat/simple texture (no important detail near edges).
5. Trace a solid white silhouette for `idle_pd_mono_432.png`.
6. Hand-tune `favicon_16.png` — shrinking 32px is usually muddy.

## Godot wiring (when art is final)

- Project → Application → Icon → `idle_pd_512.png` (or overwrite `res://icon.png`)
- Android export → Adaptive icon foreground / background / monochrome
- Windows export → `idle_pd.ico`
- Web already uses `html/export_icon=true` from the project icon

Always export with **nearest-neighbor** (no bilinear).
""",
		encoding="utf-8",
	)


def main():
	ROOT.mkdir(parents=True, exist_ok=True)
	m32 = master_32()
	m32.save(ROOT / "idle_pd_master_32.png")
	master_512_from_32(m32).save(ROOT / "idle_pd_512.png")
	guide_512().save(ROOT / "idle_pd_guide_512.png")
	android_template(432, with_subject=True).save(ROOT / "idle_pd_fg_432.png")
	android_template(432, bg_only=True).save(ROOT / "idle_pd_bg_432.png")
	android_template(432, with_subject=True, mono=True).save(ROOT / "idle_pd_mono_432.png")
	favicon(16, use_pd=True).save(ROOT / "favicon_16.png")
	favicon(32, use_pd=False).save(ROOT / "favicon_32.png")
	make_ico(ROOT / "idle_pd.ico", m32)
	write_readme()
	for p in sorted(ROOT.iterdir()):
		print(p.name, p.stat().st_size if p.is_file() else "")


if __name__ == "__main__":
	main()
