## Readable dialogue panel: speaker name, one line at a time, advance and
## close. Line text is sourced exclusively from DialogueDB.get_lines() -
## open_for() is the only production entry point and it never accepts a
## literal string, only an npc_id it hands straight to the DB.
##
## Dialogue state is resolved fresh on every open_for() call from
## GameState.brownout_fired: pre_brownout before the beat, post_brownout
## from the instant it fires (BrownoutDirector, Phase 11) onward, for every
## NPC, with no per-NPC memory beyond that one shared flag. Escape always
## closes rather than quitting or stacking a pause menu, per Flow 14 - but
## as of Phase 15 that's no longer read directly here: while the panel is
## visible it holds the "dialogue" context on UiStateMachine (the single
## project-wide Escape owner), so Escape can never both close the dialogue
## and open the pause menu on the same press.
##
## Phase 13 adds a second mode on top of the line-at-a-time flow: once
## GameState.closing_time_reached and Caroline hasn't been answered yet,
## open_for(&"caroline", ...) shows her closing question (from
## DialogueDB.get_lines(closing)) and, once that's advanced past, switches
## into CHOICE mode - four buttons built from DialogueDB.get_closing_choices(),
## selectable by mouse click or by keyboard (arrow keys move focus, the
## default Godot Button activation keys press it). Selecting one sets
## GameState.closing_decision and shows the acknowledgement line before
## closing normally. Escape in CHOICE mode closes without selecting -
## closing_decision stays NONE, so the next open_for() re-shows all four
## options, exactly as if the prompt had never been opened.
extends Control

enum Mode { LINES, CHOICE }
enum FollowUp { CLOSE, SHOW_CHOICES }

## Vertical anchor top used outside of CHOICE mode; CHOICE mode temporarily
## grows the panel to fit four answer buttons, then restores this.
const DEFAULT_ANCHOR_TOP := 0.66
const CHOICE_ANCHOR_TOP := 0.42

## Emitted once the panel has fully closed (last line advanced, or Escape).
signal closed
## Emitted only when a conversation reaches its last line and is advanced
## past (not when Escape cuts it short) - the signal BrownoutDirector
## counts distinct NPCs against for its "Nth conversation completed"
## trigger.
signal conversation_completed(npc_id: StringName)

@onready var _frame: Control = %Frame
@onready var _speaker_label: Label = %SpeakerLabel
@onready var _line_label: Label = %LineLabel
@onready var _advance_hint: Label = %AdvanceHint
@onready var _choices_container: VBoxContainer = %ChoicesContainer

var _lines: Array[String] = []
var _index := 0
var _npc_id: StringName = &""
var _mode: Mode = Mode.LINES
var _after_lines: FollowUp = FollowUp.CLOSE
var _choice_ids: Array[StringName] = []


func _ready() -> void:
	hide()
	for i in _choices_container.get_child_count():
		var button: Button = _choices_container.get_child(i)
		button.pressed.connect(_on_choice_pressed.bind(i))


## Production entry point: looks up npc_id's current-state lines in
## DialogueDB and opens the panel on the first one. State is re-resolved
## from GameState.brownout_fired on every call, so the very next open_for()
## after the beat fires serves that NPC's post_brownout line with no other
## trigger needed. Routes to the closing decision prompt instead when
## npc_id is Caroline, closing time has been reached, and no decision has
## been recorded yet.
func open_for(npc_id: StringName, display_name: String) -> void:
	_npc_id = npc_id
	if npc_id == &"caroline" and GameState.closing_time_reached and GameState.closing_decision == GameState.NONE:
		_open_closing_prompt(display_name)
		return
	var state: StringName = DialogueDB.STATE_POST_BROWNOUT if GameState.brownout_fired else DialogueDB.STATE_PRE_BROWNOUT
	var lines: Array[String] = DialogueDB.get_lines(npc_id, state)
	open_with_lines(display_name, lines)


