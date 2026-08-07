## Chapter select: the front door to any chapter, offered or locked.
##
## Sits between the title screen's Start button and meckie select (title ->
## chapter select -> meckie select -> room, extending the existing title ->
## meckie-select -> room pattern with one more stop). Lists a hardcoded row
## for the still-hardcoded Chapter Zero flow plus one row per ChapterDB.ids()
## chapter, sorted for a stable order. A chapter with no `requires` (or
## fully satisfied ones) is a normal enabled button; one with an unmet
## `requires` stays VISIBLE but disabled, with a reason label under its
## summary - see spec-chapters.md's "unmet ones are visible but greyed with
## the reason, never hidden." Picking an enabled row calls
## GameState.reset_chapter(id) (only that chapter's own progress, per the
## same spec's "entering a chapter resets that chapter's state, never
## another's") and moves on to meckie select. Escape returns to the title,
## via the "chapter_select" context this screen holds on UiStateMachine -
## the single project-wide Escape owner - rather than reading ui_cancel
## directly.
extends Control

## Fired when a row is activated, after GameState.reset_chapter() has run.
signal chapter_chosen(id: String)
## Fired when the player backs out toward the title screen.
signal back_requested

const TITLE_SCENE := "res://scenes/ui/title_screen.tscn"
const MECKIE_SCENE := "res://scenes/ui/meckie_select.tscn"

## Sentinel row id for the still-hardcoded Chapter Zero flow - never a real
## ChapterDB id, matching GameState.active_chapter_id's own "" sentinel.
const CHAPTER_ZERO_ID := ""

const AMBER := Color(1, 0.705882, 0.329412, 1)
const BODY_TEXT := Color(0.847059, 0.796078, 0.721569, 1)
const MUTED := Color(0.658824, 0.603922, 0.537255, 1)
const PINK := Color(1, 0.435294, 0.658824, 1)
const PLATE_BG := Color(0.141176, 0.109804, 0.094118, 1)

## Probes flip this off so choosing a chapter or backing out only fires the
## signal instead of tearing down the probe scene with a change_scene call.
@export var change_scenes := true

@onready var _list: VBoxContainer = %List

## chapter id ("" for Chapter Zero) -> its row Button, for tests and for
## focusing the first enabled row.
var _rows: Dictionary = {}
var _leaving := false


func _ready() -> void:
	_populate()
	UiStateMachine.push_context(&"chapter_select", _go_back)


func _exit_tree() -> void:
	UiStateMachine.pop_context(&"chapter_select")


## The row Button for `chapter_id` ("" for the Chapter Zero row), or null.
func row_button(chapter_id: String) -> Button:
	return _rows.get(chapter_id, null)


func _populate() -> void:
	_add_row(CHAPTER_ZERO_ID, "Chapter Zero", "Ziggy's, the first night. One room, one evening, one decision.", true, "")

	var chapter_db := get_node(^"/root/ChapterDB")
	var ids := chapter_db.ids()
	ids.sort()
	for id in ids:
		var data: Dictionary = chapter_db.get_chapter(id)
		var reason := ""
		var unlocked := true
		for raw_req in data.get("requires", []):
			var req: Dictionary = raw_req
			if not _requirement_met(req):
				unlocked = false
				reason = _reason_for(req)
				break
		_add_row(id, String(data.get("title", id)), String(data.get("summary", "")), unlocked, reason)

	var first_enabled: Button = null
	for id in _rows:
		var button: Button = _rows[id]
		if not button.disabled:
			first_enabled = button
			break
	if first_enabled != null:
		first_enabled.grab_focus()


func _requirement_met(req: Dictionary) -> bool:
	var save_mgr := get_node(^"/root/SaveManager")
	var flag := String(req.get("flag", ""))
	var equals: Variant = req.get("equals")
	return save_mgr.current_flag_value(flag) == String(equals)


## Derives a player-facing "needs: ..." reason from an unmet requirement.
## The closing-decision flag gets the hand-authored phrase spec-chapters.md
## itself uses as an example ("needs: you organised, last time"); any other
## flag falls back to a generic but still specific readout naming the flag
## and the value it needs.
func _reason_for(req: Dictionary) -> String:
	var flag := String(req.get("flag", ""))
	var equals: Variant = req.get("equals")
	var save_mgr := get_node(^"/root/SaveManager")
	if flag == save_mgr.KEY_CLOSING_DECISION:
		var decision := String(equals)
		if save_mgr.CLOSING_DECISION_REASONS.has(decision):
			return "needs: %s" % save_mgr.CLOSING_DECISION_REASONS[decision]
	return "needs: %s to be %s" % [flag, str(equals)]


func _add_row(id: String, title: String, summary: String, unlocked: bool, reason: String) -> void:
	var button := Button.new()
	button.name = "Row_%s" % (id if id != CHAPTER_ZERO_ID else "chapter_zero")
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL if unlocked else Control.FOCUS_NONE
	button.disabled = not unlocked
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_stylebox_override(&"normal", _row_style(0.0, unlocked))
	button.add_theme_stylebox_override(&"hover", _row_style(0.08, unlocked))
	button.add_theme_stylebox_override(&"focus", _row_style(0.05, unlocked))
	button.add_theme_stylebox_override(&"pressed", _row_style(0.14, unlocked))
	button.add_theme_stylebox_override(&"disabled", _row_style(0.0, unlocked))

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 3)
	button.add_child(box)

	var title_label := Label.new()
	title_label.text = title
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.add_theme_font_size_override(&"font_size", 26)
	title_label.add_theme_color_override(&"font_color", AMBER if unlocked else MUTED)
	box.add_child(title_label)

	var summary_label := Label.new()
	summary_label.text = summary
	summary_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	summary_label.add_theme_font_size_override(&"font_size", 15)
	summary_label.add_theme_color_override(&"font_color", BODY_TEXT if unlocked else MUTED)
	box.add_child(summary_label)

	if not unlocked:
		var reason_label := Label.new()
		reason_label.name = "ReasonLabel"
		reason_label.text = reason
		reason_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		reason_label.add_theme_font_size_override(&"font_size", 14)
		reason_label.add_theme_color_override(&"font_color", PINK)
		box.add_child(reason_label)

	button.pressed.connect(_on_row_pressed.bind(id))
	_list.add_child(button)
	_rows[id] = button


func _row_style(tint: float, unlocked: bool) -> StyleBoxFlat:
	var accent := AMBER if unlocked else MUTED
	var style := StyleBoxFlat.new()
	style.bg_color = PLATE_BG.lerp(accent, tint)
	style.border_color = Color(accent, 0.7 if unlocked else 0.4)
	style.set_border_width_all(1)
	style.border_width_left = 4
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	style.set_corner_radius_all(9)
	return style


func _on_row_pressed(id: String) -> void:
	if _leaving or _rows.get(id, null) == null or (_rows[id] as Button).disabled:
		return
	get_node(^"/root/GameState").reset_chapter(id)
	chapter_chosen.emit(id)
	if not change_scenes:
		return
	_leaving = true
	var err := get_tree().change_scene_to_file(MECKIE_SCENE)
	if err != OK:
		_leaving = false
		push_error("Chapter select could not load %s (error %d)" % [MECKIE_SCENE, err])


func _go_back() -> void:
	if _leaving:
		return
	back_requested.emit()
	if not change_scenes:
		return
	_leaving = true
	var err := get_tree().change_scene_to_file(TITLE_SCENE)
	if err != OK:
		_leaving = false
		push_error("Chapter select could not load %s (error %d)" % [TITLE_SCENE, err])
