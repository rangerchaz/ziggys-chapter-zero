## In-room pause menu: Resume, Settings, Quit.
##
## Lives as a CanvasLayer inside ziggys_room.tscn with process_mode ALWAYS
## (deliverable requirement) so its own buttons and input keep working
## while get_tree().paused is true - everything else in the room
## (player, idle Meckies, NPCs, the brownout beat's tweens) inherits the
## default PAUSABLE behavior and simply freezes, which is what "the game
## pauses" means here: no special-casing was needed anywhere else, since
## Tween.TWEEN_PAUSE_BOUND (the default) freezes any tween owned by a
## paused node exactly where it is and resumes it cleanly, so pausing
## mid-brownout never corrupts the light fade or the audio duck.
##
## Doubles as the room's Escape entry point: _ready() registers a "room"
## context on UiStateMachine (the single project-wide Escape owner) whose
## handler is open() - so as long as this node exists in the tree,
## Escape opens the pause menu whenever nothing higher-priority (dialogue,
## the menu itself, settings opened from it) is already claiming Escape.
## While open, it holds a "pause" context whose handler is resume().
extends CanvasLayer

const SETTINGS_SCENE := "res://scenes/ui/settings_screen.tscn"

@onready var _menu_root: Control = %MenuRoot
@onready var _resume_button: Button = %ResumeButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton

var _settings_instance: Control = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	_resume_button.pressed.connect(resume)
	_settings_button.pressed.connect(_open_settings)
	_quit_button.pressed.connect(_on_quit_pressed)
	UiStateMachine.push_context(&"room", open)


func _exit_tree() -> void:
	UiStateMachine.pop_context(&"pause")
	UiStateMachine.pop_context(&"room")


## Opened by UiStateMachine when Escape is pressed in-room with nothing
## else claiming it (also reachable directly, e.g. a future pause button).
func open() -> void:
	if visible:
		return
	get_tree().paused = true
	_menu_root.show()
	show()
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_resume_button.grab_focus()
	UiStateMachine.push_context(&"pause", resume)


func resume() -> void:
	if not visible:
		return
	if _settings_instance != null:
		_settings_instance.queue_free()
		_settings_instance = null
	UiStateMachine.pop_context(&"pause")
	hide()
	get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## Instances the same settings_screen.tscn the title screen uses, with
## return_target set to &"pause" so its Back/Escape returns here instead
## of swapping the whole (still-paused, still-live) room scene out for
## the title screen.
func _open_settings() -> void:
	_menu_root.hide()
	var settings: Control = load(SETTINGS_SCENE).instantiate()
	settings.return_target = &"pause"
	settings.back_requested.connect(_on_settings_back.bind(settings))
	add_child(settings)
	_settings_instance = settings


func _on_settings_back(settings: Control) -> void:
	if _settings_instance == settings:
		_settings_instance = null
	settings.queue_free()
	_menu_root.show()
	_settings_button.grab_focus()


## Deliverable: quit from the pause menu saves current settings first,
## then exits the process cleanly. SettingsManager already persists every
## change as it happens, so this is a documented safety net rather than a
## fix for a real pending-write case.
func _on_quit_pressed() -> void:
	SettingsManager.save_now()
	get_tree().quit()
