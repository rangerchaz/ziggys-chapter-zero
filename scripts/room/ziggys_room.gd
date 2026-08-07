## Room-level controller: applies the active chapter's cast to the room.
##
## GameState.active_chapter_id is "" for "no chapter wired up" (see
## game_state.gd) - every probe/scene that instantiates ziggys_room.tscn
## directly without going through chapter_select.gd sees this default, so
## this node does nothing and the full ten-NPC roster ships exactly as
## before. Every real chapter select row, including Chapter Zero's own
## (content/chapters/chapter-zero.json, Phase 5), sets a real ChapterDB id
## instead. Only a room entered via chapter_select.gd (a ChapterDB chapter)
## filters: every Npcs child whose npc_id is not in that
## chapter's `cast` is queue_free()'d, not merely hidden, so an absent NPC
## has no presence, no collision and cannot be interacted with (acceptance
## criterion 1). DoorwayBlocker and every other room node sit outside the
## Npcs subtree, so cast changes never touch the seal - see
## spec-chapters.md's "cast changes must not remove it" trap.
##
## Also starts BeatRunner for the active chapter: the shipped scene's
## BeatRunner has chapter_id = "" (see beat_runner_probe.gd), so its own
## _ready() no-ops; this node's _ready() runs after its children's (Godot
## fires child _ready() bottom-up), so calling start() here is always safe.
## start() itself is deferred: a chapter whose leading beats need no
## `after` trigger (e.g. an immediate `end`) fires synchronously the
## instant start() is called, and an `end` beat's change_scene_to_file()
## collides with the scene tree still being mid-construction if that
## happens from inside this very _ready() - Godot raises "Parent node is
## busy adding/removing children". Deferring to the next idle frame (this
## node's own _ready() will already have returned, and add_child(room)
## from whichever caller loaded this scene will already have completed)
## sidesteps that without changing when beats fire from the player's POV.
extends Node3D

@onready var _npcs: Node3D = $Npcs
@onready var _beat_runner: Node = $BeatRunner


func _ready() -> void:
	var chapter_id: String = get_node(^"/root/GameState").active_chapter_id
	if chapter_id == "":
		return
	var chapter_db := get_node(^"/root/ChapterDB")
	if not chapter_db.is_loaded(chapter_id):
		push_warning("ZiggysRoom: active chapter '%s' is not loaded; showing the full cast" % chapter_id)
		return
	_filter_cast(chapter_db.get_chapter(chapter_id).get("cast", []))
	_beat_runner.start.call_deferred(chapter_id)


func _filter_cast(cast: Array) -> void:
	var cast_ids: Array[StringName] = []
	for raw_id in cast:
		cast_ids.append(StringName(raw_id))
	for npc in _npcs.get_children():
		if npc is NpcHuman and not cast_ids.has(npc.npc_id):
			npc.queue_free()
