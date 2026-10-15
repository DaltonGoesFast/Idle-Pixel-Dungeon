#!/usr/bin/env python3
"""Regenerates the data tables in docs/BALANCE.md and docs/CONTENT.md from data/*.json.
Run after changing data:  python3 tools/gen_docs.py
Hand-written text lives outside the <!-- GENERATED --> markers and is preserved."""
import json, os, re
ROOT = os.path.join(os.path.dirname(__file__), "..")
D = lambda n: json.load(open(os.path.join(ROOT, "data", n + ".json")))
mobs, items, heroes, biomes, events, recipes, fac, rooms = (D(n) for n in
    ["mobs", "items", "heroes", "biomes", "events", "recipes", "facilities", "rooms"])

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
        [[i["name"], i.get("unknown_name", "-"), ", ".join(f"{k}={v}" for k, v in i.items() if k in ("dmg_bonus", "barrier_bonus", "bolt_dmg", "charges", "recharge", "burns_grass"))]
         for k, i in items.items() if not k.startswith("_") and i["type"] in ("ring", "wand")])
    s += "\n### Encounter sets (Sewers)\n\n"
    s += table(["From floor", "Mobs"], [[e["min_floor"], ", ".join(e["mobs"])] for e in biomes["sewers"]["encounter_sets"]])
    s += "\n### Facilities\n\n"
    s += table(["Facility", "Upgrade cost (x current level)", "Max"], [[f["name"], ", ".join(f"{v} {k}" for k, v in f["upgrade_cost"].items()), f["max"]] for f in fac.values() if isinstance(f, dict)])
    return s

def content():
    s = "### Recipes\n\n"
    rows = []
    for facn, lst in recipes.items():
        if facn.startswith("_"): continue
        for r in lst: rows.append([facn, r["name"], ", ".join(f"{v} {k}" for k, v in r["cost"].items()), r.get("out", r.get("out_mat")), r["min_level"]])
    s += table(["Facility", "Recipe", "Cost", "Output", "Min level"], rows)
    s += "\n### Door Choices\n\n"
    s += table(["Id", "Door A", "Door B"], [[d["id"], d["a"]["text"] + f" ({d['a']['kind']})", d["b"]["text"] + f" ({d['b']['kind']})"] for d in events["doors"]])
    s += "\n### Special rooms (UI cards)\n\n"
    s += table(["Id", "Title", "Options"], [[x["id"], x["title"], " / ".join(o["text"] for o in x["options"])] for x in events["specials"]])
    s += f"\n### Arenas\n\n{len(rooms['rooms'])} handcrafted 8x8 rooms + {len(rooms['boss_rooms'])} boss room (data/rooms.json). Legend: {rooms['_legend']}\n"
    for i, r in enumerate(rooms["rooms"] + rooms["boss_rooms"]):
        s += f"\nRoom {i}:\n```\n" + "\n".join(r) + "\n```\n"
    return s

def write(path, gen):
    p = os.path.join(ROOT, "docs", path)
    txt = open(p).read() if os.path.exists(p) else "<!-- GENERATED -->\n<!-- /GENERATED -->\n"
    txt = re.sub(r"<!-- GENERATED -->.*<!-- /GENERATED -->", lambda m: "<!-- GENERATED -->\n" + gen + "<!-- /GENERATED -->", txt, flags=re.S)
    open(p, "w").write(txt)

write("BALANCE.md", balance()); write("CONTENT.md", content())
print("docs regenerated")
