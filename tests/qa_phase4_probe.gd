## Phase 4 QA-only capture (not a deliverable test - just screenshots for the
## visual review). Needs the GPU window, so run WITHOUT --headless:
##
##     godot --path . res://tests/qa_phase4_probe.tscn
##
## Shoots the title screen (Start button, the new front door into chapter
## select), the chapter select screen at desktop and mobile window sizes
## (Chapter Zero plus every loaded ChapterDB fixture, including the
## deliberately-locked fixture-requires-locked row with its "needs: ..."
## reason), then the room twice with an identical wide overview camera:
## once with GameState.active_chapter_id == "" (Chapter Zero, full ten-NPC
## roster - the phase's regression check) and once with
## fixture-cast-caroline-chad active (cast = [caroline, chad], so eight of
## the ten regulars must be queue_free()'d). Saves to
## tests/artifacts/qa/phase4/. Exits 0 once everything is written.
extends Node

const TitleScene := preload("res://scenes/ui/title_screen.tscn")
const SelectScene := preload("res://scenes/ui/chapter_select.tscn")
const RoomScene := preload("res://scenes/room/ziggys_room.tscn")
const OUT_DIR := "res://tests/artifacts/qa/phase4"

const DESKTOP_SIZE := Vector2i(1280, 800)
const MOBILE_SIZE := Vector2i(375, 667)

## Same wide overview camera qa_npc_probe.gd (phase 7) used, reused as-is
## so the full-cast and filtered-cast shots are a direct apples-to-apples
## comparison from an identical vantage point.
const OVERVIEW_POS := Vector3(5.6, 3.3, 5.0)
const OVERVIEW_LOOK_AT := Vector3(-1, 1.1, -1.5)

const FILTERED_CHAPTER_ID := "fixture-cast-caroline-chad"

var _frames := 0
var _select: Control
var _room: Node3D
var _cam: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_set_window_size(DESKTOP_SIZE)
	add_child(TitleScene.instantiate())


func _set_window_size(size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	var screen := DisplayServer.window_get_current_screen()
	var origin := DisplayServer.screen_get_position(screen)
	var screen_size := DisplayServer.screen_get_size(screen)
	DisplayServer.window_set_position(origin + (screen_size - size) / 2)


func _process(_delta: float) -> void:
	_frames += 1
	match _frames:
		# Title screen fades in over ENTRANCE_DURATION (0.7s = 42 frames at
		# 60fps); wait past that so the shot isn't mid-fade and washed out.
		50:
			_shot("title_desktop.png")
			_set_window_size(MOBILE_SIZE)
		60:
			_shot("title_mobile.png")
			_set_window_size(DESKTOP_SIZE)
			get_child(0).queue_free()
			_select = SelectScene.instantiate()
			_select.change_scenes = false
			add_child(_select)
		70:
			_shot("chapter_select_desktop.png")
			_set_window_size(MOBILE_SIZE)
		80:
			_shot("chapter_select_mobile.png")
			_set_window_size(DESKTOP_SIZE)
			_select.queue_free()
			# Chapter Zero: active_chapter_id == "", the still-hardcoded
			# flow's sentinel - the room must show its full ten-NPC roster.
			get_node(^"/root/GameState").reset_chapter("")
			_room = RoomScene.instantiate()
			_room.get_node(^"PlayerSpawner").auto_spawn = false
			add_child(_room)
			_cam = Camera3D.new()
			_cam.fov = 60.0
			add_child(_cam)
			_cam.current = true
			_cam.global_position = OVERVIEW_POS
			_cam.look_at(OVERVIEW_LOOK_AT, Vector3.UP)
		# CSG build + shader compile need a beat to settle before the shot
		# reads clean (same margin qa_npc_probe.gd used).
		100:
			_shot("room_full_cast_chapter_zero.png")
			_room.queue_free()
			_cam.queue_free()
			get_node(^"/root/GameState").reset_chapter(FILTERED_CHAPTER_ID)
			_room = RoomScene.instantiate()
			_room.get_node(^"PlayerSpawner").auto_spawn = false
			add_child(_room)
			_cam = Camera3D.new()
			_cam.fov = 60.0
			add_child(_cam)
			_cam.current = true
			_cam.global_position = OVERVIEW_POS
			_cam.look_at(OVERVIEW_LOOK_AT, Vector3.UP)
		150:
			var present: Array[StringName] = []
			for npc in _room.get_node(^"Npcs").get_children():
				if npc is NpcHuman:
					present.append(npc.npc_id)
			print("QA PHASE 4 PROBE: filtered room NPCs present -> %s" % [present])
			_shot("room_filtered_cast_two_npcs.png")
			print("QA PHASE 4 PROBE DONE")
			get_tree().quit(0)


func _shot(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(OUT_DIR + "/" + file_name)
	if err != OK:
		printerr("could not save %s (error %d)" % [file_name, err])
	else:
		print("saved " + file_name)
