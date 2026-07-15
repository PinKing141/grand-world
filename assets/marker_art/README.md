# Placeholder Marker Art

This package supplies the project's temporary early-modern grand-strategy marker language. It learns from EU4's information hierarchy—clear heraldic ownership, screen-stable silhouettes, urgent conflict markers, and restrained atlas styling—but contains no copied Paradox art, flags, textures, fonts, or shader code.

## Generated runtime assets

- `generated/country_shield_atlas.png` — one stable high-resolution 128×128 slot for every canonical country tag, assembled into a 4096×4096 atlas.
- `generated/marker_icon_atlas.png` — original army, navy, battle, siege, capital, fort, port, cluster, destination, and invalid-action icons.
- `generated/marker_asset_manifest.json` — atlas layout, replacement status, source metadata, and active-1444 coverage.
- `generated/icons/*.png` — individual editable/replacement references for the icon family.

## Historical source policy

`source_flags/` contains openly licensed Wikimedia Commons thumbnails selected as historical banners, arms, near-period manuscript evidence, or clearly identified reconstructions. `source_flags/source_manifest.json` records the source URL, original URL, author/attribution, licence, hash, evidence class, and review warning for every image.

A country without defensible configured evidence receives a transparent atlas slot with the status `unassigned_requires_historical_research`. No invented country-specific heraldry is displayed. Stable atlas indices are retained so researched artwork can be added without breaking saves or runtime ownership mappings.

The shield generator renders each sourced 128×128 tile at 256×256 and downsamples it once with Lanczos filtering.

Runtime army shields use a slightly larger camera-scaled footprint than the original marker pass so the increased source detail remains visible instead of being crushed into a tiny number of screen pixels.

The source pack currently prioritises high-visibility 1444 states. Expanding it requires adding a reviewed entry to `tools/marker_art/historical_flag_sources.json`, running the fetch command once, reviewing the source manifest, and rebuilding.

## Rebuild

Fetch configured sources only when intentionally updating the third-party source pack:

```powershell
python tools/marker_art/build_marker_assets.py --fetch-sources
```

Normal offline rebuild:

```powershell
python tools/marker_art/build_marker_assets.py
```

CI/currentness check:

```powershell
python tools/marker_art/build_marker_assets.py --check
python tests/marker_asset_contract_smoke.py
```

## Replacement contract

Final redesigned artwork can replace individual source flags, transparent research slots, or the icon drawing functions. Preserve country atlas indices when possible. If indices or tile sizes change, regenerate `marker_asset_manifest.json` and keep the runtime contract test green.

The generated [historical shield research register](../../docs/roadmap/map_visual_production/HISTORICAL_SHIELD_RESEARCH_REGISTER.md) lists every current source-backed shield and every country still requiring research.

Long-term research progress belongs in `tools/marker_art/shield_research_reviews.json`, not in the generated Markdown. That tracker preserves researchers, review dates, candidate URLs, historical bearers, evidence ranges, outcomes, uncertainty notes, and approval status across rebuilds and long pauses in development.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) before distributing any build containing the sourced placeholder portions.
