# Country Label Territory Bake

`build_label_territory_map.py` converts the full-resolution province bitmap into a conservative quarter-resolution province-ID raster used only for country-label fitting and shape analysis.

Each output pixel represents a `4x4` source block. It receives a province ID only when every source pixel belongs to the same province; mixed coastline and border blocks become zero. A rectangle composed from owned IDs is therefore inside political territory rather than merely close to province-centre anchors. The quarter-resolution bake keeps large-country layout batches within the presentation frame budget while retaining a conservative boundary.

Every visible label uses the canonical full country name. Internal tags remain stable simulation identifiers and searchable metadata, but are never substituted for a name. The runtime measures the main connected land body's raster covariance so elongated countries follow their dominant geographic axis; Italy, Scandinavia, Britain, and other diagonal or north-south shapes therefore do not receive a forced horizontal label. Small territories retain their full name and defer it to a close-zoom screen fallback when it cannot fit readably.

Regenerate after changing `assets/provinces.bmp` or `assets/definition.csv`:

```powershell
python tools/map_labels/build_label_territory_map.py
```

Run the blocking stale-data check:

```powershell
python tools/map_labels/build_label_territory_map.py --check
```

The normal headless suite compares projected label rectangles, orientation, scale, and text against five deterministic layout baselines. To also open a Forward+ rendering window and compare GPU screenshots for the default world view, dense Europe, island-heavy Southeast Asia, Scandinavia, and the Italian peninsula, run:

```powershell
python tools/map_labels/run_visual_regression.py --godot C:\path\to\Godot_console.exe
```

Only intentionally approved visual changes should replace the PNG baselines:

```powershell
python tools/map_labels/run_visual_regression.py --update --godot C:\path\to\Godot_console.exe
```

The project-wide runner exposes the same rendered gate through `--visual`.

Do not add Godot's `--headless` switch to the GPU capture command. This project's compute-map renderer requires the Forward+ rendering path; the logic/layout tests remain headless-safe.
