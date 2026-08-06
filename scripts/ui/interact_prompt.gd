## Screen-space "you can talk to someone" prompt.
##
## Pure display: InteractionManager calls show_for()/hide_prompt() as the
## nearest talkable NPC changes, this script does not touch physics,
## groups, or DialogueDB itself.
extends Control

@onready var _label: Label = %PromptLabel


func _ready() -> void:
	hide()


## Shows the prompt naming `display_name` and the interact key.
func show_for(display_name: String) -> void:
	_label.text = "[E]  Talk to %s" % display_name
	show()


func hide_prompt() -> void:
	hide()
