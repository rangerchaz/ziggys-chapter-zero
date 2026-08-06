## Settings screen: picture and sound.
##
## Every control writes straight through the SettingsManager autoload,
## which applies the change (window or audio bus) and persists it to
## user://settings.cfg in the same call; nothing here is cosmetic.
##
## Phase 15 reuses this exact scene from the pause menu as well as the
## title screen (deliverable: "shared scene, returns to pause rather than
## to title when opened from there"). `return_target` says which: &"title"
## (default, title screen's Settings button) swaps the whole active scene
## via change_scene_to_file, same as always; &"pause" (pause menu's
## Settings button) leaves the room scene alone and just emits
## back_requested so the pause menu can hide this instance and show
## itself again. Either way, Back and Escape go through the exact same
## _go_back() - Escape itself is read by UiStateMachine (the single
## project-wide Escape owner), which this screen holds a "settings"
## context on for as long as it's on screen, not by a local
## _unhandled_input or a Button shortcut (which would race it).
extends Control

## Emitted whenever this screen wants to close, regardless of
## return_target - lets a pause-menu host resume its own UI without
## caring how the screen was reached.
signal back_requested

## Who opened this screen: &"title" swaps the scene back to the title
## screen on close; &"pause" leaves scene-swapping to the caller and only
## emits back_requested.
@export var return_target: StringName = &"title"

const TITLE_SCENE := "res://scenes/ui/title_screen.tscn"
const ENTRANCE_DURATION := 0.5

@onready var _panel: VBoxContainer = %Panel
@onready var _resolution_option: OptionButton = %ResolutionOption
@onready var _fullscreen_toggle: Button = %FullscreenToggle
@onready var _back_button: Button = %BackButton
@onready var _footer: Label = %Footer
@onready var _sliders: Dictionary = {
	&"Master": %MasterSlider,
	&"Music": %MusicSlider,
	&"SFX": %SfxSlider,
	&"Ambient": %AmbientSlider,
}
@onready var _value_labels: Dictionary = {
	&"Master": %MasterValue,
	&"Music": %MusicValue,
	&"SFX": %SfxValue,
	&"Ambient": %AmbientValue,
}

var _leaving := false


func _ready() -> void:
	_populate_resolutions()
	_fullscreen_toggle.set_pressed_no_signal(SettingsManager.fullscreen)
	_update_fullscreen_text()

	for bus: StringName in _sliders:
		var slider: HSlider = _sliders[bus]
		slider.set_value_no_signal(SettingsManager.get_volume(bus))
		_update_value_label(bus)
		slider.value_changed.connect(_on_volume_changed.bind(bus))

	_resolution_option.item_selected.connect(_on_resolution_selected)
	_fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)
	_back_button.pressed.connect(_go_back)

	if return_target == &"pause":
		_back_button.text = "Back to pause"
		_footer.text = "Esc returns to the pause menu. Changes apply and save immediately."

	_resolution_option.grab_focus()
	_play_entrance()
	UiStateMachine.push_context(&"settings", _go_back)


func _exit_tree() -> void:
	UiStateMachine.pop_context(&"settings")


## Same short slide-and-fade the title uses; the room keeps its rhythm.
func _play_entrance() -> void:
	modulate.a = 0.0
	var panel_rest_x := _panel.position.x
	_panel.position.x = panel_rest_x - 28.0

	var tween := create_tween().set_parallel()
	tween.tween_property(self, "modulate:a", 1.0, ENTRANCE_DURATION) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_panel, "position:x", panel_rest_x, ENTRANCE_DURATION) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func _populate_resolutions() -> void:
	_resolution_option.clear()
	for size in SettingsManager.RESOLUTIONS:
		_resolution_option.add_item("%d x %d" % [size.x, size.y])
	var index := SettingsManager.RESOLUTIONS.find(SettingsManager.resolution)
	_resolution_option.select(maxi(index, 0))


func _on_resolution_selected(index: int) -> void:
	SettingsManager.set_resolution(SettingsManager.RESOLUTIONS[index])


func _on_fullscreen_toggled(enabled: bool) -> void:
	SettingsManager.set_fullscreen(enabled)
	_update_fullscreen_text()


func _on_volume_changed(value: float, bus: StringName) -> void:
	SettingsManager.set_volume(bus, value)
	_update_value_label(bus)


func _update_value_label(bus: StringName) -> void:
	var slider: HSlider = _sliders[bus]
	var label: Label = _value_labels[bus]
	label.text = "%d%%" % roundi(slider.value * 100.0)


func _update_fullscreen_text() -> void:
	_fullscreen_toggle.text = "Fullscreen" if _fullscreen_toggle.button_pressed else "Windowed"


func _go_back() -> void:
	if _leaving:
		return
	_leaving = true
	back_requested.emit()
	if return_target == &"pause":
		return
	var err := get_tree().change_scene_to_file(TITLE_SCENE)
	if err != OK:
		_leaving = false
		push_error("Settings screen could not load %s (error %d)" % [TITLE_SCENE, err])
