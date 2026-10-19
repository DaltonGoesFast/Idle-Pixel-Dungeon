## Captures screenshots of each screen at Fold cover + inner sizes into /workspace/builds/shots (needs a display: xvfb-run).
## Run: xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/screenshots.tscn
extends Node

var main
var f := 0
var out := "/workspace/builds/shots"
var SIZES := {"cover": Vector2i(484, 1188), "inner": Vector2i(928, 1080)}   # SHOT_PC=1 adds a 1280x800 PC window
## The window at SIZES is a 0.5x stretch of the 968x2376 viewport, which drops 1-px pixel-font columns
## ("i", ":", ".") that are fine on device. Render at 2x and downsample (SHOT_NATIVE=1 keeps the 2x image) (DECISIONS #112).
const RENDER_SCALE := 2
var plan := []
var mage_was_unlocked := false   # expedition_no_wand unlocks the Mage and takes her wand out; camp_heroes puts both back
var mage_wand_uid := 0

func _ready() -> void:
	if OS.has_environment("SHOT_DIR"): out = OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(out)
	if OS.has_environment("SHOT_PC"): SIZES["pc"] = Vector2i(1280, 800)
	SaveSystem.autosave = false; SaveSystem.path = "user://shots.json"
	GameState.new_game()
	GameState.settings.tutorial = false
	GameState.settings.lighting = not OS.has_environment("NOLIGHT")
	GameState.add_mat("iron_ore", 20); GameState.add_mat("gold", 200)
	main = load("res://scenes/main.tscn").instantiate(); add_child(main)
	for sz in SIZES:
		plan.append([sz, "camp", func(): main.show_camp(); main.screen.close_page()])
		plan.append([sz, "icon_audit", func():
			# every icon context with centre guides: item slots, paperdoll slots, res chips, icon buttons, hero portraits
			main.show_camp(); main.screen.close_page()
			var layer := PanelContainer.new(); layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); main.screen.add_child(layer)
			var sc := ScrollContainer.new(); layer.add_child(sc); var v := UIKit.vbox(sc); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v.add_child(UIKit.header("Icon audit"))
			var g: GridContainer = main.screen.slot_grid(v)
			for id in ["GOLD", "DEWDROP", "TORCH", "IRON_KEY", "RATION", "ORE", "potion_healing", "ring_wealth", "chalice_blood", "shortsword", "mace", "WEAPON_HOLDER", "ARMOR_HOLDER", "RING_HOLDER", "ARTIFACT_HOLDER", "CHEST"]:
				var b: Button = main.screen.item_slot(id, "", "", func(): pass)
				var guide := ColorRect.new(); guide.color = Color(1, 0, 1, 0.5); guide.set_anchors_preset(Control.PRESET_CENTER); guide.size = Vector2(1, 1000); guide.position = Vector2(UIKit.font_size * 1.5, -400); guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
				b.add_child(guide); var gh := ColorRect.new(); gh.color = guide.color; gh.size = Vector2(1000, 1); gh.position = Vector2(-400, UIKit.font_size * 1.5); gh.mouse_filter = Control.MOUSE_FILTER_IGNORE; b.add_child(gh)
				b.clip_contents = true; g.add_child(b)
			var chips := HFlowContainer.new(); v.add_child(chips)
			for k in ["gold", "iron_ore", "seeds", "torch", "ration", "potion_healing"]: chips.add_child(UIKit.res_chip(k, "88", 0.9))
			var bf := HFlowContainer.new(); v.add_child(bf)
			for n in ["enter", "backpack_lrg", "prefs", "journal", "talent", "alchemy"]:
				var tb := UIKit.as_toolbar(UIKit.button("", func(): pass), n); tb.custom_minimum_size = Vector2.ONE * UIKit.btn_height(); tb.size_flags_horizontal = 0; tb.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER; bf.add_child(tb)
			for n in ["Stash", "Forge", "Journal"]:
				var lb := UIKit.button(n, func(): pass); UIKit.with_icon(lb, main.screen.PAGE_ICONS[n]); lb.size_flags_horizontal = 0; lb.custom_minimum_size.x = UIKit.font_size * 7; bf.add_child(lb)
			var hr := HFlowContainer.new(); v.add_child(hr)
			for c in GameState.heroes: hr.add_child(main.screen._hero_slot(c))
			Paperdoll.build(v, "warrior", not main.screen.portrait, "camp", func(): pass)])
		# DECISIONS #197: the one-time gameplay data notice (tip card look, OK + Privacy)
		plan.append([sz, "data_notice", func(): main.show_camp(); main.screen.close_page(); main.show_data_notice()])
		plan.append([sz, "camp_expedition", func():
			main.tips.queue = main.tips.queue.filter(func(q): return not q.get("notice", false)); main.tips._render()
			main.show_camp(); main.screen.open_page("Delve")])
		# DECISIONS #193: the Mage's wand taken out of the Staff - the Expedition window and Stats panel say "no Bolt"
		plan.append([sz, "expedition_no_wand", func():
			mage_was_unlocked = GameState.heroes.mage.unlocked
			GameState.heroes.mage.unlocked = true
			mage_wand_uid = 0
			if GameState.unequip("mage", "staff"): mage_wand_uid = int(GameState.gear[-1].uid)
			main.show_camp(); main.screen.chosen_hero = "mage"; main.screen.open_page("Delve")])
		plan.append([sz, "heroes_no_wand", func(): main.show_camp(); main.screen.chosen_hero = "mage"; main.screen.open_page("Heroes")])
		plan.append([sz, "camp_heroes", func():
			if mage_wand_uid: GameState.imbue_wand(mage_wand_uid); mage_wand_uid = 0   # the usual Mage for the later shots
			GameState.heroes.mage.unlocked = mage_was_unlocked
			main.show_camp(); main.screen.chosen_hero = "warrior"; main.screen.open_page("Heroes")])
		plan.append([sz, "camp_paperdoll", func():
			GameState.add_gear("shortsword"); GameState.add_gear("mace"); GameState.add_gear("ring_wealth"); GameState.add_gear("chalice_blood")
			Paperdoll.sel_slot = "weapon"; main.show_camp(); main.screen.open_page("Heroes")])
		plan.append([sz, "camp_talents", func():
			Paperdoll.sel_slot = ""; GameState.heroes.warrior.level = 5; HeroPanels.sel_talent = "iron_will"
			main.show_camp(); main.screen.show_talents = true; main.screen.open_page("Heroes")
			(func(): main.screen.win_layer.get_meta("sc").scroll_vertical = 100000).call_deferred()])
		plan.append([sz, "camp_compare", func():
			HeroPanels.sel_talent = ""; GameState.heroes.warrior.level = 1
			main.show_camp(); main.screen.open_page("Stash")
			main.screen.compare(GameState.gear.filter(func(g): return g.id == "mace")[0])])
		# gear ownership (DECISIONS #189): picker with another hero's ring, the patrol lock, the stash item window
		plan.append([sz, "gear_take", func():
			main.screen._close_info()
			for c in GameState.heroes: GameState.heroes[c].unlocked = true
			if GameState.heroes.mage.ring == 0: GameState.equip("mage", GameState.add_gear("ring_might", true))
			GameState.equip("warrior", GameState.add_gear("ring_tenacity", true))
			main.show_camp(); main.screen.chosen_hero = "warrior"; Paperdoll.sel_slot = "ring"; main.screen.open_page("Heroes")])
		plan.append([sz, "gear_locked", func():
			for c in GameState.heroes: GameState.heroes[c].unlocked = true
			GameState.heroes.mage.patrol = {"biome": "sewers", "start": GameState.now()}
			main.show_camp(); main.screen.chosen_hero = "mage"; Paperdoll.sel_slot = "ring"; main.screen.open_page("Heroes")])
		plan.append([sz, "gear_stash_item", func():
			main.show_camp(); main.screen.chosen_hero = "warrior"; main.screen.section["Stash"] = "gear"; main.screen.open_page("Stash")
			var g: Dictionary = GameState.gear_by_uid(int(GameState.heroes.mage.ring))
			main.screen.info(g.id, GameState.gear_name(g), main.screen.gear_lines(g), main.screen.gear_actions(g))])
		plan.append([sz, "gear_stash", func():
			main.screen._close_info(); GameState.heroes.mage.patrol = {}; Paperdoll.sel_slot = ""
			main.show_camp(); main.screen.section["Stash"] = "gear"; main.screen.open_page("Stash")])
		plan.append([sz, "camp_toast", func():
			main.show_camp(); main.screen.open_page("Guild"); GameState.say("Bought a Ration.")])
		plan.append([sz, "camp_stash", func():
			# every ring kind, known + unknown + cracked, a potion and a scroll: the icons must all show
			for rid in ["ring_might", "ring_tenacity", "ring_evasion", "ring_wealth", "ring_energy"]:
				GameState.add_gear(rid, true); GameState.add_gear(rid, false)
			var cr: int = GameState.add_gear("ring_might", true); GameState.gear_by_uid(cr).cracked = true
			GameState.add_mat("potion_toxic", 1); GameState.add_mat("scroll_upgrade", 1)
			main.show_camp(); main.screen.section["Stash"] = "gear"; main.screen.open_page("Stash")])
		plan.append([sz, "forge", func():
			GameState.add_mat("iron_ore", 40); GameState.add_mat("dark_gold", 5); GameState.add_mat("gold", 100)
			GameState.facilities.blacksmith.level = 3
			var a: int = GameState.add_gear("shortsword", true, 0); var b: int = GameState.add_gear("cloth_armor", true, 1)
			GameState.gear_by_uid(a).cracked = true; GameState.gear_by_uid(b).cracked = true
			var rg: int = GameState.add_gear("ring_wealth", true); GameState.gear_by_uid(rg).cracked = true
			main.show_camp(); main.screen.section["Forge"] = "upgrade"; main.screen.open_page("Forge")])
		plan.append([sz, "forge_craft", func():
			main.show_camp(); main.screen.section["Forge"] = "craft"; main.screen.open_page("Forge")])
		plan.append([sz, "camp_forge_info", func():
			main.show_camp(); main.screen.open_page("Forge")
			var uid: int = GameState.add_gear("mace", true, 0)
			main.screen._gear_forge_info(GameState.gear_by_uid(uid), ["+0  ->  +N"], "")])
		plan.append([sz, "camp_forge_buy", func():
			main.show_camp(); main.screen.open_page("Forge")
			var r: Dictionary = DB.recipes.blacksmith[0]
			main.screen._recipe_info("blacksmith", r, r.out, [main.screen.cost_row(r.cost)], "")])
		plan.append([sz, "camp_alchemy", func():
			GameState.add_mat("potion_toxic", 1); GameState.add_mat("seeds", 3)
			main.show_camp(); main.screen.alch_sel = "transmute_toxic"; main.screen.open_page("Alchemy")])
		plan.append([sz, "camp_enchanter", func():
			# earlier steps make these types known, which identifies a queued one at once (DECISIONS #203), so forget them
			for t in ["ring_wealth", "ring_evasion"]: GameState.seen.erase("item:" + t)
			var u: int = GameState.add_gear("ring_wealth", false); GameState.add_gear("ring_evasion", false); GameState.enqueue_identify(u)
			main.show_camp(); main.screen.section["Enchanter"] = "identify"; main.screen.open_page("Enchanter")])
		# DECISIONS #203: the user's queue (7 Garnet + 2 Ruby at a Lv1 Desk), right after Queue all
		plan.append([sz, "enchanter_queue", func():
			GameState.id_queue = []
			for g in GameState.gear.filter(func(x): return not x.known): GameState.gear.erase(g)
			for t in ["ring_might", "ring_tenacity"]: GameState.seen.erase("item:" + t)   # known by now; the shot is the first Garnet
			for i in 7: GameState.add_gear("ring_might", false)
			for i in 2: GameState.add_gear("ring_tenacity", false)
			GameState.mats.gold = 1369; GameState.enqueue_identify_all()
			main.show_camp(); main.screen.section["Enchanter"] = "identify"; main.screen.open_page("Enchanter")])
		plan.append([sz, "camp_guild", func():
			GameState.add_mat("gold", 200); GameState.facilities.guild.level = 2
			main.show_camp(); main.screen.open_page("Guild")])
		plan.append([sz, "camp_guild_patrols", func():
			# patrol perks (DECISIONS #188): idle geared Warrior with Wealth +2, Mage out with her staff wand and the Chalice
			GameState.add_mat("gold", 2000); GameState.facilities.guild.level = 3
			for c in ["warrior", "mage"]:
				GameState.heroes[c].unlocked = true
				for b in ["sewers", "prison"]: if not (b in GameState.heroes[c].cleared): GameState.heroes[c].cleared.append(b)
			GameState.gear_by_uid(GameState.heroes.warrior.weapon).lvl = 3; GameState.gear_by_uid(GameState.heroes.warrior.armor).lvl = 2
			var wr: int = GameState.add_gear("ring_wealth", true, 2); GameState.equip("warrior", wr)
			var th: int = GameState.add_gear("thieves_armband", true, 1); GameState.equip("warrior", th)
			if GameState.heroes.mage.patrol.is_empty():
				GameState.heroes.mage.wand_lvl = 2
				var ch: int = GameState.add_gear("chalice_blood", true, 1); GameState.equip("mage", ch)
				GameState.start_patrol("mage", "prison"); GameState.heroes.mage.patrol.start = GameState.now() - 5.0 * 3600.0
			main.show_camp(); main.screen.section["Guild"] = "patrols"; main.screen.open_page("Guild")])
		plan.append([sz, "camp_guild_buy", func():
			main.show_camp(); main.screen.open_page("Guild")
			var r: Dictionary = GameState.recipe("guild", "buy_ration")
			main.screen._recipe_info("guild", r, r.out_mat, [main.screen.cost_row(r.cost)], "")])
		plan.append([sz, "journal", func():
			# DECISIONS #195: two reached milestones wait for Claim; the rest show "have / goal" by category
			GameState.milestones_claimed.clear(); GameState.milestones_reached.clear()
			GameState.stats.extractions = 1; GameState.stats.kills = 37; GameState.stats["kill_rat"] = 12; GameState.touch()
			main.show_camp(); main.screen.journal_view = "milestones"; main.screen.open_page("Journal")])
		plan.append([sz, "camp_claim_dot", func(): main.show_camp(); main.screen.close_page()])
		plan.append([sz, "journal_claimed", func():
			GameState.claim_all_milestones()
			main.show_camp(); main.screen.journal_view = "milestones"; main.screen.open_page("Journal")])
		plan.append([sz, "journal_progress", func(): main.show_camp(); main.screen.journal_view = "progress"; main.screen.open_page("Journal")])
		plan.append([sz, "journal_bottom", func():
			# the end of the list: Feats with their claimed line, scrolled all the way down
			GameState.stats.feat_close_call = 1; GameState.touch(); GameState.claim_all_milestones()
			main.show_camp(); main.screen.journal_view = "milestones"; main.screen.open_page("Journal")
			var sc: ScrollContainer = main.screen.win_layer.get_meta("sc")
			(func(): sc.scroll_vertical = 1000000).call_deferred()])
		plan.append([sz, "codex", func():
			for m in ["rat", "snake", "gnoll", "crab", "goo"]: GameState.discover("mob:" + m)
			GameState.discover("trap:worn_dart")
			main.show_camp(); main.screen.journal_view = "codex"; main.screen.open_page("Journal")
			main.screen.rebuild()])
		plan.append([sz, "tip", func():
			main.show_camp(); main.tips.push("welcome")])
		plan.append([sz, "tip_closed", func(): main.tips.skip_all(); GameState.settings.tutorial = false])
		plan.append([sz, "settings", func(): main.show_camp(); main.screen.open_page("Settings")])
		plan.append([sz, "delve", func():
			_fresh_warrior_run()
			main.show_delve(); main.delve.running = false
			for i in 30: Delve.advance(GameState, 1.0)
			main.delve.pending = {"kind": "door", "door": DB.doors[0]}; main.delve._show_card()])
		plan.append([sz, "delve_walk", func():
			_fresh_warrior_run(); main.show_delve()
			GameState.heroes.warrior.armor = GameState.add_gear("scale_armor")   # armor tier row must show
			main.delve.pending = {}; main.delve.running = true; main.delve._show_card()
			main.delve.scene.scroll = main.delve.scene.target - 0.6; main.delve.scene.pops.append({"idx": DB.icon_index("gold"), "age": 0.2, "n": 3}); main.delve.scene.glow = 0.8])
		plan.append([sz, "delve_enemy", func():
			_clear_pops()
			main.delve.running = false
			main.delve.pending = Delve.combat_event(GameState.run, Delve.rng_for(GameState.run, 4), ["gnoll", "rat"]); main.delve._show_card()])
		plan.append([sz, "delve_death", func():   # the fight above was won: SPD die frames and fade (DECISIONS #182)
			main.delve.scene._last_combat = {"ids": ["gnoll", "rat"], "boss": false, "col": main.delve.scene._last_combat.get("col", 0)}
			main.delve.pending = {}; main.delve._show_card(); main.delve.scene.foes_fell()])
		plan.append([sz, "delve_special", func():
			_clear_pops()
			main.delve.running = false
			main.delve.pending = {"kind": "special", "special": DB.specials[0]}; main.delve._show_card()])
		if OS.has_environment("ROOM_SHOTS"):   # every special room's delve scene (DECISIONS #180)
			for sp in DB.specials:
				plan.append([sz, "room_" + String(sp.id), func():
					_fresh_warrior_run(); main.show_delve(); _clear_pops(); main.delve.running = false; main.delve.pending = {"kind": "special", "special": sp}; main.delve._show_card()])
		plan.append([sz, "delve_auto", func():
			_clear_pops()
			main.delve.pending = {}; GameState.settings.full_auto = true
			GameState.log_line("Auto: fight Marsupial Rat", "auto"); GameState.log_line("Victory: 2 kills, took 3 damage, +5 gold, +2 xp.", "positive")
			GameState.log_line("Warning: your torch is burning low.", "warning"); GameState.log_line("You descend to floor 2.", "highlight")
			main.delve._refresh_controls(); main.delve._show_card(); GameState.settings.full_auto = false])
		for b in [["prison", 7], ["caves", 12], ["city", 17], ["halls", 22]]:   # biome corridor art (DECISIONS #181); after the Sewers delve shots, and delve_menu resets to Sewers
			plan.append([sz, "delve_" + b[0], _biome_walk.bind(b[0], b[1])])
		plan.append([sz, "delve_menu", func():
			_fresh_warrior_run(); main.show_delve(); _clear_pops()
			GameState.run.supplies["scroll_passage"] = 1
			main.delve.pending = {}; main.delve._open_panel("menu")])
		# DECISIONS #202: Scroll of Passage Read/Cancel confirm (phone portrait is the cover size)
		plan.append([sz, "passage_confirm", func():
			_fresh_warrior_run(); main.show_delve(); _clear_pops()
			GameState.run.supplies["scroll_passage"] = 1
			main.delve.pending = {}; main.delve._confirm_passage()])
		# DECISIONS #214: a potion used from the scrolled Bag shows its result (and the milestone it reached) in a pop-up
		plan.append([sz, "use_popup", func():
			_fresh_warrior_run(); main.show_delve(); _clear_pops()
			GameState.ided.erase("potion_haste"); GameState.run.pack["potion_haste"] = 1
			var ms: Array = DB.milestones.filter(func(m): return m.stat == "items_identified" and not (m.id in GameState.milestones_reached))
			if not ms.is_empty(): GameState.stats["items_identified"] = int(ms[0].goal) - 1
			main.delve.pending = {}; main.delve._open_panel("backpack")
			var sc: ScrollContainer = main.delve.card_host.get_parent()
			sc.scroll_vertical = 100000
			HeroPanels.use_item("potion_haste", false, func(): main.delve._refresh(); main.delve._refresh_controls(); main.delve._show_card())
			(func(): sc.scroll_vertical = 100000).call_deferred()])
		plan.append([sz, "delve_low_hp", func():
			_fresh_warrior_run(); main.show_delve(); _clear_pops()
			main.delve.pending = {}; main.delve.running = false
			GameState.run.hp = 4; main.delve._refresh_controls(); main.delve._show_card()])
		plan.append([sz, "delve_campfire", func():
			_fresh_warrior_run(); main.show_delve(); _clear_pops()
			GameState.run.hp = 20; GameState.run.boss_dead = true; GameState.run.floor = 5
			GameState.run.pack["iron_ore"] = 3; Delve.reward(GameState, {"item": "mace"})
			main.delve.pending = {"kind": "campfire"}; main.delve._show_card()])
		plan.append([sz, "backpack", func():
			_fresh_warrior_run()
			if GameState.run.pack_gear.is_empty():
				Delve.reward(GameState, {"item": "mace"}); Delve.reward(GameState, {"item": "mail_armor"}); Delve.reward(GameState, {"item_unknown": "ring"})
				GameState.run.pack["potion_toxic"] = 1; GameState.run.pack["scroll_upgrade"] = 1
			main.show_delve(); main.delve._open_panel("backpack")])
		plan.append([sz, "talents", func():
			GameState.heroes.warrior.level = 9; GameState.heroes.warrior.talents = ["hearty_meal"]
			main.show_delve(); main.delve._open_panel("talents")])
		plan.append([sz, "guided", func():
			main.delve._close_panel(); GameState.heroes.warrior.level = 1; GameState.heroes.warrior.talents = []
			GameState.settings.tutorial = true; GameState.tutorial_done = ["first_fight", "welcome", "delve_bar"]
			main.start_combat(Delve.combat_event(GameState.run, Delve.rng_for(GameState.run, 3), ["rat"]), func(_r): pass)
			GameState.settings.tutorial = false])
		# v0.44.0 phone regression (fix8): Mage on Sewers 1, ambush by two rats, then a wand bolt in the fight
		plan.append([sz, "mage_ambush", func():
			GameState.end_run("abandon")
			for c in GameState.heroes: GameState.heroes[c].unlocked = true
			# camp_guild_patrols (#188) leaves the Mage out on patrol, and a hero on patrol can't start a run: without
			# this start_run failed, these four shots showed an empty delve and logged 24 SCRIPT ERRORs
			GameState.heroes.mage.patrol = {}
			if not GameState.start_run("mage", {}, "sewers", 1): push_error("mage_ambush: start_run failed: " + GameState.can_start_run("mage"))
			main.show_delve(); _clear_pops(); main.delve.running = false
			main.delve.pending = Delve.combat_event(GameState.run, Delve.rng_for(GameState.run, 4), ["rat", "rat"]); main.delve._show_card()])
		plan.append([sz, "mage_ambush_late", func(): pass])   # the same scene ~0.2 s later (foes arrived, lunging)
		plan.append([sz, "mage_bolt", func():
			main.start_combat(Delve.combat_event(GameState.run, Delve.rng_for(GameState.run, 4), ["rat", "rat"]), func(_r): pass)
			var cb = main.screen.combat
			for e in cb.enemies():
				if cb.can_bolt(e.pos): main.screen._act(func(): cb.hero_bolt(e.pos)); break])
		plan.append([sz, "mage_bolt_late", func(): pass])
		plan.append([sz, "defeat_long", func():   # v0.44.0 phone softlock: a 30+ line defeat list must keep OK on screen
			_fresh_warrior_run(); main.show_delve(); _clear_pops(); main.delve.running = false
			var lost := PackedStringArray()
			for i in 34: lost.append("Ring of Item %d cracks" % i)
			main.delve._open_summary("Defeat", PackedStringArray(), lost, Callable(), true, "Unused supplies return to the stash. Scrolls of Upgrade return on the next boss kill.")])
		plan.append([sz, "event_result", func():   # an event's result window: no dim behind it, like the event card (DECISIONS #191)
			main.delve._accept_summary()
			# like the real chest/special-room flow (_card_special: pending = {}; _show_card() before _show_trade), the
			# event card is closed first, so the shot shows the scene, not the fresh run's encounter card, behind it
			main.delve.pending = {}; main.delve._show_card()
			main.delve._open_summary("Open the chest", PackedStringArray(["+14 Gold", "Potion of Healing"]), PackedStringArray(["-1 Iron Key"]))])
		plan.append([sz, "combat", func():
			main.start_combat(Delve.combat_event(GameState.run, Delve.rng_for(GameState.run, 3), ["gnoll", "crab"]), func(_r): pass)
			for i in 3: main.screen._do_bot()])
		# DECISIONS #210: blue segmented Barrier on the status-pane HP bar and the over-sprite bar
		plan.append([sz, "barrier_full", func():
			if not GameState.run.is_empty(): GameState.end_run("abandon")
			GameState.start_run("warrior", {}, "sewers", 9); main.show_delve(); main.delve.running = false
			main.start_combat({"kind": "combat", "room": DB.rooms[0], "mobs": ["gnoll"]}, func(_r): pass)
			main.screen._refresh()])
		plan.append([sz, "barrier_hit", func():
			var cb = main.screen.combat
			var e = cb.enemies()[0]
			cb.hit_hero(int(e.dmg), e.name)
			main.screen._refresh()])
		plan.append([sz, "huntress", func():
			GameState.end_run("abandon")
			for c in GameState.heroes: GameState.heroes[c].unlocked = true
			GameState.start_run("huntress", {}, "sewers", 9); main.show_delve(); main.delve.running = false
			main.start_combat(Delve.combat_event(GameState.run, Delve.rng_for(GameState.run, 4), ["crab", "rat"]), func(_r): pass)
			for i in 2: main.screen._do_bot()])
		plan.append([sz, "combat_bag", func():
			for id in ["mace", "leather_armor", "ring_wealth"]: GameState.run.pack_gear.append({"uid": 9100 + GameState.run.pack_gear.size(), "id": id, "lvl": 0, "cracked": false, "known": false, "owned": false})
			main.screen.bag_open = true; main.screen._refresh()])
		plan.append([sz, "prison", func():
			GameState.run.biome = "prison"; GameState.run.floor = 7
			main.start_combat({"kind": "combat", "room": DB.biome_rooms.prison[0], "mobs": ["guard", "dm100", "skeleton"]}, func(_r): pass)
			main.screen._act(func(): main.screen.combat.hero_search())
			for i in 2: main.screen._do_bot()])
		plan.append([sz, "tengu", func():
			main.start_combat({"kind": "combat", "boss": true, "room": DB.boss_rooms[1], "mobs": ["tengu"]}, func(_r): pass)
			for i in 4: main.screen._do_bot()])
		plan.append([sz, "caves", func():
			GameState.run.biome = "caves"; GameState.run.floor = 12
			main.start_combat({"kind": "combat", "room": DB.biome_rooms.caves[0], "mobs": ["brute", "shaman", "bat"]}, func(_r): pass)
			for i in 3: main.screen._do_bot()])
		plan.append([sz, "dm300", func():
			main.start_combat({"kind": "combat", "boss": true, "room": DB.boss_rooms[2], "mobs": ["dm300"]}, func(_r): pass)
			for i in 4: main.screen._do_bot()])
		plan.append([sz, "city", func():
			GameState.run.biome = "city"; GameState.run.floor = 17
			main.start_combat({"kind": "combat", "room": DB.biome_rooms.city[1], "mobs": ["ghoul", "warlock", "monk"]}, func(_r): pass)
			for i in 3: main.screen._do_bot()])
		plan.append([sz, "dking", func():
			main.start_combat({"kind": "combat", "boss": true, "room": DB.boss_rooms[3], "mobs": ["dking"]}, func(_r): pass)
			for i in 5: main.screen._do_bot()])
		plan.append([sz, "halls", func():
			GameState.run.biome = "halls"; GameState.run.floor = 22
			main.start_combat({"kind": "combat", "room": DB.biome_rooms.halls[1], "mobs": ["succubus", "eye", "ripper"]}, func(_r): pass)
			main.screen.combat.hero.ht = 120; main.screen.combat.hero.hp = 120
			for i in 3: main.screen._do_bot()])
		plan.append([sz, "yog", func():
			GameState.run.biome = "halls"; GameState.run.floor = 25
			main.start_combat({"kind": "combat", "boss": true, "room": DB.boss_rooms[DB.biomes.halls.boss_room], "mobs": ["yog"]}, func(_r): pass)
			main.screen.combat.hero.ht = 120; main.screen.combat.hero.hp = 120
			for i in 6: main.screen._do_bot()])
		plan.append([sz, "terrain", func():
			# hero standing in a doorway, a rat in tall grass (with grass above it) and a trampled cell
			GameState.run.biome = "sewers"; GameState.run.floor = 1
			main.start_combat({"kind": "combat", "room": DB.biome_rooms.prison[0], "mobs": ["rat", "crab"]}, func(_r): pass)
			var cb = main.screen.combat; var T = cb.T
			for y in range(1, cb.SIZE - 1):
				for x in range(1, cb.SIZE - 1): cb.terrain[y][x] = T.FLOOR
			for x in cb.SIZE: cb.terrain[3][x] = T.WALL
			cb.terrain[3][2] = T.DOOR; cb.terrain[3][5] = T.DOOR
			for y in range(5, 8):
				for x in range(3, 7): cb.terrain[y][x] = T.GRASS
			cb.terrain[6][3] = T.FLOOR; cb.trampled[Vector2i(3, 6)] = true
			cb.hero.pos = Vector2i(2, 3)
			var es: Array = cb.enemies(); es[0].pos = Vector2i(5, 6); es[1].pos = Vector2i(4, 2)
			cb.terrain[2][4] = T.FLOOR
			main.screen.grid.queue_redraw()])
		plan.append([sz, "combat_fx", func():
			# battle visuals frozen mid-flight (DECISIONS #183): DM-100 lightning, a shaman bolt, an Evil Eye ray,
			# a spirit arrow, a white hit flash on the rat and a gnoll in its die frames
			GameState.run.biome = "prison"; GameState.run.floor = 7
			main.start_combat({"kind": "combat", "room": DB.biome_rooms.prison[0], "mobs": ["dm100", "shaman", "eye", "rat"]}, func(_r): pass)
			var cb = main.screen.combat; var T = cb.T; var g = main.screen.grid
			for y in range(1, cb.SIZE - 1):
				for x in range(1, cb.SIZE - 1): cb.terrain[y][x] = T.FLOOR
			cb.danger.clear()
			var es: Array = cb.enemies()
			cb.hero.pos = Vector2i(3, 5); es[0].pos = Vector2i(6, 2); es[1].pos = Vector2i(6, 6); es[2].pos = Vector2i(1, 1); es[3].pos = Vector2i(5, 4)
			for u in cb.units: g.disp[u.uid] = Vector2(u.pos)
			g.shots = [{"kind": "lightning", "from": Vector2(6, 2), "to": Vector2(3, 5), "t": 0.05, "dur": 1000.0, "col": Color.WHITE, "mid": Vector2(4.8, 3.2)},
				{"kind": "magic", "from": Vector2(6, 6), "to": Vector2(3, 5), "t": 500.0, "dur": 1000.0, "col": Color("ff4d4d"), "mid": Vector2.ZERO},
				{"kind": "deathray", "from": Vector2(1, 1), "to": Vector2(1, 6), "t": 100.0, "dur": 1000.0, "col": Color.WHITE, "mid": Vector2.ZERO},
				{"kind": "arrow", "from": Vector2(3, 5), "to": Vector2(5, 4), "t": 500.0, "dur": 1000.0, "col": Color.WHITE, "mid": Vector2.ZERO}]
			g.flash[es[3].uid] = 1000.0
			g.dying = [{"sprite": "gnoll", "fw": 12, "fh": 15, "row": 0, "pos": Vector2(2, 3), "flip": true, "t": 0.3}]
			g.queue_redraw()])
		plan.append([sz, "boss", func():
			GameState.run.biome = "sewers"; GameState.run.floor = 1
			main.start_combat({"kind": "combat", "boss": true, "room": DB.boss_rooms[0], "mobs": ["goo"]}, func(_r): pass)
			for i in 3: main.screen._do_bot()])
	# v0.44.1 phone report (Fold inner): the Rogue's artifact slot with a pack swap must not squeeze into a sliver.
	# After every other shot at every size: these replace the Warrior run, end it and level the Rogue, which the
	# shots above (and the next size's) would otherwise pick up
	for sz in SIZES:
		plan.append([sz, "hero_swap_delve", func():
			_rogue_swap_run(); Paperdoll.sel_slot = "artifact"
			# event_result left its result window open on the reused delve screen; close it so it doesn't cover the bag
			if main.delve != null and is_instance_valid(main.delve): main.delve._accept_summary()
			main.show_delve(); main.delve._open_panel("backpack"); _scroll_to_doll.call_deferred()])
		# DECISIONS #206: the Rogue's cloak charges last the expedition - "Cloak 2/3" on the Brought row and the fight's Cloak button
		plan.append([sz, "cloak_delve", func():
			if main.delve != null and is_instance_valid(main.delve): main.delve._close_panel()
			GameState.run.cloak_charges = 2; main.show_delve(); _clear_pops(); main.delve.running = false])
		plan.append([sz, "cloak_combat", func():
			main.start_combat({"kind": "combat", "room": DB.rooms[0], "mobs": ["skeleton"]}, func(_r): pass)])
		plan.append([sz, "hero_swap_camp", func():
			GameState.end_run("abandon"); _rogue_swap_camp(); Paperdoll.sel_slot = "artifact"
			main.show_camp(); main.screen.chosen_hero = "rogue"; main.screen.open_page("Heroes")])
	# DECISIONS #207: SPD weapon windows (Stash item window) and a Spear swinging from 2 tiles. Last, on a fresh Warrior.
	for sz in SIZES:
		for wid in ["mace", "spear", "whip", "flail", "round_shield", "assassins_blade"]:
			plan.append([sz, "weapon_" + wid, func():
				if main.screen.has_method("_close_info"): main.screen._close_info()
				if not GameState.run.is_empty(): GameState.end_run("abandon")
				GameState.heroes.warrior.str = 14
				main.show_camp(); main.screen.chosen_hero = "warrior"; main.screen.section["Stash"] = "gear"; main.screen.open_page("Stash")
				var g: Dictionary = GameState.gear_by_uid(GameState.add_gear(wid, true, 1 if wid == "round_shield" else 0))
				main.screen.info(g.id, GameState.gear_name(g), main.screen.gear_lines(g), main.screen.gear_actions(g))])
		plan.append([sz, "combat_reach", func():
			if main.screen.has_method("_close_info"): main.screen._close_info()
			GameState.heroes.warrior.weapon = GameState.add_gear("spear", true, 0); GameState.heroes.warrior.str = 12
			if not GameState.run.is_empty(): GameState.end_run("abandon")
			GameState.start_run("warrior", {}, "sewers", 5); main.show_delve(); main.delve.running = false
			var room := ["########", "#......#", "#.H.1..#", "#......#", "#....2.#", "#......#", "#......#", "########"]
			main.start_combat({"kind": "combat", "room": room, "mobs": ["gnoll", "rat"]}, func(_r): pass)
			for e in main.screen.combat.enemies(): e.seen_hero = true
			main.screen._refresh()])
		plan.append([sz, "combat_reach_swing", func():
			var cb = main.screen.combat
			for e in cb.enemies():
				if Combat.cheb(e.pos, cb.hero.pos) > 1 and cb.can_melee(e): main.screen._on_cell(e.pos); break])

