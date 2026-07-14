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
