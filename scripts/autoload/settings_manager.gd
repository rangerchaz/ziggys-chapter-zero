## Player-facing options for A Night at Ziggy's.
##
## Registered as the SettingsManager autoload (see project.godot), so it
## runs before the title screen draws: resolution, display mode and bus
## volumes are read from user://settings.cfg and applied in _ready().
## Every setter re-applies and rewrites the file, so the settings screen
## never has to think about persistence. ConfigFile on purpose; JSON is
## reserved for game-state saves per the spec.
extends Node

## Emitted after a resolution change has been applied and saved.
signal resolution_changed(size: Vector2i)
## Emitted after the window mode has been applied and saved.
signal fullscreen_changed(enabled: bool)
## Emitted after a bus volume has been applied and saved.
signal volume_changed(bus: StringName, linear: float)

const SETTINGS_PATH := "user://settings.cfg"
const DISPLAY_SECTION := "display"
const AUDIO_SECTION := "audio"

## The resolutions the settings screen offers, smallest first.
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]
const DEFAULT_RESOLUTION := Vector2i(1920, 1080)

## Buses the player can mix, matching default_bus_layout.tres.
const VOLUME_BUSES: Array[StringName] = [&"Master", &"Music", &"SFX", &"Ambient"]
const DEFAULT_VOLUME := 1.0
## linear_to_db(0.0) is -inf, which neither ConfigFile nor the mixer
## should ever see; sliders at (or effectively at) zero write this instead.
const SILENCE_DB := -80.0

var resolution: Vector2i = DEFAULT_RESOLUTION
var fullscreen := false

var _volumes: Dictionary = {}


func _ready() -> void:
	for bus in VOLUME_BUSES:
		_volumes[bus] = DEFAULT_VOLUME
	_load()
	_apply_window()
	for bus in VOLUME_BUSES:
		_apply_volume(bus)


func set_resolution(size: Vector2i) -> void:
	resolution = size
	_apply_window()
	_save()
	resolution_changed.emit(size)


func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	_apply_window()
	_save()
	fullscreen_changed.emit(enabled)


func set_volume(bus: StringName, linear: float) -> void:
	if bus not in VOLUME_BUSES:
		push_warning("Unknown audio bus '%s'; expected one of %s" % [bus, VOLUME_BUSES])
		return
	_volumes[bus] = clampf(linear, 0.0, 1.0)
	_apply_volume(bus)
	_save()
	volume_changed.emit(bus, _volumes[bus])


func get_volume(bus: StringName) -> float:
	return _volumes.get(bus, DEFAULT_VOLUME)


## New-machine state: 1920x1080 windowed, every bus at full volume.
func reset_to_defaults() -> void:
	resolution = DEFAULT_RESOLUTION
	fullscreen = false
	for bus in VOLUME_BUSES:
		_volumes[bus] = DEFAULT_VOLUME
	_apply_window()
	for bus in VOLUME_BUSES:
		_apply_volume(bus)
	_save()


## Every setter above already persists on the spot, so nothing is ever
## actually pending - this exists so a quit path (pause menu, title) can
## say explicitly "save current settings first" without relying on that
## being an implementation detail someone could change later.
func save_now() -> void:
	_save()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return  # First boot: nothing saved yet, keep defaults.

	var stored_res: Variant = cfg.get_value(DISPLAY_SECTION, "resolution", DEFAULT_RESOLUTION)
	if stored_res is Vector2i and RESOLUTIONS.has(stored_res):
		resolution = stored_res
	fullscreen = bool(cfg.get_value(DISPLAY_SECTION, "fullscreen", false))

	for bus in VOLUME_BUSES:
		var stored: Variant = cfg.get_value(AUDIO_SECTION, String(bus), DEFAULT_VOLUME)
		if stored is float or stored is int:
			_volumes[bus] = clampf(float(stored), 0.0, 1.0)


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(DISPLAY_SECTION, "resolution", resolution)
	cfg.set_value(DISPLAY_SECTION, "fullscreen", fullscreen)
	for bus in VOLUME_BUSES:
		cfg.set_value(AUDIO_SECTION, String(bus), _volumes[bus])
	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		push_warning("Could not save settings to %s (error %d)" % [SETTINGS_PATH, err])


func _apply_window() -> void:
	# The dummy display server (--headless) has no window to move; settings
	# still load and persist so tests can exercise everything else.
	if DisplayServer.get_name() == "headless":
		return
	if fullscreen:
		if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(resolution)
		_center_window()


func _center_window() -> void:
	var screen := DisplayServer.window_get_current_screen()
	var origin := DisplayServer.screen_get_position(screen)
	var screen_size := DisplayServer.screen_get_size(screen)
	var window_size := DisplayServer.window_get_size()
	DisplayServer.window_set_position(origin + (screen_size - window_size) / 2)


func _apply_volume(bus: StringName) -> void:
	var index := AudioServer.get_bus_index(String(bus))
	if index < 0:
		push_warning("Audio bus '%s' is missing from the bus layout" % bus)
		return
	var linear: float = _volumes[bus]
	AudioServer.set_bus_volume_db(index, SILENCE_DB if linear <= 0.0001 else linear_to_db(linear))
