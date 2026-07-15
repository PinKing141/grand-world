# Country Registry Pipeline

`build_country_registry.py` is the P0 authority for country identity, display-name keys, adjective keys, political-colour references, source paths, and 1444 owner coverage.

Generate the registry after changing a country file, country colour, or ownership manifest:

```powershell
python tools/country_registry/build_country_registry.py
```

Run the blocking validation used by the automated suite:

```powershell
python tools/country_registry/build_country_registry.py --check
```

The validator rejects malformed filenames, duplicate tags, missing colours, missing manifest owners, stale source hashes, unresolved localisation keys, duplicate active display names, and every exact political-colour duplicate. It also checks all starting land-neighbour pairs in Oklab and rejects distances below `0.04`.

Generate the art-facing neighbour report after ownership or political colours change:

```powershell
python tools/country_registry/analyse_neighbour_colours.py
```

The report ranks every 1444 land-neighbour pair by normal Oklab distance, approximate protanopia/deuteranopia/tritanopia distance, shared-border length, and province-contact count. It also proposes deterministic one-country-at-a-time replacement candidates for high- and medium-risk countries. Those candidates are review aids, not automatic palette edits, and do not replace testing with colour-vision-deficient players.
