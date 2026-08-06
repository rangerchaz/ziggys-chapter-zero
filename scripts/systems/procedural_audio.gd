## Procedurally synthesizes every ambient sound in the room - a low room
## tone with a crowd-murmur texture, a jukebox loop, and an oven hiss/
## crackle - with plain oscillator and filtered-noise math, no imported
## audio assets. Lives as a child ("Generator") of an AudioStreamPlayer
## (the non-positional room tone) or an AudioStreamPlayer3D (jukebox,
## oven), owns an AudioStreamGenerator on that parent, and keeps its
## ring buffer topped up every _process tick so the loop never has to
## seam or click.
class_name ProceduralAudio
extends Node

enum Profile { ROOM_TONE, JUKEBOX, OVEN }

@export var profile: Profile = Profile.ROOM_TONE
@export var mix_rate: float = 22050.0
## Generous on purpose: this is background ambience with no latency
## requirement, so a big ring buffer trades a little startup delay for
## real resilience against a frame hitch (e.g. a screenshot capture, a
## scene load) causing an audible underrun click.
@export var buffer_length: float = 2.0

## Master gain for this source, 0..1. AudioDirector tweens the room-tone
## instance's level (and murmur_level) for fades/ducks; jukebox and oven
## stay at their authored level.
@export_range(0.0, 1.0) var level: float = 1.0
## Room-tone only: gain of the crowd-murmur noise layer, kept separate
## from the hum so a "low hum" ambience state can drop the murmur to
## near-zero while the low tone stays audible underneath it.
@export_range(0.0, 1.0) var murmur_level: float = 1.0

const JUKEBOX_NOTES: Array[float] = [220.00, 261.63, 329.63, 392.00, 329.63, 261.63]
const JUKEBOX_NOTE_DURATION := 0.42
const JUKEBOX_BASS_FREQ := 82.41

var _playback: AudioStreamGeneratorPlayback
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _murmur_state := 0.0
var _hiss_state := 0.0
var _crackle_env := 0.0
var _note_index := 0
var _note_t := 0.0


func _ready() -> void:
	_rng.randomize()
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = mix_rate
	generator.buffer_length = buffer_length

	var parent := get_parent()
	if parent is AudioStreamPlayer:
		var player := parent as AudioStreamPlayer
		player.stream = generator
		player.play()
		_playback = player.get_stream_playback() as AudioStreamGeneratorPlayback
	elif parent is AudioStreamPlayer3D:
		var player3d := parent as AudioStreamPlayer3D
		player3d.stream = generator
		player3d.play()
		_playback = player3d.get_stream_playback() as AudioStreamGeneratorPlayback
	else:
		push_warning("ProceduralAudio must be a child of an AudioStreamPlayer or AudioStreamPlayer3D")
		return

	set_process(true)


## Exposed for QA probes: AudioStreamGeneratorPlayback.get_skips() counts
## buffer underruns, the objective "was there an audible dropout" check.
func get_playback() -> AudioStreamGeneratorPlayback:
	return _playback


func _process(_delta: float) -> void:
	if _playback == null:
		return
	var to_fill := _playback.get_frames_available()
	if to_fill <= 0:
		return

	var buffer := PackedVector2Array()
	buffer.resize(to_fill)
	var dt := 1.0 / mix_rate
	for i in to_fill:
		var sample := 0.0
		match profile:
			Profile.ROOM_TONE:
				sample = _room_tone_sample()
			Profile.JUKEBOX:
				sample = _jukebox_sample(dt)
			Profile.OVEN:
				sample = _oven_sample()
		buffer[i] = Vector2(sample, sample)
		_t += dt
	_playback.push_buffer(buffer)


## Low hum (two quiet sine partials with a slow amplitude sway) plus a
## brown-noise crowd-murmur layer that breathes at its own slow rate.
func _room_tone_sample() -> float:
	var hum := sin(_t * TAU * 58.0) * 0.6 + sin(_t * TAU * 87.0) * 0.25
	var hum_sway := 0.85 + 0.15 * sin(_t * TAU * 0.11)
	hum *= hum_sway * 0.14 * level

	_murmur_state = lerpf(_murmur_state, _rng.randf_range(-1.0, 1.0), 0.06)
	var murmur_sway := 0.6 + 0.4 * sin(_t * TAU * 0.07 + 1.7)
	var murmur := _murmur_state * murmur_sway * 0.05 * level * murmur_level

	return clampf(hum + murmur, -1.0, 1.0)


## A short arpeggio loop over a steady bass note, soft-clipped for a
## small-speaker jukebox character - reads as "music" from a distance
## without needing any imported melody data.
func _jukebox_sample(dt: float) -> float:
	_note_t += dt
	if _note_t >= JUKEBOX_NOTE_DURATION:
		_note_t -= JUKEBOX_NOTE_DURATION
		_note_index = (_note_index + 1) % JUKEBOX_NOTES.size()
	var note_freq: float = JUKEBOX_NOTES[_note_index]
	var envelope := clampf(_note_t / 0.015, 0.0, 1.0) * exp(-_note_t * 4.0)
	var lead := sin(_t * TAU * note_freq) * 0.5 + sin(_t * TAU * note_freq * 2.0) * 0.15
	var bass := sin(_t * TAU * JUKEBOX_BASS_FREQ) * 0.35
	var mix := lead * envelope * 0.5 + bass * 0.35
	return clampf(tanh(mix * 2.2), -1.0, 1.0) * level


## Steady high-passed hiss, a low hearth rumble, and sparse decaying
## crackle pops triggered at random.
func _oven_sample() -> float:
	var raw := _rng.randf_range(-1.0, 1.0)
	_hiss_state = lerpf(_hiss_state, raw, 0.35)
	var hiss := (raw - _hiss_state) * 0.18

	var rumble := sin(_t * TAU * 42.0) * 0.05

	_crackle_env *= 0.9985
	if _rng.randf() < 0.0015:
		_crackle_env = _rng.randf_range(0.3, 0.7)
	var crackle := _rng.randf_range(-1.0, 1.0) * _crackle_env * 0.4

	return clampf((hiss + rumble + crackle) * level, -1.0, 1.0)