func _process(_d: float) -> void:
	if f == 0 and OS.has_environment("SHOTS"):  # SHOTS=caves,dm300 -> only those steps
		var only: PackedStringArray = OS.get_environment("SHOTS").split(",")
		plan = plan.filter(func(st): return st[1] in only)
	f += 1
	var i := f / 12
	if i >= plan.size():
		SaveSystem.wipe(); get_tree().quit(); return
	var step = plan[i]
	if f % 12 == 1:
		UsePopup.close_open()   # the use_popup shot's pop-up must not cover the next shots
		get_window().size = SIZES[step[0]] * RENDER_SCALE
		step[2].call()
		# SCENE_ONLY=1: hide the delve's card so the scene art behind it can be audited (fix6)
		if OS.has_environment("SCENE_ONLY") and main.get("delve") != null and is_instance_valid(main.delve): main.delve.win_layer.visible = false
	if f % 12 == 11:
		var img := get_viewport().get_texture().get_image()
		if not OS.has_environment("SHOT_NATIVE"): img.resize(SIZES[step[0]].x, SIZES[step[0]].y, Image.INTERPOLATE_LANCZOS)
		img.save_png("%s/%s_%s.png" % [out, step[0], step[1]])
		if main.screen.get("grid") != null: print("GRID ", step[1], " ", main.screen.grid.size, " cs=", main.screen.grid.cell_size(), " win=", get_viewport().get_visible_rect().size)
		if false: print("box ", main.screen.root_box.size, " title ", main.screen.root_box.get_child(0).size, " tabs ", main.screen.tabs.size, " anchors ", main.screen.root_box.anchor_right, " off ", main.screen.root_box.offset_right)


