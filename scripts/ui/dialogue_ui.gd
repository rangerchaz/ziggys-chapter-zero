## Readable dialogue panel: speaker name, one line at a time, advance and
## close. Line text is sourced exclusively from DialogueDB.get_lines() -
## open_for() is the only production entry point and it never accepts a
## literal string, only an npc_id it hands straight to the DB.
##
## Dialogue state is pre_brownout for every NPC right now: GameState never
## flips brownout_fired true until Phase 11 wires the brownout beat, and
## Phase 12 is what authors post_brownout content and the branch that reads
## it. Escape (ui_cancel) always closes rather than quitting or stacking a
## pause menu, per Flow 14.
extends Control

## Emitted once the panel has fully closed (last line advanced, or Escape).
signal closed
## Emitted only when a conversation reaches its last line and is advanced
## past (not when Escape cuts it short) - the signal BrownoutDirector
## counts distinct NPCs against for its "Nth conversation completed"
## trigger.
signal conversation_completed(npc_id: StringName)

const _STATE := &"pre_brownout"

@onready var _speaker_label: Label = %SpeakerLabel
@onready var _line_label: Label = %LineLabel
@onready var _advance_hint: Label = %AdvanceHint

var _lines: Array[String] = []
var _index := 0
var _npc_id: StringName = &""


func _ready() -> void:
	hide()


## Production entry point: looks up npc_id's current-state lines in
## DialogueDB and opens the panel on the first one.
func open_for(npc_id: StringName, display_name: String) -> void:
	_npc_id = npc_id
	var lines: Array[String] = DialogueDB.get_lines(npc_id, _STATE)
	open_with_lines(display_name, lines)


## Renders a pre-fetched line list under `display_name`. Split out from
## open_for() so the advance/close state machine can be exercised directly
## (e.g. by tests) without depending on content file contents.
func open_with_lines(display_name: String, lines: Array[String]) -> void:
	_lines = lines
	_index = 0
	_speaker_label.text = display_name
	if _lines.is_empty():
		push_warning("DialogueUI: opened '%s' with zero lines; closing immediately" % display_name)
		_close()
		return
	_render_current_line()
	show()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		_advance()
	elif event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()


func _advance() -> void:
	_index += 1
	if _index >= _lines.size():
		_finish()
	else:
		_render_current_line()


func _finish() -> void:
	conversation_completed.emit(_npc_id)
	_close()


func _render_current_line() -> void:
	_line_label.text = _lines[_index]
	_advance_hint.text = "[E]  Continue" if _index < _lines.size() - 1 else "[E]  Close"


func _close() -> void:
	hide()
	closed.emit()
