## The ten named human regulars at Ziggy's.
##
## One canonical roster so the room scene and its probes agree on ids and
## display names, the way MeckieDefs anchors the Meckie cast. No dialogue
## strings live here — Phase 9 owns what these people say.
class_name NpcDefs
extends RefCounted

const IDS: Array[StringName] = [
	&"caroline", &"chad", &"oleg", &"ramsey", &"nic",
	&"conner", &"nick", &"jocelyn", &"tonya", &"grant",
]

const DISPLAY_NAMES: Dictionary = {
	&"caroline": "Caroline",
	&"chad": "Chad",
	&"oleg": "Oleg",
	&"ramsey": "Ramsey",
	&"nic": "Nic",
	&"conner": "Conner",
	&"nick": "Nick",
	&"jocelyn": "Jocelyn",
	&"tonya": "Tonya",
	&"grant": "Grant",
}


static func ids() -> Array[StringName]:
	return IDS.duplicate()


static func display_name_of(id: StringName) -> String:
	return DISPLAY_NAMES.get(id, "")
