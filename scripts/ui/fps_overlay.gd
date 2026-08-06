## Phase 16 performance overlay for windowed FPS/frame-time measurement
## against the 60fps@1080p acceptance criterion. Hidden by default, toggled
## by the debug_fps_overlay key (F3) so it never appears in ordinary
## playthrough screenshots. Reads Engine.get_frames_per_second() directly
## (the engine's own rolling average) rather than hand-averaging deltas.
class_name FpsOverlay
extends Control

@onready var _label: Label = %FpsLabel


func _ready() -> void:
	visible = false
	set_process(visible)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_fps_overlay"):
		visible = not visible
		set_process(visible)


func _process(_delta: float) -> void:
	var fps := Engine.get_frames_per_second()
	var frame_ms := (1000.0 / fps) if fps > 0.0 else 0.0
	_label.text = "%d fps  %.1f ms" % [roundi(fps), frame_ms]
