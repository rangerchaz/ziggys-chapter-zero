## Spawns the playable Meckie into the room at its cast spawn marker.
##
## Reads GameState.selected_meckie (the pick-a-Meckie flow lands in a later
## phase) and falls back to `default_meckie`. Probes that want a bare room
## set `auto_spawn = false` on this node before adding the room to the tree.
extends Node

const PlayerScene := preload("res://scenes/characters/meckie_player.tscn")

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


## Instantiates the player-controlled Meckie at the marker matching `id`
## and returns it. Phase 3 keeps one spawn marker per cast member under
## Markers/MeckieSpawns.
func spawn(id: StringName) -> CharacterBody3D:
	var room := get_parent()
	var player: CharacterBody3D = PlayerScene.instantiate()
	player.meckie_id = id
	var marker: Marker3D = room.get_node_or_null(
			"Markers/MeckieSpawns/MeckieSpawn" + MeckieDefs.display_name_of(id))
	if marker != null:
		player.position = marker.position
		# Face into the room rather than whatever the marker happens to face.
		var to_center := -marker.position
		player.rotation.y = atan2(-to_center.x, -to_center.z)
	room.add_child.call_deferred(player)
	return player
