## Updater: check GitHub releases and download the platform asset (Android APK / Windows zip).
## Not part of the save. Android hands the APK to the system installer; Windows opens the zip.
## Auto-checks on launch and when the app resumes (DECISIONS #242); Camp shows a Settings badge.
extends Node

signal changed

const REPO := "DaltonGoesFast/Idle-Pixel-Dungeon"
const API_URL := "https://api.github.com/repos/%s/releases/latest" % REPO
const USER_AGENT := "SPD-Tactics-Updater"
const UPDATE_DIR := "user://updates"
const CHECK_TIMEOUT := 20.0      # the releases/latest JSON is small; don't sit on "Checking…" for minutes
const DOWNLOAD_TIMEOUT := 600.0  # the APK / zip is tens of MB
const RECHECK_COOLDOWN := 300.0  # automatic rechecks at most every 5 min (GitHub: 60/hour/IP)
const ERROR_RECHECK_COOLDOWN := 60.0  # retry sooner after a failed check (no network / HTTP error)

enum State { IDLE, CHECKING, READY, DOWNLOADING, DONE, ERROR }

var state: int = State.IDLE
var remote_version := ""
var remote_tag := ""
var asset_name := ""
var asset_url := ""
var status_text := ""
var progress := 0.0
var local_path := ""

var _http: HTTPRequest
var _mode := ""   # "check" | "download"
var _poll_left := 0.0
var _last_check_unix := 0.0

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = DOWNLOAD_TIMEOUT
	_http.max_redirects = 8
	_http.use_threads = http_uses_threads()
	add_child(_http)
	_http.request_completed.connect(_on_http)
	# First check without waiting for Camp or Settings to open (Android often stays warm in memory).
	maybe_check()

func _notification(what: int) -> void:
	# Sideloaded Android keeps the process alive; closing from Recents was the only reliable recheck.
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		maybe_check()

func supports_platform() -> bool:
	return asset_suffix() != ""

## Vita has no installer asset, and its HTTP client stays on the main thread.
static func http_uses_threads(os_name: String = OS.get_name()) -> bool:
	return os_name != "Vita"

## ".apk", "-windows.zip", or "" if this build has no update asset.
static func asset_suffix() -> String:
	var n := OS.get_name()
	if n == "Android":
		return ".apk"
	if n == "Windows":
		return "-windows.zip"
	return ""

static func normalize_version(v: String) -> String:
	var s := v.strip_edges()
	if s.begins_with("v") or s.begins_with("V"):
		s = s.substr(1)
	return s

## -1 if a < b, 0 if equal, 1 if a > b. Non-numeric parts compare as 0.
static func compare_versions(a: String, b: String) -> int:
	var aa := normalize_version(a).split(".")
	var bb := normalize_version(b).split(".")
	var n := maxi(aa.size(), bb.size())
	for i in n:
		var x := int(aa[i]) if i < aa.size() else 0
		var y := int(bb[i]) if i < bb.size() else 0
		if x < y:
			return -1
		if x > y:
			return 1
	return 0

static func local_version() -> String:
	return normalize_version(String(ProjectSettings.get_setting("application/config/version", "0")))

## Pick the release asset for this platform. Returns {name, url} or {}.
## `assets` comes straight from the API JSON, so anything that is not an Array of
## {name: String, browser_download_url: String} is skipped instead of raising a script error.
static func pick_asset(assets, version: String, suffix: String) -> Dictionary:
	if suffix == "" or typeof(assets) != TYPE_ARRAY:
		return {}
	var want := "spd-tactics-v%s%s" % [normalize_version(version), suffix]
	var fallback := {}
	for a in assets:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var name = a.get("name", "")
		var url = a.get("browser_download_url", "")
		if typeof(name) != TYPE_STRING or typeof(url) != TYPE_STRING or url == "":
			continue
		if name == want:
			return {"name": name, "url": url}
		if fallback.is_empty() and name.ends_with(suffix) and name.begins_with("spd-tactics"):
			fallback = {"name": name, "url": url}
	return fallback

