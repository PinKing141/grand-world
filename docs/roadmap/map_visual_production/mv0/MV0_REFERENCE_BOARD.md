# MV-0 Reference Board

## Status and Usage Rule

**State:** Seeded from research; Art/Product approval pending.

References are used to understand hierarchy, layering, camera scale, and production technique. They are not source assets. No image, texture, font, shader, map data, icon, or proprietary colour set from another game may enter the project without explicit rights.

For every retained reference, the production board must record capture date, reviewer, functional claim, primary/secondary/community status, and whether any local copy may be stored.

## Primary Commercial References

### Europa Universalis IV

- [Official Steam page](https://store.steampowered.com/app/236850/Europa_Universalis_IV/)
- Primary lesson: political mode remains readable while terrain, coast, units, labels, and province structure coexist.
- Study:
  - Muted country-colour family rather than unrestricted high saturation.
  - Strong sovereign versus restrained province border hierarchy.
  - Country labels that follow broad territory shape without extreme distortion.
  - Calm water as negative space.
  - Wide/regional/close density changes.
- Do not copy: exact palette, label styling, textures, border art, map data, shader implementation, or unit assets.

### Crusader Kings II

- [Official Steam page](https://store.steampowered.com/app/203770/Crusader_Kings_II/)
- Primary lesson: regional terrain and holdings can give political space local character.
- Study:
  - Terrain/realm transition.
  - Settlement/holding density.
  - Heraldic identity and regional cues.
- Do not copy: character-first density, coat-of-arms assets, terrain textures, holding art, or UI conventions that conflict with country-first play.

## Secondary Presentation Research

### Contemporary review evidence

- [PC Gamer EU4 review](https://www.pcgamer.com/europa-universalis-iv-review/)
- Functional claim: the finished map experience was supported by vibrant regional detail, changing seasons, animated routes, and units—not only flat province colours.
- Production use: justify evaluating the whole map stack while keeping political readability primary.

### Paradox map-development discussion

- [EU4 development diary discussion, 9 October 2018](https://forum.paradoxplaza.com/forum/developer-diary/eu4-development-diary-9th-of-october-2018.1122972/)
- Functional claim: attractive country-name stretching and placement still receive manual/art-directed map attention.
- Production use: support authored label hints and outlier review rather than expecting one algorithm to solve every realm.

## Community Technical Research

These sources are useful engineering observations, not authoritative documentation of current proprietary implementation.

| Source | Lesson to verify independently |
|---|---|
| [EU4 map-modding quick reference](https://www.eu4cn.com/wiki/Map_Modding_Quick_Reference) | Mature map stacks separate height, normal, terrain, rivers, trees, seasons, water, provinces, and political data |
| [EU4 reference map notes](https://xylozi.wordpress.com/eu4/reference-map/) | Compare the responsibilities of colour, normal, river, seasonal, and water assets |
| [WebGL EU4-map analysis](https://nickb.dev/blog/simulating-the-eu4-map-in-the-browser-with-webgl/) | Thick country/thin province hierarchy and political/terrain composition |
| [EU4 GPU frame-capture analysis](https://www.hlsl.co.uk/blog/2018/7/18/what-can-we-learn-from-gpu-frame-captures-europa-universalis-4) | Use frame captures to reason about passes and cost rather than guessing from screenshots |

## Historical Atlas Reference Categories

Build a separate legally reviewed board for:

- Fifteenth- and sixteenth-century political atlases.
- Modern scholarly reconstructions of 1444 political geography.
- Physical relief maps.
- Köppen/biome/ecoregion references used only for climate structure.
- Hydrography and coast/bathymetry references.
- Period settlement importance and trade-route maps.
- Typographic atlases showing large realm, regional, water, and settlement hierarchy.

## Project-Original Identity Requirements

The final map must define its own:

- Political palette and reserved interaction colours.
- Border colour, texture, and zoom response.
- Coast and water material.
- Terrain material family.
- Country and geographic typography.
- Capital, settlement, port, unit, battle, and occupation marker language.
- Selection, route, warning, and invalid-action feedback.

## Reference Review Checklist

- What exact player question does this reference solve?
- Which zoom and map mode does it represent?
- Is the lesson visual hierarchy, content density, material, motion, or interaction?
- Does it still work on minimum-spec hardware and accessibility settings?
- Is it compatible with the project's country-first design?
- Can the project create an original implementation from owned/licensed inputs?
- What existing scope would this reference displace?

## Approval Conditions

- Art/Product selects the primary political, terrain/water, and typography targets.
- Technical Art confirms each target has a plausible asset/shader path.
- Rendering/QA confirms a plausible performance path.
- Production confirms every planned shipping input has a provenance strategy.

