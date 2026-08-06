# Wichita Guild — Chapter Zero: A Night at Ziggy's

A single-chapter **3D** vertical slice in **Godot 4.7**, built to look good
enough that someone says "wow" before they say "what is it".

This is a showcase, not the whole game. One room, one evening, one decision.
Later chapters get added around it; nothing here should assume it is alone.

---

## The pitch

Ziggy's is a pizza bar in Wichita. On the night the third brownout of the
summer hits, the regulars are still there, and so are three little robots
that belong to the place. By closing time the room has decided to do
something about the data centers, and that decision is the guild.

The player is a **Meckie** — one of the three robots. Not a person. You roll
around a bar you know well, talk to people you know, and the choices are
about who you get to stay when the lights go out.

---

## WHY THIS IS 3D

Because the whole point is the room. One interior, lit properly, is worth
more than ten flat screens. **Everything below is achievable with primitives,
shaders and lights — no modelled or animated characters are required, and
none should be faked with placeholder assets.**

### Art direction — this is a hard requirement, not flavour

**Two temperatures, always in frame together.**

- **Inside Ziggy's is warm**: amber pendant lights over the bar, a red-pink
  neon sign, the orange mouth of a pizza oven, dust in the light.
- **Outside is cold**: the data-center campus glow on the horizon, a hard
  cyan (`#00d4ff`) that comes through the front window and lies across the
  floor in a long rectangle.
- The brownout is the moment those swap: the warm lights die, and for a
  few seconds the room is lit **only** by the cold light from outside.
  That single beat is the shot the whole chapter exists for.

**Technique** (all code-authored, all text files):

- `WorldEnvironment` with glow/bloom, volumetric fog, subtle SSAO, and a
  slight tonemap toward warm.
- Real `OmniLight3D`/`SpotLight3D` with shadows for the pendants; an
  emissive `StandardMaterial3D` for the neon and the oven mouth.
- Haze so light shafts are visible — the bar should look like a room with
  air in it.
- A wet-looking bar top: high roughness variation, screen-space reflections.
- Subtle camera sway and a little chromatic aberration at the brownout.
- Godot's built-in `CSGBox3D`/`CSGCylinder3D` for architecture and
  furniture. Boxes and cylinders, lit well, are the entire set.

**Characters**: the three Meckies are built from primitives — a rounded
body, a floating emissive faceplate, a signature colour. That reads as a
designed robot, not as a missing model. Humans are **stylised, seated or
standing figures** with strong silhouettes and lit faces; do not attempt
realistic humans, and do not import free character models.

---

## The cast

The Meckies are playable. The people are the room.

| Meckie | Colour | Notes |
|---|---|---|
| **Droid** | `#00d4ff` | Cyan — the same colour as the enemy campus, which nobody in the bar has failed to notice |
| **Eva** | `#ff6fa8` | Pink |
| **Sid** | pick one, warm | Should sit on the amber side of the palette |

People at Ziggy's: **Chad, Oleg, Ramsey, Nic, Conner, Nick, Jocelyn, Tonya,
Grant**, and **Caroline** behind the bar.

**Write them light.** These are real people. Give them a role in the room and
a voice that is warm and dry — no invented tragedies, no backstory that
claims to know them, nothing that would be strange to read about yourself.
Caroline runs the bar and closes the chapter. Everyone else is a regular
with an opinion about the brownouts.

---

## Deliverables

1. **The room.** Ziggy's interior in 3D: bar with stools, booths, pizza oven,
   front window onto the street, neon sign, jukebox. Navigable.
2. **A playable Meckie.** Pick one of the three at the start; move around the
   room in third person with a light follow-camera. The other two are present
   and idle.
3. **Talk to the room.** Walk up to any of the ten people and talk. Dialogue
   is data-driven (JSON + schema, same shape the existing content layer uses)
   so lines can be edited without touching code.
4. **The brownout.** A scripted beat partway through: warm lights fail, the
   room goes cold-blue, everything is lit only from outside. Audio drops to
   a hum. It must be a moment, not a light switch.
5. **One decision, four ways to answer.** At closing, Caroline asks what the
   room is going to do. Four answers, recorded as flags in the same save
   format the existing game uses, so a later chapter can read them.
6. **It looks finished.** Title, pause, settings for resolution and volume,
   and a clean quit. A demo that crashes on Escape is not a demo.

## Acceptance criteria

- Runs at 60fps at 1080p on an M-series Mac.
- The brownout beat is visually unmistakable in a screenshot — someone who
  has never seen the game can tell the lights just went out.
- Every one of the ten people has at least one line of dialogue and reacts
  to the brownout differently.
- The chosen Meckie's signature colour actually appears in the world: its
  emissive face, and the light it casts on nearby surfaces.
- The decision writes a flag that survives save/load.
- No imported 3D character models, no asset-store packs, no placeholder
  textures with watermarks. Primitives, shaders and lights only.

---

## Technical notes for whoever builds this

- **Godot 4.7**, Forward+ renderer, GDScript.
- Scenes are `.tscn` text. Keep them small and composed — one scene per
  prop, assembled into the room — so they stay diffable.
- **`--headless` CANNOT render.** It uses a dummy renderer: no GPU context,
  `get_viewport().get_texture()` fails, and `--write-movie` writes a
  ~330-byte stub that looks like success. Import checks and script parsing
  run headless; anything that produces a picture must run **windowed**.
- Keep the content layer's habits: schemas validate data, and content lives
  in JSON rather than in code.
- Target the existing save format so this chapter's flags are readable by
  the main campaign later.