func has_update() -> bool:
	return state == State.READY or state == State.DOWNLOADING or (state == State.DONE and remote_version != "")

## True when an automatic check should run (cooldown elapsed, not mid-download / mid-check).
## Skips while READY/DONE — the Camp badge and Update button already show the known update.
func should_auto_check() -> bool:
	if not supports_platform():
		return false
	if state == State.CHECKING or state == State.DOWNLOADING:
		return false
	if state == State.READY or state == State.DONE:
		return false
	if _last_check_unix <= 0.0:
		return true
	var cool := ERROR_RECHECK_COOLDOWN if state == State.ERROR else RECHECK_COOLDOWN
	return Time.get_unix_time_from_system() - _last_check_unix >= cool

## Quiet recheck used on launch, resume, and Camp rebuild. `force` bypasses the cooldown
## (Settings "Check for update" / Try again still call `check_now` / `start_update` directly).
func maybe_check(force := false) -> void:
	if force:
		if state == State.CHECKING or state == State.DOWNLOADING:
			return
		check_now()
		return
	if should_auto_check():
		check_now()

func check_now() -> void:
	if not supports_platform():
		_set_state(State.IDLE, "")
		return
	if state == State.CHECKING or state == State.DOWNLOADING:
		return
	_last_check_unix = Time.get_unix_time_from_system()
	_mode = "check"
	_set_state(State.CHECKING, "Checking…")
	_http.timeout = CHECK_TIMEOUT
	var err := _http.request(API_URL, ["User-Agent: %s" % USER_AGENT, "Accept: application/vnd.github+json"])
	if err != OK:
		_set_state(State.ERROR, "No network")

func start_update() -> void:
	if state == State.DOWNLOADING:
		return
	if state == State.DONE and local_path != "" and FileAccess.file_exists(local_path):
		_apply_local()
		return
	if asset_url == "":
		check_now()
		return
	if state != State.READY and state != State.ERROR and state != State.DONE:
		return
	_begin_download()

func _begin_download() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(UPDATE_DIR))
	local_path = "%s/%s" % [UPDATE_DIR, asset_name]
	if FileAccess.file_exists(local_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(local_path))
	_http.download_file = local_path
	_http.timeout = DOWNLOAD_TIMEOUT
	_mode = "download"
	progress = 0.0
	_poll_left = 0.0
	_set_state(State.DOWNLOADING, "Downloading 0%")
	var err := _http.request(asset_url, ["User-Agent: %s" % USER_AGENT])
	if err != OK:
		_http.download_file = ""
		_set_state(State.ERROR, "Download failed")

func _process(delta: float) -> void:
	if state != State.DOWNLOADING:
		return
	_poll_left -= delta
	if _poll_left > 0.0:
		return
	_poll_left = 0.25
	var got := _http.get_downloaded_bytes()
	var total := _http.get_body_size()
	if total > 0:
		progress = clampf(float(got) / float(total), 0.0, 1.0)
		_set_state(State.DOWNLOADING, "Downloading %d%%" % int(progress * 100.0))
	else:
		_set_state(State.DOWNLOADING, "Downloading…")

