## Settings screen: picture and sound, reachable from the title screen.
##
## Every control writes straight through the SettingsManager autoload,
## which applies the change (window or audio bus) and persists it to
## user://settings.cfg in the same call; nothing here is cosmetic. Back
## and Escape both return to the title screen (the Back button carries a
## ui_cancel shortcut, with _unhandled_input as a fallback).
extends Control

const TITLE_SCENE := "res://scenes/ui/title_screen.tscn"
const ENTRANCE_DURATION := 0.5

@onready var _panel: VBoxContainer = %Panel
@onready var _resolution_option: OptionButton = %ResolutionOption
@onready var _fullscreen_toggle: Button = %FullscreenToggle
@onready var _back_button: Button = %BackButton
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

	_resolution_option.grab_focus()
	_play_entrance()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_back()


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
	var err := get_tree().change_scene_to_file(TITLE_SCENE)
	if err != OK:
		_leaving = false
		push_error("Settings screen could not load %s (error %d)" % [TITLE_SCENE, err])
