"""Extract SPD sprite animations (idle/run/attack/die, fps, frames) from SPD's *Sprite.java into data/anims.json."""
import re, json, os, glob
SRC = "/workspace/spd/shattered-pixel-dungeon/core/src/main/java/com/shatteredpixel/shatteredpixeldungeon/sprites"
names = [os.path.basename(p)[:-4] for p in glob.glob("assets/sprites/*.png") if not p.endswith("items.png")]
special = {"dm100": "DM100Sprite", "dm300": "DM300Sprite", "king": "KingSprite", "warrior": "HeroSprite", "mage": "HeroSprite", "rogue": "HeroSprite", "huntress": "HeroSprite"}
out = {}
for n in sorted(names):
    cls = special.get(n, n[0].upper() + n[1:] + "Sprite")
    p = os.path.join(SRC, cls + ".java")
    if not os.path.exists(p): print("missing", n, cls); continue
    s = open(p).read()
    a = {}
    for k in ["idle", "run", "attack", "die", "zap"]:
        m = re.search(k + r"\s*=\s*new\s+(?:MovieClip\.)?Animation\(\s*([^,]+?)\s*,\s*(true|false)\s*\)\s*;\s*" + k + r"\.frames\(\s*\w+\s*,([^)]*)\)", s)
        if not m: continue
        nums = re.findall(r"\d+", m.group(1)); fps = int(nums[-1]) if nums else 20
        fr = []
        for t in m.group(3).split(","):
            t = re.sub(r"\b[a-zA-Z_]\w*\b", "0", t.strip())
            try: fr.append(int(eval(t)))
            except Exception: pass
        a[k] = {"fps": fps, "loop": m.group(2) == "true", "frames": fr}
    if n in ("warrior", "mage", "rogue", "huntress"):
        a["run"] = {"fps": 20, "loop": True, "frames": [2, 3, 4, 5, 6, 7]}
    out[n] = a
json.dump(out, open("data/anims.json", "w"), indent=1)
print(len(out), "sprites;", [k for k, v in out.items() if len(v) < 4])