## The staged "+3 gold" pop of delve_walk lives 1.1 s, longer than the next shots take, so clear it (DECISIONS #113).
## The delve_death corpses would also linger over the next scenes, so they go too.
func _clear_pops() -> void:
	if main.delve != null and main.delve.scene != null:
		main.delve.scene.pops.clear(); main.delve.scene.glow = 0.0; main.delve.scene._dying = {}


## A delve corridor walk in another biome (tile sheet, wall deco, region props).
func _biome_walk(biome: String, fl: int) -> void:
	_fresh_warrior_run(); main.show_delve(); _clear_pops()
	GameState.run.biome = biome; GameState.run.floor = fl
	main.delve.scene._floor_seen = fl   # a jump from Sewers 1 is not a descent: no fade-in from black in the shot
	main.delve.pending = {}; main.delve.running = true; main.delve._show_card()
	main.delve.scene.scroll = main.delve.scene.target - 0.6


## Delve shots always start from a clean Warrior run on Sewers 1 (no state leaking from boss/biome shots).
func _fresh_warrior_run() -> void:
	if not GameState.run.is_empty() and (GameState.run.hero != "warrior" or GameState.run.biome != "sewers" or int(GameState.run.floor) > 5):
		GameState.run = {}
	if GameState.run.is_empty():
		for k in ["ration", "torch", "potion_healing"]: GameState.add_mat(k, 1)
		GameState.start_run("warrior", {"ration": 1, "torch": 1, "potion_healing": 1}, "sewers", 5)


## A Lv10 Rogue on Prison 10 wearing the Cape of Thorns, with a Horn of Plenty in the pack (the phone report).
func _rogue_swap_run() -> void:
	GameState.run = {}; _rogue_swap_camp()
	GameState.start_run("rogue", {}, "prison", 10)
	GameState.run.pack_gear.append({"uid": 9300, "id": "horn_plenty", "lvl": 0, "cracked": false, "known": true, "owned": false})

func _rogue_swap_camp() -> void:
	var h: Dictionary = GameState.heroes.rogue
	h.unlocked = true; h.level = 10
	if int(h.get("artifact", 0)) == 0: GameState.equip("rogue", GameState.add_gear("cape_thorns", true, 2))
	if not GameState.gear.any(func(g): return g.id == "horn_plenty" and GameState.equipped_by(g.uid) == ""): GameState.add_gear("horn_plenty")
	if not GameState.gear.any(func(g): return g.id == "chalice_blood"): GameState.equip("warrior", GameState.add_gear("chalice_blood", true, 1))

func _scroll_to_doll() -> void:
	var pd = main.delve.card_host.find_child("Paperdoll", true, false)
	if pd: (main.delve.card_host.get_parent() as ScrollContainer).scroll_vertical = int(pd.position.y)
