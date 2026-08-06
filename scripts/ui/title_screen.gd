## Title screen: the front door of the chapter.
##
## Start opens the Meckie selection screen (Phase 6), Settings opens the
## settings screen (Sprint 2), Quit exits cleanly. Also the readout for
## Phase 14's save system: SaveManager (autoload, runs before this scene)
## has already loaded user://ziggys_chapter_zero_save.json and populated
## GameState by the time _ready() below runs, so a prior run's closing
## decision is visible immediately on relaunch, before Start is even
## pressed - the acceptance bar for "the decision survives quit/relaunch."
##
## Phase 15: Escape holds the "title" context on UiStateMachine (the
## single project-wide Escape owner). The first Escape shows an inline
## quit-confirm plate rather than quitting immediately; while that plate
## is up it holds its own "title_quit_confirm" context on top, so a
## second Escape cancels back to the title instead of stacking or
## quitting outright.
extends Control

const CHAPTER_ENTRY_SCENE := "res://scenes/ui/meckie_select.tscn"
const SETTINGS_SCENE := "res://scenes/ui/settings_screen.tscn"
const ENTRANCE_DURATION := 0.7

@onready var _menu: VBoxContainer = %Menu
@onready var _start_button: Button = %StartButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton
@onready var _prior_decision_label: Label = %PriorDecisionLabel
@onready var _quit_confirm: Control = %QuitConfirm
@onready var _quit_confirm_yes: Button = %QuitConfirmYes
@onready var _quit_confirm_cancel: Button = %QuitConfirmCancel


func _ready() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_quit_confirm_yes.pressed.connect(_on_quit_pressed)
	_quit_confirm_cancel.pressed.connect(_hide_quit_confirm)
	_quit_confirm.hide()

	_start_button.grab_focus()
	_show_prior_decision()
	_play_entrance()
	UiStateMachine.push_context(&"title", _show_quit_confirm)


func _exit_tree() -> void:
	UiStateMachine.pop_context(&"title_quit_confirm")
	UiStateMachine.pop_context(&"title")


func _show_quit_confirm() -> void:
	_quit_confirm.show()
	_quit_confirm_cancel.grab_focus()
	UiStateMachine.push_context(&"title_quit_confirm", _hide_quit_confirm)


func _hide_quit_confirm() -> void:
	_quit_confirm.hide()
	UiStateMachine.pop_context(&"title_quit_confirm")
	_quit_button.grab_focus()


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
	SettingsManager.save_now()
	get_tree().quit()
