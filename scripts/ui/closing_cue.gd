## Small "last call" banner cue: appears once GameState.closing_time_reached
## fires, telling the player Caroline has something to say to the room -
## the visible signal that the chapter has moved into closing time, apart
## from and in addition to her per-NPC interact prompt (see
## InteractionManager's Caroline special-case). Purely reactive to
## GameState signals; no dialogue or interaction logic of its own. Hides
## again once a decision has landed, since the cue is "go talk to her," not
## a permanent HUD element.
extends Control

@onready var _label: Label = %CueLabel


func _ready() -> void:
	hide()
	var state: Node = get_node(^"/root/GameState")
	state.closing_time_changed.connect(_on_closing_time_changed)
	state.closing_decision_made.connect(_on_decision_made)
	if state.closing_time_reached and state.closing_decision == state.NONE:
		_show_cue()


func _on_closing_time_changed(reached: bool) -> void:
	var state: Node = get_node(^"/root/GameState")
	if reached and state.closing_decision == state.NONE:
		_show_cue()
	else:
		hide()


func _on_decision_made(_decision: StringName) -> void:
	hide()


func _show_cue() -> void:
	_label.text = "Last call. Caroline's asking the room what it's going to do."
	show()
