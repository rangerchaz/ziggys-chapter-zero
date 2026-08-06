## Title screen: the front door of the chapter.
##
## Start loads the chapter entry scene, Quit exits cleanly. The Settings
## button exists in the scene but stays hidden and disabled until Sprint 2
## wires the settings menu; showing a dead button is worse than showing none.
extends Control

const CHAPTER_ENTRY_SCENE := "res://scenes/room/ziggys_room.tscn"
const ENTRANCE_DURATION := 0.7

@onready var _menu: VBoxContainer = %Menu
@onready var _start_button: Button = %StartButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	_settings_button.visible = false
	_settings_button.disabled = true

	_start_button.pressed.connect(_on_start_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)

	_start_button.grab_focus()
	_play_entrance()


## One short slide-and-fade as the room opens; nothing loops or lingers.
func _play_entrance() -> void:
	modulate.a = 0.0
	var menu_rest_x := _menu.position.x
	_menu.position.x = menu_rest_x - 28.0

	var tween := create_tween().set_parallel()
	tween.tween_property(self, "modulate:a", 1.0, ENTRANCE_DURATION) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_menu, "position:x", menu_rest_x, ENTRANCE_DURATION) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func _on_start_pressed() -> void:
	var err := get_tree().change_scene_to_file(CHAPTER_ENTRY_SCENE)
	if err != OK:
		push_error("Title screen could not load %s (error %d)" % [CHAPTER_ENTRY_SCENE, err])


func _on_quit_pressed() -> void:
	get_tree().quit()
