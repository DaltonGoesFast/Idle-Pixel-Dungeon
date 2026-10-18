## Telemetry: anonymous gameplay events for balance testing, batched to PostHog's /batch/ capture API
## (DECISIONS #197, docs/PRIVACY.md). Every player sends them; the first launch shows a one-time notice.
## - Anonymous: a random UUID made on first launch (user://telemetry.cfg). No names, accounts, device ids or
##   free text; props are game values only (numbers, ids from data/*.json, booleans).
## - Config: data/telemetry.json {api_key, host}. Empty api_key = no-op (debug builds print events instead).
## - Never blocks or breaks play: one HTTPRequest at a time, errors only back off, events queue to a capped
##   file (user://telemetry_queue.json, IndexedDB on the web build) and go out on a later flush.
## - Off in tests, the sims, any headless run, any run from source (the editor binary: dev sessions, the playtest
##   harness under xvfb) and automated or headless browsers on the web build (`suppressed`, DECISIONS #198).
extends Node

const CONFIG_PATH := "res://data/telemetry.json"
const DEFAULT_HOST := "https://us.i.posthog.com"
const DEFAULT_PRIVACY_URL := "https://github.com/DaltonGoesFast/spd-tactics-builds/blob/main/docs/PRIVACY.md"
const LIB := "spd-tactics-godot"

const QUEUE_CAP := 1000          # events kept on disk while offline; the oldest are dropped past this
const BATCH_MAX := 50            # events per POST
const FLUSH_EVERY := 60.0        # seconds between routine flushes
const FLUSH_AT := 20             # flush early once this many events wait
const MIN_GAP := 15.0            # never POST more often than this
const BACKOFF_MIN := 30.0        # after a failed POST; doubles up to BACKOFF_MAX
const BACKOFF_MAX := 900.0
const RATE_PER_MIN := 30         # events accepted per rolling minute; more are dropped (and counted)
const SAVE_EVERY := 5.0          # queue file write debounce
const HTTP_TIMEOUT := 15.0
const NEW_SESSION_AFTER := 1800.0  # back in the app after 30+ minutes away = a new session
const SPEND_EVERY := 300.0       # gold_spent is summed per sink and sent at most every 5 minutes

var api_key := ""
var host := DEFAULT_HOST
var privacy_url := DEFAULT_PRIVACY_URL
var distinct_id := ""
var session_id := ""
var notice_seen := false
var suppressed := false          # tests / sims / headless / source / bot browsers: nothing is queued, nothing is sent
var suppressed_by := ""          # suppress_reason() at launch ("" = a player's game)
var queue: Array = []
var dropped := 0                 # events refused by the rate limit or the queue cap this session
var sent_ok := 0
var last_status := 0             # HTTP code of the last POST (0 = none / network error)

var cfg_path := "user://telemetry.cfg"
var queue_path := "user://telemetry_queue.json"

var _http: HTTPRequest
var _in_flight: Array = []       # the batch being POSTed (back in the queue if it fails)
var _busy := false
var _flush_t := 0.0
var _gap_t := 0.0
var _backoff := 0.0
var _save_t := 0.0
var _dirty := false
var _rate: Array = []            # timestamps (s) of recently accepted events
var _session_start := 0.0        # Time.get_ticks_msec()/1000 when the session (or resume) began
var _session_active := 0.0       # active seconds banked before the last pause
var _paused_at := 0.0
var _spend := {}                 # sink -> {gold, n}
var _spend_t := 0.0
var _ended := false
var _scene_checked := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	suppressed_by = suppress_reason()
	suppressed = suppressed_by != ""
	load_config()
	_load_identity()
	_load_queue()
	_http = HTTPRequest.new()
	_http.timeout = HTTP_TIMEOUT
	_http.use_threads = OS.get_name() != "Web"   # the web export has no threads; fetch() is async anyway
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	_new_session()
	track("app_open", {"returning": notice_seen, "queued": queue.size()})

## Tests, sims, headless runs, runs from source and automated browsers never collect anything.
static func is_test_run() -> bool:
	return suppress_reason() != ""

