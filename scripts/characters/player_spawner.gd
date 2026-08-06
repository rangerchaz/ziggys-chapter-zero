## Spawns the full Meckie cast into the room: the player-controlled robot
## at its marker, and the two unchosen Meckies as idle NPCs at theirs.
##
## Reads GameState.selected_meckie (set by the selection screen) and falls
## back to `default_meckie`. Probes that want a bare room set
## `auto_spawn = false` on this node before adding the room to the tree.
extends Node

const PlayerScene := preload("res://scenes/characters/meckie_player.tscn")
const IdleScene := preload("res://scenes/characters/meckie_idle.tscn")

@export var auto_spawn := true
@export var default_meckie: StringName = &"droid"


func _ready() -> void:
	if not auto_spawn:
		return
	var id := default_meckie
	var state := get_node_or_null(^"/root/GameState")
	if state != null and state.selected_meckie != &"" \
			and MeckieDefs.DEFS.has(state.selected_meckie):
		id = state.selected_meckie
	spawn(id)
	spawn_idles(id)


## Instantiates the player-controlled Meckie at the marker matching `id`
## and returns it. Phase 3 keeps one spawn marker per cast member under
## Markers/MeckieSpawns.
func spawn(id: StringName) -> CharacterBody3D:
	var player: CharacterBody3D = PlayerScene.instantiate()
	player.meckie_id = id
	_place_at_marker(player, id)
	get_parent().add_child.call_deferred(player)
	return player


## The two cast members the player did not pick still work the room:
## instantiate them at their own markers with the idle controller.
func spawn_idles(player_id: StringName) -> Array[CharacterBody3D]:
	var spawned: Array[CharacterBody3D] = []
	for other: StringName in MeckieDefs.ids():
		if other == player_id:
			continue
		var idle: CharacterBody3D = IdleScene.instantiate()
		idle.meckie_id = other
		_place_at_marker(idle, other)
		get_parent().add_child.call_deferred(idle)
		spawned.append(idle)
	return spawned


func _place_at_marker(body: CharacterBody3D, id: StringName) -> void:
	var marker: Marker3D = get_parent().get_node_or_null(
			"Markers/MeckieSpawns/MeckieSpawn" + MeckieDefs.display_name_of(id))
	if marker == null:
		return
	body.position = marker.position
	# Face into the room rather than whatever the marker happens to face.
	var to_center := -marker.position
	body.rotation.y = atan2(-to_center.x, -to_center.z)