func _on_http(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var was := _mode
	_mode = ""
	_http.download_file = ""
	if was == "check":
		_finish_check(result, code, body)
	elif was == "download":
		_finish_download(result, code)

func _finish_check(result: int, code: int, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_state(State.ERROR, "No network")
		return
	if code != 200:
		_set_state(State.ERROR, "Check failed (HTTP %d)" % code)
		return
	# Every bad body must land in ERROR: a script error here would leave the state on CHECKING,
	# and check_now() refuses to run again while CHECKING (stuck until the app restarts).
	var json := JSON.new()
	var parsed = json.data if json.parse(body.get_string_from_utf8()) == OK else null
	if typeof(parsed) != TYPE_DICTIONARY:
		_set_state(State.ERROR, "Bad reply from GitHub")
		return
	var tag_v = parsed.get("tag_name", "")
	if typeof(tag_v) != TYPE_STRING:
		_set_state(State.ERROR, "Bad reply from GitHub")
		return
	var tag: String = tag_v
	var ver := normalize_version(tag)
	if ver == "":
		_set_state(State.ERROR, "No matching file")
		return
	var picked := pick_asset(parsed.get("assets", []), ver, asset_suffix())
	if picked.is_empty() or String(picked.get("url", "")) == "":
		_set_state(State.ERROR, "No matching file")
		return
	remote_tag = tag
	remote_version = ver
	asset_name = String(picked.name)
	asset_url = String(picked.url)
	if compare_versions(local_version(), ver) >= 0:
		_set_state(State.IDLE, "Up to date")
		return
	_set_state(State.READY, "Update to v%s" % ver)

func _finish_download(result: int, code: int) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		if FileAccess.file_exists(local_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(local_path))
		_set_state(State.ERROR, "Download stopped")
		return
	if not FileAccess.file_exists(local_path):
		_set_state(State.ERROR, "Download stopped")
		return
	var f := FileAccess.open(local_path, FileAccess.READ)
	if f == null or f.get_length() < 1024:
		_set_state(State.ERROR, "Download stopped")
		return
	f = null
	progress = 1.0
	_set_state(State.DONE, "Installing…")
	_apply_local()

func _apply_local() -> void:
	var abs_path := ProjectSettings.globalize_path(local_path)
	if OS.get_name() == "Windows":
		var err := OS.shell_open(abs_path)
		if err != OK:
			_set_state(State.ERROR, "Could not open zip")
		else:
			_set_state(State.DONE, "Zip opened — unzip and run spd-tactics.exe")
		return
	if OS.get_name() == "Android":
		var msg := install_android_apk(abs_path)
		if msg == "":
			_set_state(State.DONE, "Install prompted")
		elif msg == "settings":
			_set_state(State.READY, "Allow installs, then Update again")
		else:
			_set_state(State.ERROR, msg)
		return
	_set_state(State.ERROR, "No matching file")

## Opens the system package installer. Returns "" on success, "settings" if unknown-apps is off, else an error label.
static func install_android_apk(abs_path: String) -> String:
	if OS.get_name() != "Android":
		return "No matching file"
	var runtime = Engine.get_singleton("AndroidRuntime")
	if runtime == null:
		return "Install failed"
	var activity = runtime.getActivity()
	if activity == null:
		return "Install failed"
	var File := JavaClassWrapper.wrap("java.io.File")
	var apk = File.File(abs_path)
	if apk == null or not apk.exists():
		return "Download stopped"
	var pm = activity.getPackageManager()
	if pm != null and not pm.canRequestPackageInstalls():
		var Settings := JavaClassWrapper.wrap("android.provider.Settings")
		var Uri := JavaClassWrapper.wrap("android.net.Uri")
		var Intent := JavaClassWrapper.wrap("android.content.Intent")
		var settings_intent = Intent.Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
		settings_intent.setData(Uri.parse("package:" + activity.getPackageName()))
		activity.startActivity(settings_intent)
		return "settings"
	# Godot template FileProvider covers the app files dir (user://) as filesRoot.
	var FileProvider := JavaClassWrapper.wrap("androidx.core.content.FileProvider")
	var authority := "%s.fileprovider" % activity.getPackageName()
	var uri = FileProvider.getUriForFile(activity, authority, apk)
	if uri == null or JavaClassWrapper.get_exception() != null:
		return "Install failed"
	var Intent := JavaClassWrapper.wrap("android.content.Intent")
	var intent = Intent.Intent(Intent.ACTION_VIEW)
	intent.setDataAndType(uri, "application/vnd.android.package-archive")
	intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
	intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
	activity.startActivity(intent)
	if JavaClassWrapper.get_exception() != null:
		return "Install failed"
	return ""

func _set_state(s: int, text: String, emit := true) -> void:
	state = s
	status_text = text
	if emit:
		changed.emit()
