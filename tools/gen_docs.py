#!/usr/bin/env python3
"""Regenerates the data tables in docs/BALANCE.md and docs/CONTENT.md from data/*.json.
Run after changing data:  python3 tools/gen_docs.py
Hand-written text lives outside the <!-- GENERATED --> markers and is preserved."""
import json, os, re
ROOT = os.path.join(os.path.dirname(__file__), "..")
D = lambda n: json.load(open(os.path.join(ROOT, "data", n + ".json")))
mobs, items, heroes, biomes, events, recipes, fac, rooms = (D(n) for n in
    ["mobs", "items", "heroes", "biomes", "events", "recipes", "facilities", "rooms"])
traps = D("traps")

def table(head, rows):
    out = "| " + " | ".join(head) + " |\n|" + "---|" * len(head) + "\n"
    for r in rows: out += "| " + " | ".join(str(c) for c in r) + " |\n"
    return out

def balance():
    s = "### Heroes (Lv1, starting gear)\n\n"
    s += table(["Hero", "Base HT", "+HT/lvl", "Base Barrier", "Heirloom Barrier", "Start weapon", "Start armor"],
        [[h["name"], h["base_ht"], h["ht_per_level"], h["base_barrier"], h["heirloom_barrier"], h["start_weapon"], h["start_armor"]] for h in heroes.values()])
    s += "\n### Monsters\n\n"
    s += table(["Mob", "HT", "Dmg", "DR", "Delay (ticks)", "EXP", "Gold", "SPD source", "Tuning"],
        [[m["name"], m["ht"], m["dmg"], m["dr"], m["delay"], m["exp"], m["loot"], m.get("spd", ""), m.get("tuned", "-")]
         for k, m in mobs.items() if not k.startswith("_")])
    s += "\n### Weapons & armor\n\n"
    s += table(["Item", "Type", "Tier", "Dmg / DR", "Barrier", "Delay", "Str"],
        [[i["name"], i["type"], i.get("tier", "-"), i.get("dmg", i.get("dr", "-")), i.get("barrier", "-"), i.get("delay", "-"), i.get("str", "-")]
         for k, i in items.items() if not k.startswith("_") and i["type"] in ("weapon", "armor")])
    s += "\n### Rings & wands\n\n"
    s += table(["Item", "Unidentified as", "Effect"],
        [[i["name"], i.get("unknown_name", "-"), ", ".join(f"{k}={v}" for k, v in i.items() if k in ("dmg_bonus", "barrier_bonus", "bolt_dmg", "charges", "recharge", "burns_grass", "chains_water"))]
         for k, i in items.items() if not k.startswith("_") and i["type"] in ("ring", "wand")])
    for bid, b in biomes.items():
        s += f"\n### {b['name']} (floors {b['floors'][0]}-{b['floors'][1]}, boss {b['boss']} on {b['boss_floor']}, {b['str_gate']} Str)\n\n"
        s += f"Traps: {', '.join(b.get('traps', []))}. Strength potions at {b['strength_potions_at']}. Secret cache: {b.get('secret_cache', {})}\n\n"
        s += table(["From floor", "Mobs"], [[e["min_floor"], ", ".join(e["mobs"])] for e in b["encounter_sets"]])
    s += "\n### Patrol yields per hour (x efficiency x gear bonus; gold has no gear bonus)\n\n"
    mats = ["gold", "iron_ore", "dark_gold", "arcane_resin", "dew", "seeds"]
    s += table(["Biome", "Str gate"] + mats + ["Curio every"], [[b["name"], b["str_gate"]] + [b["patrol_yield_per_hour"].get(m, "-") for m in mats] + [f"{b['patrol_curio_every_hours']}h"] for b in biomes.values()])
    s += "\n### Traps\n\n"
    s += table(["Trap", "Effect", "SPD source"], [[t["name"], t["desc"], t.get("spd", "")] for k, t in traps.items() if not k.startswith("_")])
    s += "\n### Facilities\n\n"
    s += table(["Facility", "Upgrade cost (x current level)", "Scrolls of Upgrade per cap raise", "Max"], [[f["name"], ", ".join(f"{v} {k}" for k, v in f["upgrade_cost"].items()), " / ".join(str(x) for x in f.get("cap_scrolls", [])), f["max"]] for f in fac.values() if isinstance(f, dict)])
    return s