## Why this run must not collect ("" = a player's exported game). DECISIONS #197/#198: only exported builds (APK, EXE,
## the GitHub Pages build) in a real browser or on a real device send. Runs from source use the editor binary (the
## developer's own sessions, the playtest harness and its probes under xvfb, which aren't headless and don't live
## in res://tests/), and an automated browser (navigator.webdriver) is a check of the web build, not a player.
## SPD_TELEMETRY_FROM_SOURCE=1 lets a deliberate check from the editor send (never headless or tests).
static func suppress_reason() -> String:
	var tests := false
	for a in OS.get_cmdline_args():
		if String(a).ends_with(".tscn") and String(a).contains("tests/"): tests = true
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var cs: Node = (ml as SceneTree).current_scene
		if cs != null and cs.scene_file_path.begins_with("res://tests/"): tests = true
	var bot := false
	if OS.has_feature("web"):
		# Only navigator.webdriver (Playwright/Puppeteer/Selenium). Do not key on user-agent strings —
		# real browsers set those, and HeadlessChrome alone must not suppress a player's export.
		var wd = JavaScriptBridge.eval("navigator.webdriver === true", true)
		bot = automated_browser(typeof(wd) == TYPE_BOOL and wd)
	return classify(OS.has_environment("SPD_NO_TELEMETRY"), DisplayServer.get_name() == "headless", tests,
		OS.has_feature("editor"), OS.has_environment("SPD_TELEMETRY_FROM_SOURCE"), bot)

## The decision itself, from plain facts about the run (so tests can cover every case).
static func classify(env_off: bool, headless: bool, tests: bool, from_source: bool, source_allowed: bool, automated: bool) -> String:
	if env_off: return "env"
	if headless: return "headless"
	if tests: return "tests"
	if from_source and not source_allowed: return "source"
	if automated: return "automated_browser"
	return ""

## A browser driven by a test tool (Playwright, Puppeteer, Selenium set navigator.webdriver).
## User-agent strings are ignored: real players' browsers set them, and must still send.
static func automated_browser(webdriver: bool) -> bool:
	return webdriver

func load_config(path := CONFIG_PATH) -> void:
	api_key = ""; host = DEFAULT_HOST; privacy_url = DEFAULT_PRIVACY_URL
	if not FileAccess.file_exists(path): return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY: return
	if typeof(d.get("api_key")) == TYPE_STRING: api_key = String(d.api_key).strip_edges()
	if typeof(d.get("host")) == TYPE_STRING: host = sane_host(String(d.host), host)
	if typeof(d.get("privacy_url")) == TYPE_STRING and String(d.privacy_url) != "": privacy_url = String(d.privacy_url)

## https only (plain http just for a local test server on 127.0.0.1 / localhost).
static func sane_host(h: String, fallback: String) -> String:
	var x := h.strip_edges().trim_suffix("/")
	if x.begins_with("https://") or x.begins_with("http://127.0.0.1") or x.begins_with("http://localhost"): return x
	return fallback

## True when events are queued and sent (a key is set and this is a real game run).
func enabled() -> bool:
	return api_key != "" and not suppressed

# ------------------------------------------------------------------ identity
static func new_uuid() -> String:
	var b := Crypto.new().generate_random_bytes(16)
	b[6] = (b[6] & 0x0f) | 0x40   # version 4
	b[8] = (b[8] & 0x3f) | 0x80   # RFC 4122 variant
	var h := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]

func _load_identity() -> void:
	var c := ConfigFile.new()
	if c.load(cfg_path) == OK:
		distinct_id = String(c.get_value("telemetry", "distinct_id", ""))
		notice_seen = bool(c.get_value("telemetry", "notice_seen", false))
	if distinct_id.length() != 36:
		distinct_id = new_uuid()
		_save_identity()

func _save_identity() -> void:
	if suppressed: return   # tests never write the real identity file
	var c := ConfigFile.new()
	c.set_value("telemetry", "distinct_id", distinct_id)
	c.set_value("telemetry", "notice_seen", notice_seen)
	c.save(cfg_path)

## The one-time disclosure (Main shows it on first launch).
func needs_notice() -> bool:
	return not notice_seen and not suppressed

func mark_notice_seen() -> void:
	notice_seen = true
	_save_identity()
	track("notice_seen", {})

# ------------------------------------------------------------------ sessions
func _now_s() -> float:
	return Time.get_ticks_msec() / 1000.0

