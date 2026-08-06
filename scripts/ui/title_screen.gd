## Title screen: the front door of the chapter.
##
## Start opens the Meckie selection screen (Phase 6), Settings opens the
## settings screen (Sprint 2), Quit exits cleanly. Also the readout for
## Phase 14's save system: SaveManager (autoload, runs before this scene)
## has already loaded user://ziggys_chapter_zero_save.json and populated
## GameState by the time _ready() below runs, so a prior run's closing
## decision is visible immediately on relaunch, before Start is even
## pressed - the acceptance bar for "the decision survives quit/relaunch."
extends Control

const CHAPTER_ENTRY_SCENE := "res://scenes/ui/meckie_select.tscn"
const SETTINGS_SCENE := "res://scenes/ui/settings_screen.tscn"
const ENTRANCE_DURATION := 0.7

@onready var _menu: VBoxContainer = %Menu
@onready var _start_button: Button = %StartButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton
@onready var _prior_decision_label: Label = %PriorDecisionLabel


func _ready() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)

	_start_button.grab_focus()
	_show_prior_decision()
	_play_entrance()


## Shows a one-line summary of last run's recorded closing decision, if
## SaveManager loaded one; hidden entirely on a fresh chapter.
func _show_prior_decision() -> void:
	var state := get_node(^"/root/GameState")
	var save_mgr := get_node(^"/root/SaveManager")
	var decision := String(state.closing_decision)
	if decision == "" or decision not in save_mgr.CLOSING_DECISION_SUMMARIES:
		_prior_decision_label.hide()
		return
	_prior_decision_label.text = "Last time: %s" % save_mgr.CLOSING_DECISION_SUMMARIES[decision]
	_prior_decision_label.show()


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


func _on_settings_pressed() -> void:
	var err := get_tree().change_scene_to_file(SETTINGS_SCENE)
	if err != OK:
		push_error("Title screen could not load %s (error %d)" % [SETTINGS_SCENE, err])


func _on_quit_pressed() -> void:
	get_tree().quit()
