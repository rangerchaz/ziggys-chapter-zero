## Wires the in-world interaction loop: tracks which NPCs' InteractionArea
## the player Meckie is inside, resolves the nearest one when several
## overlap, and drives the interact prompt and the dialogue UI from that.
##
## Listens to every NpcHuman's InteractionArea directly rather than
## polling distances every frame against the whole "npcs" group, so cost
## stays proportional to how many NPCs are actually in range (almost
## always 0 or 1, never more than a couple given the room's layout).
class_name InteractionManager
extends Node

## Emitted when the nearest talkable NPC changes to a real one.
signal npc_prompt_shown(npc_id: StringName, display_name: String)
## Emitted when no talkable NPC is in range any more.
signal npc_prompt_hidden

@export var interact_prompt_path: NodePath
@export var dialogue_ui_path: NodePath

@onready var _prompt: Control = get_node_or_null(interact_prompt_path)
@onready var _dialogue: Control = get_node_or_null(dialogue_ui_path)

## NpcHuman -> true for every NPC whose InteractionArea currently contains
## the player.
var _in_range: Dictionary = {}
var _nearest: NpcHuman = null
var _player: Node3D = null
var _dialogue_open := false


func _ready() -> void:
	for raw in get_tree().get_nodes_in_group(&"npcs"):
		var npc := raw as NpcHuman
		if npc == null:
			continue
		var area: Area3D = npc.get_node_or_null(^"InteractionArea")
		if area == null:
			continue
		area.body_entered.connect(_on_body_entered.bind(npc))
		area.body_exited.connect(_on_body_exited.bind(npc))

	npc_prompt_shown.connect(func(id: StringName, display_name: String) -> void:
		if _prompt == null:
			return
		var state: Node = get_node(^"/root/GameState")
		if id == &"caroline" and state.closing_time_reached and state.closing_decision == state.NONE:
			_prompt.show_for(display_name, "[E]  Hear Caroline out")
		else:
			_prompt.show_for(display_name))
	npc_prompt_hidden.connect(func() -> void:
		if _prompt != null:
			_prompt.hide_prompt())

	if _dialogue != null:
		_dialogue.closed.connect(_on_dialogue_closed)


func _physics_process(_delta: float) -> void:
	# Two overlapping ranges can swap which is closer as the player walks
	# between them, so keep re-resolving while more than one is in range.
	if _in_range.size() > 1:
		_resolve_nearest()


## Event-driven rather than polled: is_action_just_pressed() in
## _physics_process can see the same "just pressed" frame more than once
## (or miss it) whenever a process frame covers zero or multiple physics
## steps, which is exactly the headless/uncapped-framerate case the test
## suite runs under. _unhandled_input fires exactly once per real event,
## the same mechanism DialogueUI itself uses to advance/close.
func _unhandled_input(event: InputEvent) -> void:
	if not _dialogue_open and _nearest != null and event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		_open_dialogue(_nearest)


func _on_body_entered(body: Node3D, npc: NpcHuman) -> void:
	if not body.is_in_group(&"player"):
		return
	_player = body
	_in_range[npc] = true
	_resolve_nearest()


func _on_body_exited(body: Node3D, npc: NpcHuman) -> void:
	if not body.is_in_group(&"player"):
		return
	_in_range.erase(npc)
	_resolve_nearest()


func _resolve_nearest() -> void:
	var closest: NpcHuman = null
	if _player != null:
		var closest_dist := INF
		for npc: NpcHuman in _in_range:
			var dist := npc.global_position.distance_squared_to(_player.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest = npc
	if closest == _nearest:
		return
	_nearest = closest
	if _dialogue_open:
		return
	if _nearest != null:
		npc_prompt_shown.emit(_nearest.npc_id, _nearest.display_name)
	else:
		npc_prompt_hidden.emit()


func _open_dialogue(npc: NpcHuman) -> void:
	if _dialogue == null:
		return
	_dialogue_open = true
	npc_prompt_hidden.emit()
	_set_player_input_enabled(false)
	_dialogue.open_for(npc.npc_id, npc.display_name)


func _on_dialogue_closed() -> void:
	_dialogue_open = false
	_set_player_input_enabled(true)
	if _nearest != null:
		npc_prompt_shown.emit(_nearest.npc_id, _nearest.display_name)


func _set_player_input_enabled(enabled: bool) -> void:
	if _player != null and _player.has_method(&"set_input_enabled"):
		_player.set_input_enabled(enabled)
