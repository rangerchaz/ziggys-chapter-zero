# Save format

Owner: `scripts/autoload/save_manager.gd` (the `SaveManager` autoload). This
document is the human-readable copy of the header comment in that file;
if the two ever disagree, the script is authoritative.

This is **version 1** of the save convention for the Wichita Guild chapter
series. No earlier version has ever existed. It is written by *A Night at
Ziggy's* (this chapter, "Chapter Zero") and is designed to be readable
without ambiguity by a later, separate main campaign project - that's the
reason for the namespaced keys and the enumerated string values below,
rather than anything specific to this chapter's internal representation.

Chapter Zero itself is authored as data (`content/chapters/chapter-zero.json`,
see `spec-chapters.md`), and its `decision` beat writes exactly the
`ziggys_chapter_zero.closing_decision` key below through the same generic
mechanism any other chapter's decision would - see "Generic chapter flags".
The three reserved keys and their values are unchanged from before that
conversion; a save from either side of it loads on the other.

## File location

```
user://ziggys_chapter_zero_save.json
```

Always `user://`, never `res://` - `res://` is the read-only project/export
bundle and cannot be written to at runtime on an exported build. There is
exactly one save file; this chapter has no save slots.

## Write behavior

Every write is atomic: the full JSON document is serialized to
`user://ziggys_chapter_zero_save.json.tmp` first, that temp file is closed,
and only then is it renamed over the real save path
(`DirAccess.rename_absolute`). A crash, power loss, or forced quit
mid-write leaves either the old save intact or the new one fully written -
never a half-written, corrupt file in the real save slot.

A save is written automatically whenever any of the three persisted
GameState fields below changes (Meckie picked, brownout fires, closing
decision made), or whenever a generic chapter-namespaced flag is written
(see "Generic chapter flags" below) - there is no explicit "save game"
action in this chapter.

## Read behavior (boot)

`SaveManager.load_save()` runs once at boot, before the title screen
appears:

- **No file present** - not an error. This is the ordinary fresh-chapter
  case; GameState keeps its just-initialized defaults.
- **File present, valid, `version` matches** - every recognized key is
  applied to GameState.
- **File present but unparsable, missing a `version` field, or `version`
  is anything other than `1`** - reported via `push_error` and
  `SaveManager.last_load_error`, and otherwise ignored. GameState is left
  at defaults rather than partially applied from a save format this build
  doesn't understand. This is the forward-migration hook: a future version
  bump adds a real migration path here instead of a hard reject.

## Document shape

A flat JSON object, not nested:

```json
{
  "version": 1,
  "saved_at": "2026-08-06T18:04:00",
  "ziggys_chapter_zero.closing_decision": "organize",
  "ziggys_chapter_zero.selected_meckie": "droid",
  "ziggys_chapter_zero.brownout_seen": true
}
```

| Field | Type | Notes |
|---|---|---|
| `version` | integer | Must be `1` for this build to accept the file. |
| `saved_at` | string | ISO-8601-ish local timestamp from `Time.get_datetime_string_from_system()`. Informational only; nothing currently reads it back. |
| `ziggys_chapter_zero.closing_decision` | string | One of the four enumerated values below, or `""` if the closing prompt hasn't been answered yet. **Never a bare integer index** - the string id is stable even if this chapter's choice *order* ever changes. |
| `ziggys_chapter_zero.selected_meckie` | string | One of `"droid"`, `"eva"`, `"sid"` (`GameState.MECKIES`), or `""` if no Meckie has been picked yet. |
| `ziggys_chapter_zero.brownout_seen` | boolean | Whether the scripted brownout beat (Phase 11) has fired this save. |

Keys are **flat, dotted strings** - literally `"ziggys_chapter_zero.closing_decision"`
as one JSON key, not a nested `"ziggys_chapter_zero": { "closing_decision": ... }`
object. A consumer only needs to look up that one key by name; it does not
need to know or care about this chapter's internal schema beyond that.

## Generic chapter flags

Beyond the three keys above, a chapter's `decision` beats (see
`spec-chapters.md`) can write arbitrary additional flags through
`GameState.set_flag(key, value)` (`GameState.flags`, a plain string/string
map). `SaveManager` persists every entry there as its own **additional
top-level dotted key**, exactly the same flat shape as the three reserved
keys above - never nested, never collected into a sub-object:

```json
{
  "version": 1,
  "saved_at": "2026-08-06T18:04:00",
  "ziggys_chapter_zero.closing_decision": "organize",
  "ziggys_chapter_zero.selected_meckie": "droid",
  "ziggys_chapter_zero.brownout_seen": true,
  "ziggys.the-morning-after.decision": "stay_open"
}
```

The convention for a flag's key is the same as the three reserved ones:
namespace it under the chapter's own id (e.g. `ziggys.the-morning-after.decision`),
so two chapters' decisions can never collide in the same save file. A
`decision` beat's `writes` field is exactly that key (see `chapter.schema.json`).
Values are always strings, same rule as `closing_decision` above: an
enumerated choice id, never a bare index.

On load, `SaveManager` treats every key in the file other than `version`,
`saved_at`, and the three reserved keys as a generic flag and restores all
of them into `GameState.flags` verbatim. A save written before this
convention existed simply has none of these extra keys, so `GameState.flags`
comes back empty - the three reserved keys load exactly as they always
have, byte-for-byte compatible with a save from before this convention.

## `ziggys_chapter_zero.closing_decision` enumerated values

Sourced from the four choice ids authored in
`content/dialogue/caroline.json` (Phase 13's closing-time decision). This
is the complete enumeration; no other string value is valid:

| Value | Meaning |
|---|---|
| `organize` | "We organize. Actual meetings, actual people, actual pressure on somebody who can fix this." |
| `quiet_watch` | "We keep an eye on each other and figure it out as it comes. No committees." |
| `wait_it_out` | "We wait. Maybe it doesn't happen a fourth time." |
| `not_my_problem` | "Honestly? Not my fight. I just want my lights back." |
| `""` (empty string) | Not decided yet. Not one of the four - a sentinel, same as `GameState.NONE` in this codebase. |

## For a later campaign project

To read this chapter's outcome from another Godot project (or any JSON
reader): open `user://ziggys_chapter_zero_save.json` from the shared user
data directory, confirm `"version" == 1`, then read
`"ziggys_chapter_zero.closing_decision"` directly as one of the five
values above. No other key in this document is meaningful outside this
chapter.
