## Single owner of the Escape key across the whole chapter.
##
## Every screen or overlay that wants Escape to do something specific
## (title, selection, in-room/pause, dialogue, settings...) registers a
## named context here instead of reading ui_cancel/pause itself in its own
## _unhandled_input - this autoload is the ONLY node in the project that
## does that, so a single Escape press is always resolved by exactly one
## thing: whichever context was most recently pushed and hasn't been
## popped yet. That is what makes "closes dialogue, not also opens pause"
## a guarantee rather than a race between two _unhandled_input listeners.
##
## Contexts are keyed by name rather than a strict push/pop stack:
## pushing a name that's already registered replaces it in place instead
## of stacking a duplicate (DialogueUI calls open_with_lines() more than
## once across a single conversation - main lines, then Caroline's
## closing question, then the acknowledgement line - without wanting a
## growing pile of "dialogue" entries). Registered process_mode ALWAYS so
## it keeps receiving input (and can therefore still resume the game)
## while get_tree().paused is true.
extends Node

## name (StringName) -> Callable, in registration order. The last entry
## is the active context; Escape calls its Callable and nothing else.
var _contexts: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if not (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause")):
		return
	get_viewport().set_input_as_handled()
	if _contexts.is_empty():
		return
	var handler: Callable = _contexts[-1]["on_escape"]
	if handler.is_valid():
		handler.call()


## Registers (or replaces) the Escape handler for `name`, making it the
## active context. Safe to call repeatedly with the same name.
func push_context(name: StringName, on_escape: Callable) -> void:
	pop_context(name)
	_contexts.append({"name": name, "on_escape": on_escape})


## Removes `name` from the registry, wherever it sits. A no-op if it
## isn't present, so _exit_tree()/close() cleanup never needs to guard it.
func pop_context(name: StringName) -> void:
	for i in range(_contexts.size() - 1, -1, -1):
		if _contexts[i]["name"] == name:
			_contexts.remove_at(i)


func has_context(name: StringName) -> bool:
	for ctx in _contexts:
		if ctx["name"] == name:
			return true
	return false


## The name of the currently active (topmost) context, or "" if none.
func active_context() -> StringName:
	return _contexts[-1]["name"] if not _contexts.is_empty() else &""


## Test/debug helper: drops every registered context so one probe's
## leftover registrations can never leak into the next.
func clear() -> void:
	_contexts.clear()