## Renders a pre-fetched line list under `display_name`. Split out from
## open_for() so the advance/close state machine can be exercised directly
## (e.g. by tests) without depending on content file contents.
func open_with_lines(display_name: String, lines: Array[String]) -> void:
	_lines = lines
	_index = 0
	_mode = Mode.LINES
	_after_lines = FollowUp.CLOSE
	_frame.anchor_top = DEFAULT_ANCHOR_TOP
	_choices_container.hide()
	_speaker_label.text = display_name
	if _lines.is_empty():
		push_warning("DialogueUI: opened '%s' with zero lines; closing immediately" % display_name)
		_close()
		return
	_render_current_line()
	show()
	UiStateMachine.push_context(&"dialogue", _close)


## Opens Caroline's closing question, then flags that finishing it should
## open the choice prompt rather than close the panel.
func _open_closing_prompt(display_name: String) -> void:
	var lines: Array[String] = DialogueDB.get_lines(_npc_id, DialogueDB.STATE_CLOSING)
	open_with_lines(display_name, lines)
	if not lines.is_empty():
		_after_lines = FollowUp.SHOW_CHOICES


## Escape is handled centrally by UiStateMachine (the "dialogue" context
## pushed in open_with_lines()) so it works identically in CHOICE mode
## (dismisses the closing decision without selecting) and LINES mode -
## the only thing left for this panel to read directly is the advance key,
## which only ever applies in LINES mode; CHOICE mode's four options are
## selected through the buttons themselves (mouse click, or ui_accept on
## the focused one).
func _unhandled_input(event: InputEvent) -> void:
	if not visible or _mode != Mode.LINES:
		return
	if event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		_advance()


func _advance() -> void:
	_index += 1
	if _index >= _lines.size():
		_finish()
	else:
		_render_current_line()


func _finish() -> void:
	if _after_lines == FollowUp.SHOW_CHOICES:
		_enter_choice_mode()
		return
	conversation_completed.emit(_npc_id)
	_close()


## Builds the four-option decision prompt from DialogueDB.get_closing_choices().
## Never soft-locks: if the content layer somehow doesn't carry four
## options, this warns and closes rather than showing a broken/short list.
func _enter_choice_mode() -> void:
	var choices: Array[Dictionary] = DialogueDB.get_closing_choices(_npc_id)
	if choices.size() != _choices_container.get_child_count():
		push_warning("DialogueUI: '%s' closing choices incomplete (%d), closing without a decision" % [_npc_id, choices.size()])
		conversation_completed.emit(_npc_id)
		_close()
		return
	_choice_ids.clear()
	for i in choices.size():
		var choice: Dictionary = choices[i]
		var button: Button = _choices_container.get_child(i)
		button.text = "%d.  %s" % [i + 1, String(choice["text"])]
		_choice_ids.append(choice["id"])
	_mode = Mode.CHOICE
	_advance_hint.text = "Choose one"
	_frame.anchor_top = CHOICE_ANCHOR_TOP
	_choices_container.show()
	_choices_container.get_child(0).grab_focus()


## Records the pick, then shows the acknowledgement line (if the content
## layer has one) before closing normally.
func _on_choice_pressed(index: int) -> void:
	if _mode != Mode.CHOICE:
		return
	var decision_id: StringName = _choice_ids[index]
	_choices_container.hide()
	_frame.anchor_top = DEFAULT_ANCHOR_TOP
	_mode = Mode.LINES
	GameState.closing_decision = decision_id
	var ack_lines: Array[String] = DialogueDB.get_closing_acknowledgement(_npc_id)
	if ack_lines.is_empty():
		conversation_completed.emit(_npc_id)
		_close()
		return
	open_with_lines(_speaker_label.text, ack_lines)


func _render_current_line() -> void:
	_line_label.text = _lines[_index]
	_advance_hint.text = "[E]  Continue" if _index < _lines.size() - 1 else "[E]  Close"


func _close() -> void:
	_choices_container.hide()
	_frame.anchor_top = DEFAULT_ANCHOR_TOP
	_mode = Mode.LINES
	hide()
	UiStateMachine.pop_context(&"dialogue")
	closed.emit()
