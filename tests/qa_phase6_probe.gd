## Phase 6 QA-only capture (not a deliverable test - just screenshots for the
## visual review). Needs the GPU window, so run WITHOUT --headless:
##
##     godot --path . res://tests/qa_phase6_probe.tscn
##
## Captures the Meckie selection screen at a desktop-ish window size and a
## narrow "mobile" window size (this is a native windowed game, not a
## responsive web app, so "mobile" here means a small window - it exercises
## the canvas_items/keep-aspect stretch mode the project uses), then spawns
## the room with Droid as the player and shoots the two idle Meckies (Eva,
## Sid) twice a few seconds apart to show they are not frozen, and finally
## the title screen reached after Escape to confirm the back path renders.
## Saves to tests/artifacts/qa/phase6/. Exits 0 once everything is written.
extends Node

const SelectScene := preload("res://scenes/ui/meckie_select.tscn")
const RoomScene := preload("res://scenes/room/ziggys_room.tscn")
const TitleScene := preload("res://scenes/ui/title_screen.tscn")
const OUT_DIR := "res://tests/artifacts/qa/phase6"

const DESKTOP_SIZE := Vector2i(1280, 800)
const MOBILE_SIZE := Vector2i(375, 667)

const DROID_MARKER := Vector3(0.5, 0, -4.4)
const EVA_MARKER := Vector3(5.6, 0, 2.6)
const SID_MARKER := Vector3(-4.2, 0, -2.8)

var _frames := 0
var _select: Control
var _room: Node3D
var _wide_cam: Camera3D
var _player: CharacterBody3D
var _eva: CharacterBody3D
var _sid: CharacterBody3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_set_window_size(DESKTOP_SIZE)
	_select = SelectScene.instantiate()
	_select.change_scenes = false
	add_child(_select)


func _set_window_size(size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	var screen := DisplayServer.window_get_current_screen()
	var origin := DisplayServer.screen_get_position(screen)
	var screen_size := DisplayServer.screen_get_size(screen)
	DisplayServer.window_set_position(origin + (screen_size - size) / 2)


func _process(_delta: float) -> void:
	_frames += 1
	match _frames:
		10:
			_shot("meckie_select_desktop.png")
			_set_window_size(MOBILE_SIZE)
		20:
			_shot("meckie_select_mobile.png")
			_set_window_size(DESKTOP_SIZE)
		30:
			# Escape backs out to the title screen.
			var esc := InputEventKey.new()
			esc.keycode = KEY_ESCAPE
			esc.physical_keycode = KEY_ESCAPE
			esc.pressed = true
			Input.parse_input_event(esc)
			var esc_up := InputEventKey.new()
			esc_up.keycode = KEY_ESCAPE
			esc_up.physical_keycode = KEY_ESCAPE
			esc_up.pressed = false
			Input.parse_input_event(esc_up)
		35:
			_select.queue_free()
			add_child(TitleScene.instantiate())
		# Title screen fades in over ENTRANCE_DURATION (0.7s = 42 frames at
		# 60fps); wait past that so the shot isn't mid-fade and washed out.
		85:
			_shot("meckie_select_escape_to_title.png")
			get_child(0).queue_free()
			# Droid as player; Eva and Sid are the idle pair.
			var state: Node = get_node(^"/root/GameState")
			state.selected_meckie = &"droid"
			_room = RoomScene.instantiate()
			add_child(_room)
			_wide_cam = Camera3D.new()
			_wide_cam.fov = 65.0
			add_child(_wide_cam)
		150:
			for child in _room.get_children():
				if child is MeckiePlayerController:
					_player = child
				elif child is MeckieIdleController:
					if child.meckie_id == &"eva":
						_eva = child
					elif child.meckie_id == &"sid":
						_sid = child
			if _player == null or _eva == null or _sid == null:
				printerr("QA PHASE 6 PROBE FAIL: player/idle Eva/Sid not found")
				get_tree().quit(1)
				return
			_wide_cam.global_position = EVA_MARKER + Vector3(-2.2, 2.1, 3.4)
			_wide_cam.look_at((EVA_MARKER + SID_MARKER) * 0.5 + Vector3(0, 0.9, 0), Vector3.UP)
			_wide_cam.current = true
		180:
			_shot("room_overview_wide.png")
			# Pose Droid on the open floor facing his own camera, same spot
			# meckie_render_probe.gd already proved clear of geometry - his
			# actual spawn sits in the tight back-bar corridor, a bad angle
			# for a clean signature-color read.
			var rig: SpringArm3D = _player.get_node(^"CameraRig")
			_player.global_position = Vector3(0.8, 0.05, 1.2)
			_player.velocity = Vector3.ZERO
			_player.rotation.y = PI
			rig.global_position = _player.global_position + Vector3(0, 1.35, 0)
			rig.rotation = Vector3(-0.3, 0, 0)
			rig.get_node(^"Camera3D").make_current()
		200:
			_shot("room_droid_player_close.png")
			_wide_cam.current = true
			_wide_cam.global_position = EVA_MARKER + Vector3(-2.4, 1.6, 1.4)
			_wide_cam.look_at(EVA_MARKER + Vector3(0, 0.9, 0), Vector3.UP)
		220:
			_shot("room_eva_idle_close_t0.png")
			_wide_cam.global_position = SID_MARKER + Vector3(2.4, 1.7, 1.6)
			_wide_cam.look_at(SID_MARKER + Vector3(0, 0.9, 0), Vector3.UP)
		240:
			_shot("room_sid_idle_close_t0.png")
			_wide_cam.global_position = EVA_MARKER + Vector3(-2.4, 1.6, 1.4)
			_wide_cam.look_at(EVA_MARKER + Vector3(0, 0.9, 0), Vector3.UP)
		# ~4.5 simulated seconds later at 60fps, so hover-bob phase and any
		# wander step differ visibly from the first close shots.
		510:
			_shot("room_eva_idle_close_t1.png")
			_wide_cam.global_position = SID_MARKER + Vector3(2.4, 1.7, 1.6)
			_wide_cam.look_at(SID_MARKER + Vector3(0, 0.9, 0), Vector3.UP)
		530:
			_shot("room_sid_idle_close_t1.png")
			print("QA PHASE 6 PROBE DONE")
			get_tree().quit(0)


func _shot(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(OUT_DIR + "/" + file_name)
	if err != OK:
		printerr("could not save %s (error %d)" % [file_name, err])
	else:
		print("saved " + file_name)
