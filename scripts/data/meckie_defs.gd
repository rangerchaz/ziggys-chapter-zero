## The playable Meckie cast and their signature colors.
##
## One place for Phase 6's pick-a-Meckie flow to enumerate the cast, and for
## the Meckie scene to resolve an id into a color. Ids match
## GameState.MECKIES; Sid's warm amber comes from the chapter's UI palette
## so the third Meckie sits on the warm side of the two-temperature look.
class_name MeckieDefs
extends RefCounted

const DEFS: Dictionary = {
	&"droid": {"display_name": "Droid", "color": Color("00d4ff")},
	&"eva": {"display_name": "Eva", "color": Color("ff6fa8")},
	&"sid": {"display_name": "Sid", "color": Color("ffb454")},
}


static func ids() -> Array:
	return DEFS.keys()


static func color_of(id: StringName) -> Color:
	return DEFS[id]["color"]


static func display_name_of(id: StringName) -> String:
	return DEFS[id]["display_name"]