MATW = {"dew": "dew", "potion_healing": "healing potion"}
def matw(m): return MATW.get(m, items["_materials"].get(m, {}).get("name", m).lower())
def num(x): return str(int(x)) if float(x) == int(x) else f"{x:.1f}"
def perk_text(k, v):
    """Mirror of GameState.patrol_perk_text for one perk spec at +0 with its per-level step."""
    if isinstance(v, bool): return {"curio_known": "curios arrive identified"}.get(k, k)
    if isinstance(v, str): return "curios: any ring" if k == "curio_pool" else k
    b, per = v[0], v[1]
    step = f" ({'+' if per >= 0 else ''}{num(per)}/lvl{', min ' + num(v[2]) if len(v) > 2 else ''})" if per else ""
    if k.endswith("_per_hour"): return f"+{num(b)} {matw(k[:-9])}/h{step}"
    if k.endswith("_every"): return f"+1 {matw(k[:-6])} per {num(b)}h{step}"
    t = {"all_pct": "+{}% materials (not gold)", "time_pct": "+{}% patrol time", "curio_pct": "+{}% curios", "fee_cut_pct": "-{}% fee (max 50%)",
         "power": "+{} patrol power", "max_hours": "+{}h max", "curio_plus_pct": "{}% of curios come +1"}.get(k)
    if t: return t.format(num(b)) + step
    if k.endswith("_pct"): return f"+{num(b)}% {matw(k[:-4])}{step}"
    return k

def content():
    s = "### Patrol perks (DECISIONS #188)\n\nWorn ring, artifact and the Mage's staff wand, at +0; the step is per item level. Perks are locked in when the patrol starts.\n\n"
    s += table(["Item", "Type", "On patrol"], [[i["name"], i["type"], ", ".join(perk_text(k, v) for k, v in i["patrol"].items())]
         for k, i in items.items() if not k.startswith("_") and "patrol" in i])
    s += "\n### Recipes\n\n"
    rows = []
    for facn, lst in recipes.items():
        if facn.startswith("_"): continue
        for r in lst: rows.append([facn, r["name"], ", ".join(f"{v} {k}" for k, v in r["cost"].items()), r.get("out", r.get("out_mat")), r["min_level"]])
    s += table(["Facility", "Recipe", "Cost", "Output", "Min level"], rows)
    s += "\n### Door Choices\n\n"
    s += table(["Id", "Biomes", "Door A", "Door B"], [[d["id"], ", ".join(d.get("biomes", [])), d["a"]["text"] + f" ({d['a']['kind']})", d["b"]["text"] + f" ({d['b']['kind']})"] for d in events["doors"]])
    s += "\n### Special rooms (UI cards)\n\n"
    s += table(["Id", "Biomes", "Title", "Options"], [[x["id"], ", ".join(x.get("biomes", [])), x["title"], " / ".join(o["text"] for o in x["options"])] for x in events["specials"]])
    br = rooms.get("biome_rooms", {})
    s += f"\n### Arenas\n\n{len(rooms['rooms'])} shared 8x8 rooms, " + ", ".join(f"{len(v)} {k}-only" for k, v in br.items()) + f", {len(rooms['boss_rooms'])} boss rooms (data/rooms.json). Legend: {rooms['_legend']}\n"
    allr = [("Shared", i, r) for i, r in enumerate(rooms["rooms"])] + [(k, i, r) for k, v in br.items() for i, r in enumerate(v)] + [("Boss", i, r) for i, r in enumerate(rooms["boss_rooms"])]
    for tag, i, r in allr:
        s += f"\n{tag} room {i}:\n```\n" + "\n".join(r) + "\n```\n"
    return s

def write(path, gen):
    p = os.path.join(ROOT, "docs", path)
    txt = open(p).read() if os.path.exists(p) else "<!-- GENERATED -->\n<!-- /GENERATED -->\n"
    txt = re.sub(r"<!-- GENERATED -->.*<!-- /GENERATED -->", lambda m: "<!-- GENERATED -->\n" + gen + "<!-- /GENERATED -->", txt, flags=re.S)
    open(p, "w").write(txt)

write("BALANCE.md", balance()); write("CONTENT.md", content())
print("docs regenerated")
