## Phase 10 ambient audio probe, headless-safe (checks node/bus state and
## the AudioDirector fade math, not actual sample output):
##
##     godot --headless --path . res://tests/audio_probe.tscn
##
## Verifies the room tone, jukebox and oven AudioStreamPlayer(3D) nodes
## exist, are playing a procedurally-generated AudioStreamGenerator, and
## are routed to the correct bus; that SettingsManager volume changes
## read back on the real AudioServer bus; that AudioDirector.
## set_ambience_state('low_hum') fades the bed down and 'normal' restores
## it; and that no imported audio asset files exist anywhere in the repo.
## Exits 0 on pass, 1 on failure.
extends Node

const RoomScene := preload("res://scenes/room/ziggys_room.tscn")
const IMPORTED_AUDIO_EXTENSIONS := ["ogg", "mp3", "wav"]

var _failures := 0
var _room: Node3D


func _ready() -> void:
	_check_no_imported_audio()

	_room = RoomScene.instantiate()
	_room.get_node(^"PlayerSpawner").auto_spawn = false
	add_child(_room)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	_check_room_tone()
	_check_jukebox()
	_check_oven()
	_check_volume_sliders_affect_bus()
	await _check_ambience_states()

	if _failures == 0:
		print("AUDIO PROBE PASS")
	else:
		printerr("AUDIO PROBE FAIL (%d failures)" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("  ok: %s" % label)
	else:
		_failures += 1
		printerr("  FAIL: %s" % label)


## Deliverable/acceptance constraint: everything audible is synthesized
## in-engine, so no .ogg/.mp3/.wav asset ever needs to be imported.
func _check_no_imported_audio() -> void:
	var found: Array[String] = []
	_scan_for_audio_files("res://", found)
	_expect(found.is_empty(), "no imported audio asset files in the repo (found %s)" % [found])


func _scan_for_audio_files(path: String, found: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue
		var full := path.path_join(entry)
		if dir.current_is_dir():
			if entry != ".godot":
				_scan_for_audio_files(full, found)
		else:
			var ext := entry.get_extension().to_lower()
			if ext in IMPORTED_AUDIO_EXTENSIONS:
				found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _check_room_tone() -> void:
	var player: AudioStreamPlayer = _room.get_node_or_null(^"RoomTone")
	if player == null:
		_expect(false, "RoomTone AudioStreamPlayer exists")
		return
	_expect(player.bus == &"Ambient", "RoomTone routed to the Ambient bus (got %s)" % player.bus)
	_expect(player.stream is AudioStreamGenerator, "RoomTone stream is a procedural AudioStreamGenerator")
	_expect(player.playing, "RoomTone is playing")

	var generator: ProceduralAudio = player.get_node_or_null(^"Generator")
	if generator == null:
		_expect(false, "RoomTone has a Generator (ProceduralAudio) child")
		return
	_expect(generator.profile == ProceduralAudio.Profile.ROOM_TONE, "Generator profile is ROOM_TONE")
	_expect(generator.is_in_group(&"ambient_bed"), "Generator is in the ambient_bed group for AudioDirector")
	_expect(generator.get_playback() != null, "Generator has a live AudioStreamGeneratorPlayback")


func _check_jukebox() -> void:
	var player: AudioStreamPlayer3D = _room.get_node_or_null(^"Props/Jukebox/JukeAudio")
	if player == null:
		_expect(false, "Jukebox has a JukeAudio AudioStreamPlayer3D")
		return
	_expect(player.bus == &"Music", "JukeAudio routed to the Music bus (got %s)" % player.bus)
	_expect(player.stream is AudioStreamGenerator, "JukeAudio stream is a procedural AudioStreamGenerator")
	_expect(player.playing, "JukeAudio is playing")
	_expect(player.max_distance > 0.0, "JukeAudio has a finite max_distance for spatial falloff")

	var generator: ProceduralAudio = player.get_node_or_null(^"Generator")
	_expect(generator != null and generator.profile == ProceduralAudio.Profile.JUKEBOX,
			"Jukebox Generator profile is JUKEBOX")


func _check_oven() -> void:
	var player: AudioStreamPlayer3D = _room.get_node_or_null(^"Props/PizzaOven/OvenAudio")
	if player == null:
		_expect(false, "PizzaOven has an OvenAudio AudioStreamPlayer3D")
		return
	_expect(player.bus == &"SFX", "OvenAudio routed to the SFX bus (got %s)" % player.bus)
	_expect(player.stream is AudioStreamGenerator, "OvenAudio stream is a procedural AudioStreamGenerator")
	_expect(player.playing, "OvenAudio is playing")
	_expect(player.max_distance > 0.0, "OvenAudio has a finite max_distance for spatial falloff")

	var generator: ProceduralAudio = player.get_node_or_null(^"Generator")
	_expect(generator != null and generator.profile == ProceduralAudio.Profile.OVEN,
			"Oven Generator profile is OVEN")


## Flow 13: a slider move must reach the real audio bus, not just a UI
## value. SettingsManager already owns this contract (see smoke_test.gd);
## re-checked here against the buses this phase actually plays audio on.
func _check_volume_sliders_affect_bus() -> void:
	var settings: Node = get_node(^"/root/SettingsManager")

	settings.set_volume(&"Ambient", 0.4)
	var ambient_index := AudioServer.get_bus_index("Ambient")
	var ambient_applied := db_to_linear(AudioServer.get_bus_volume_db(ambient_index))
	_expect(absf(ambient_applied - 0.4) < 0.01,
			"Ambient slider at 0.4 reads back from AudioServer as %.4f" % ambient_applied)

	settings.set_volume(&"Master", 0.6)
	var master_index := AudioServer.get_bus_index("Master")
	var master_applied := db_to_linear(AudioServer.get_bus_volume_db(master_index))
	_expect(absf(master_applied - 0.6) < 0.01,
			"Master slider at 0.6 reads back from AudioServer as %.4f" % master_applied)

	settings.reset_to_defaults()


## Flow 7 (Phase 11's brownout) needs the bed to duck to a quiet hum and
## come back over a stated duration. Exercise both directions here.
func _check_ambience_states() -> void:
	var director: Node = get_node(^"/root/AudioDirector")
	var generator: ProceduralAudio = _room.get_node(^"RoomTone/Generator")

	_expect(generator.level > 0.9 and generator.murmur_level > 0.9,
			"bed starts at full level/murmur before any state change")

	director.set_ambience_state(&"low_hum")
	var low_duration: float = director.get_state_duration(&"low_hum")
	_expect(low_duration > 0.0, "low_hum state declares a positive duration")
	await _settle_seconds(low_duration + 0.2)
	_expect(generator.level < 0.4, "low_hum brings level down near its target (got %.3f)" % generator.level)
	_expect(generator.murmur_level < 0.05, "low_hum drops murmur near zero (got %.3f)" % generator.murmur_level)

	director.set_ambience_state(&"normal")
	var normal_duration: float = director.get_state_duration(&"normal")
	await _settle_seconds(normal_duration + 0.2)
	_expect(generator.level > 0.9, "normal restores level (got %.3f)" % generator.level)
	_expect(generator.murmur_level > 0.9, "normal restores murmur_level (got %.3f)" % generator.murmur_level)


func _settle_seconds(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