func _new_session() -> void:
	session_id = new_uuid()
	_session_start = _now_s(); _session_active = 0.0; _ended = false

func session_seconds() -> float:
	return _session_active + (0.0 if _ended else _now_s() - _session_start)

func _end_session(reason: String) -> void:
	if _ended: return
	_flush_spend()
	track("session_end", {"duration_s": int(round(session_seconds())), "reason": reason, "dropped": dropped})
	_session_active = session_seconds(); _ended = true
	_save_queue()
	flush(true)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST:
			_paused_at = _now_s()
			_end_session("close" if what == NOTIFICATION_WM_CLOSE_REQUEST else "background")
		NOTIFICATION_APPLICATION_RESUMED:
			if not _ended: return
			if _now_s() - _paused_at >= NEW_SESSION_AFTER:
				_new_session(); track("app_open", {"returning": true, "resume": true, "queued": queue.size()})
			else:
				_session_start = _now_s(); _ended = false   # same session, the time away doesn't count
		NOTIFICATION_PREDELETE:
			if _dirty: _save_queue()

# ------------------------------------------------------------------ events
static func platform() -> String:
	match OS.get_name():
		"Android": return "android"
		"Windows": return "windows"
		"Web": return "web"
		"iOS": return "ios"
		"macOS": return "macos"
		"Linux": return "linux"
	return OS.get_name().to_lower()

static func game_version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "0"))

## The current run's hero ("" at Camp).
func _cls() -> String:
	var ml := Engine.get_main_loop()
	var gs = (ml as SceneTree).root.get_node_or_null("GameState") if ml is SceneTree else null
	if gs == null or gs.run.is_empty(): return ""
	return String(gs.run.get("hero", ""))

## One PostHog event: {event, distinct_id, timestamp, properties}. Only scalar / array / dict game values pass.
func build_event(event: String, props: Dictionary, unix := -1.0) -> Dictionary:
	var p := {}
	for k in props: p[String(k)] = _clean(props[k], 0)
	if not p.has("class"): p["class"] = _cls()
	p["version"] = game_version()
	p["platform"] = platform()
	p["session_id"] = session_id
	p["$session_id"] = session_id
	p["$lib"] = LIB
	p["$process_person_profile"] = false   # anonymous events: no person profiles
	p["$geoip_disable"] = true             # no IP-derived location
	p["distinct_id"] = distinct_id
	var t := Time.get_unix_time_from_system() if unix < 0.0 else unix
	# uuid lets PostHog drop a duplicate if a sent batch is ever resent (e.g. killed before the queue file updated)
	return {"event": event, "uuid": new_uuid(), "distinct_id": distinct_id, "timestamp": Time.get_datetime_string_from_unix_time(int(t)) + "Z", "properties": p}

## JSON-safe copy limited to numbers, bools, short strings and small containers (depth 2).
static func _clean(v, depth: int):
	match typeof(v):
		TYPE_BOOL, TYPE_INT: return v
		TYPE_FLOAT: return snappedf(v, 0.001)
		TYPE_STRING, TYPE_STRING_NAME: return String(v).substr(0, 64)
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY:
			if depth >= 2: return null
			var a := []
			for x in v:
				if a.size() >= 32: break
				a.append(_clean(x, depth + 1))
			return a
		TYPE_DICTIONARY:
			if depth >= 2: return null
			var d := {}
			for k in v:
				if d.size() >= 32: break
				d[String(k).substr(0, 48)] = _clean(v[k], depth + 1)
			return d
	return null

## The /batch/ body PostHog expects.
func build_batch(events: Array) -> Dictionary:
	return {"api_key": api_key, "batch": events}

func batch_url() -> String:
	return host + "/batch/"

## Record an event. Never raises; a no-op in tests/sims and when no key is set (debug builds print it).
func track(event: String, props := {}) -> void:
	if suppressed: return
	if not _scene_checked:   # the main scene isn't set yet when autoloads start; check once it is
		var cs := get_tree().current_scene if is_inside_tree() else null
		if cs != null:
			_scene_checked = true
			if cs.scene_file_path.begins_with("res://tests/"): suppressed = true; suppressed_by = "tests"; queue = []; return
	var e := build_event(event, props)
	if api_key == "":
		if OS.is_debug_build(): print("[telemetry] ", JSON.stringify(e.properties.merged({"event": event})))
		return
	enqueue(e)

