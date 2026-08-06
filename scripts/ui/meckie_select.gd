## Meckie selection screen: pick who you are tonight.
##
## Sits between Start on the title screen and the room loading. Three
## cards, one per cast member, styled at runtime from MeckieDefs so the
## UI swatches, the character emissives and the cast lights all share one
## source of truth. Choosing writes GameState.selected_meckie and loads
## the room; Escape returns to the title screen, via the "selection"
## context this screen holds on UiStateMachine (the single project-wide
## Escape owner) rather than reading ui_cancel directly.
extends Control

## Fired when a card is activated, after GameState has been updated.
signal meckie_chosen(id: StringName)
## Fired when the player backs out toward the title screen.
signal back_requested

const TITLE_SCENE := "res://scenes/ui/title_screen.tscn"
const ROOM_SCENE := "res://scenes/room/ziggys_room.tscn"
const ENTRANCE_DURATION := 0.5

## The faceplate-panel brown the title and settings screens use for plates.
const CARD_BG := Color(0.141176, 0.109804, 0.094118)

## Probes flip this off so choosing or backing out only fires the signal
## instead of tearing down the probe scene with a change_scene call.
@export var change_scenes := true

@onready var _column: VBoxContainer = %Column
@onready var _buttons: Dictionary = {
	&"droid": %DroidButton,
	&"eva": %EvaButton,
	&"sid": %SidButton,
}

var _leaving := false


func _ready() -> void:
	for id: StringName in _buttons:
		var button: Button = _buttons[id]
		_style_card(button, id)
		button.pressed.connect(_on_option_pressed.bind(id))
	_buttons[&"droid"].grab_focus()
	_play_entrance()
	UiStateMachine.push_context(&"selection", _go_back)


func _exit_tree() -> void:
	UiStateMachine.pop_context(&"selection")


## Same short slide-and-fade the title and settings screens use.
func _play_entrance() -> void:
	modulate.a = 0.0
	var column_rest_x := _column.position.x
	_column.position.x = column_rest_x - 28.0

	var tween := create_tween().set_parallel()
	tween.tween_property(self, "modulate:a", 1.0, ENTRANCE_DURATION) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_column, "position:x", column_rest_x, ENTRANCE_DURATION) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


## Colors one card from its cast member's signature: name label, the two
## faceplate eyes, and every button state's border and tint.
func _style_card(button: Button, id: StringName) -> void:
	var color := MeckieDefs.color_of(id)
	var name_label: Label = button.get_node(^"Card/NameLabel")
	name_label.text = MeckieDefs.display_name_of(id)
	name_label.add_theme_color_override(&"font_color", color)

	var eye := StyleBoxFlat.new()
	eye.bg_color = color
	eye.set_corner_radius_all(7)
	button.get_node(^"Card/Eyes/EyeL").add_theme_stylebox_override(&"panel", eye)
	button.get_node(^"Card/Eyes/EyeR").add_theme_stylebox_override(&"panel", eye)

	button.add_theme_stylebox_override(&"normal", _card_style(color, 0.35, 0.0))
	button.add_theme_stylebox_override(&"hover", _card_style(color, 1.0, 0.05))
	button.add_theme_stylebox_override(&"focus", _card_style(color, 1.0, 0.07))
	button.add_theme_stylebox_override(&"pressed", _card_style(color, 1.0, 0.12))


func _card_style(color: Color, border_alpha: float, tint: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_BG.lerp(color, tint)
	style.border_color = Color(color, border_alpha)
	style.set_border_width_all(2)
	style.border_width_left = 6
	style.set_corner_radius_all(11)
	return style


func _on_option_pressed(id: StringName) -> void:
	if _leaving:
		return
	var state := get_node_or_null(^"/root/GameState")
	if state != null:
		state.selected_meckie = id
	meckie_chosen.emit(id)
	if not change_scenes:
		return
	_leaving = true
	var err := get_tree().change_scene_to_file(ROOM_SCENE)
	if err != OK:
		_leaving = false
		push_error("Meckie select could not load %s (error %d)" % [ROOM_SCENE, err])


func _go_back() -> void:
	if _leaving:
		return
	back_requested.emit()
	if not change_scenes:
		return
	_leaving = true
	var err := get_tree().change_scene_to_file(TITLE_SCENE)
	if err != OK:
		_leaving = false
		push_error("Meckie select could not load %s (error %d)" % [TITLE_SCENE, err])
