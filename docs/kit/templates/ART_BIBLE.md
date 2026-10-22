# <GAME> – art bible

Approved by: <designer>, <date>. The judge's targets live in `art/targets/`; the numbers live in `art/assets.json`.

## Key art and target stills
| File | Camera | Use |
|---|---|---|
| `art/keyart.png` | hero | overall look |
| `art/targets/near.png` | <pitch°, distance m, fov> | close gameplay view: judge target for context shots at ≤ <x> m |
| `art/targets/mid.png` | <default camera> | default view: the main judge target |
| `art/targets/far.png` | <max zoom> | overview: readability of biomes, routes, the base |

The golden scene reproduces these three cameras exactly (`tests/proof/golden_*.gd`, fixed seed <n>).

## Look in one paragraph
<Felsenburg's was `WORLD` in `tools/asset_pipeline.py`: chunky voxel structures with flat colours and subtle per-cube
variation on a smooth faceted low-poly landscape that is not voxel; daylight from the upper left; defenders blue,
attackers red.>

## References and anti-references (per risky surface)
| Surface | Reference (we want) | Anti-reference (we never want) | Notes |
|---|---|---|---|
| Landform / cliffs | `art/targets/ref/cliffs_*.png` | `art/targets/anti/cliffs_*.png` (e.g. a rock facade on grey polygons, every mountain a cone) | |
| Water | | | |
| Sky, clouds, fog | | | "painterly and detailed", not flat |
| Vegetation | | | |
| UI | | | |

## Truth table ("look == rule")
One function decides each row; the renderer, the navmesh and placement all call it.

| Class | Looks like | Walkable | Buildable | Speed / cost | Decided by |
|---|---|---|---|---|---|
| grass flat | | yes | yes | 1.0 | `<MaskOwner>.class_at` |
| steep grass | grass + steep tint | yes | no | | |
| cliff | rock wall | no | no | — | |
| shallow water | | | | | |
| road | only where the nav really routes | yes | no | | |

## Palette and materials
- Single file `art/palette.json` (names → sRGB, roughness, metallic). voxkit and the shaders read it.
- **The palette board** `build/proof/palette_<day|dusk|night>.png` renders every colour on a cube row in the golden
  scene light. Colours are approved on this board, not on a grey background.
- Dark accents are chosen darker than they look on grey; no gloss on dark materials.
- Team colours: <ally hue> / <enemy hue>, colour-blind safe, readable at the far camera.
- A builder may add at most 3 colours per asset; they are reviewed into the palette or removed.

## Scale chart and asset classes
| Class | Voxel edge | Triangle budget | Shadow | Typical size | Seen at |
|---|---|---|---|---|---|
| structure | 0.125 m | from `perf/budgets.json` | yes | 4–10 m | 25–150 m |
| small prop | 0.0625 m | | no (< 1.5 m) | 0.3–1.5 m | 15–60 m |
| unit | 0.05 m | | near band only | 1.5–2.2 m | 15–90 m |

Real sizes by default (crows are 0.45 m long, not 0.65 m); any exaggeration is a class rule with a factor.

## Lighting, sky and post
<sun angle and colour per time of day, ambient, fog, tonemapping, SSAO/glow per preset; how night looks and how it
stays readable (light sources on units, houses and towers)>

## Failure library
Rule ids that apply to this game (from `docs/ART_PIPELINE.md` § Failure library), plus new ones as they appear.