## Rate-limited, capped append (public so tests can drive it with a key set).
func enqueue(e: Dictionary) -> bool:
	var now := _now_s()
	while not _rate.is_empty() and now - float(_rate[0]) > 60.0: _rate.pop_front()
	if _rate.size() >= RATE_PER_MIN and String(e.get("event", "")) != "session_end":
		dropped += 1; return false
	_rate.append(now)
	queue.append(e)
	while queue.size() > QUEUE_CAP:
		queue.pop_front(); dropped += 1
	_dirty = true
	return true

## Gold sinks are summed per sink and sent as one gold_spent event per sink every few minutes.
func spend(sink: String, gold: int) -> void:
	if suppressed or gold <= 0: return
	var s: Dictionary = _spend.get(sink, {"gold": 0, "n": 0})
	s.gold = int(s.gold) + gold; s.n = int(s.n) + 1
	_spend[sink] = s

func _flush_spend() -> void:
	for sink in _spend:
		track("gold_spent", {"sink": sink, "gold": int(_spend[sink].gold), "count": int(_spend[sink].n)})
	_spend = {}

# ------------------------------------------------------------------ sending
func _process(delta: float) -> void:
	if suppressed: return
	_flush_t += delta; _gap_t += delta; _save_t += delta; _spend_t += delta
	if _backoff > 0.0: _backoff = maxf(0.0, _backoff - delta)
	if _spend_t >= SPEND_EVERY:
		_spend_t = 0.0; _flush_spend()
	if _dirty and _save_t >= SAVE_EVERY: _save_queue()
	if _flush_t >= FLUSH_EVERY or queue.size() >= FLUSH_AT: flush()

## POST up to BATCH_MAX queued events. force skips the routine gap (still respects backoff and one-at-a-time).
func flush(force := false) -> bool:
	if not enabled() or _busy or queue.is_empty() or _backoff > 0.0: return false
	if not force and _gap_t < MIN_GAP: return false
	_flush_t = 0.0; _gap_t = 0.0
	var n := mini(BATCH_MAX, queue.size())
	_in_flight = queue.slice(0, n)
	queue = queue.slice(n)
	var body := JSON.stringify(build_batch(_in_flight))
	var err := _http.request(batch_url(), ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		_requeue(); _fail()
		return false
	_busy = true
	return true

func _requeue() -> void:
	queue = _in_flight + queue
	while queue.size() > QUEUE_CAP:
		queue.pop_front(); dropped += 1
	_in_flight = []; _dirty = true

func _fail() -> void:
	_backoff = clampf(maxf(BACKOFF_MIN, _backoff * 2.0), BACKOFF_MIN, BACKOFF_MAX)

func _on_request_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_busy = false
	last_status = code if result == HTTPRequest.RESULT_SUCCESS else 0
	if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300:
		sent_ok += _in_flight.size(); _in_flight = []; _backoff = 0.0
		_save_queue()   # right away: _process doesn't run while paused, and a stale file would resend this batch
		return
	if result == HTTPRequest.RESULT_SUCCESS and code >= 400 and code < 500 and code != 429:
		# a bad key or payload never succeeds on retry: drop the batch instead of looping on it
		dropped += _in_flight.size(); _in_flight = []; _fail()
		_save_queue()
		return
	_requeue(); _fail()
	_save_queue()

# ------------------------------------------------------------------ offline queue
func _save_queue() -> void:
	_dirty = false; _save_t = 0.0
	if suppressed: return
	var all: Array = _in_flight + queue
	if all.size() > QUEUE_CAP: all = all.slice(all.size() - QUEUE_CAP)
	var f := FileAccess.open(queue_path, FileAccess.WRITE)
	if f == null: return
	f.store_string(JSON.stringify(all))
	f.close()

func _load_queue() -> void:
	queue = []
	if suppressed or not FileAccess.file_exists(queue_path): return
	var f := FileAccess.open(queue_path, FileAccess.READ)
	if f == null: return
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_ARRAY: return
	for e in d:
		if typeof(e) == TYPE_DICTIONARY and e.has("event") and e.has("properties"): queue.append(e)
	if queue.size() > QUEUE_CAP: queue = queue.slice(queue.size() - QUEUE_CAP)
