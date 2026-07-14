# Map Visual MV-0 Audit Tools

Build the deterministic asset/render baseline:

~~~powershell
python tools/map_visual_audit/build_map_visual_audit.py
~~~

Check that the generated reports are current without writing files:

~~~powershell
python tools/map_visual_audit/build_map_visual_audit.py --check
~~~

The source provenance status lives in `map_asset_manifest.json`. The tool combines that authored record with file hashes, dimensions, Godot import settings, project render settings, scene material facts, shader metadata, planned-layer gaps, and deterministic findings.

Generated outputs are written to:

- `docs/roadmap/map_visual_production/mv0/MV0_ASSET_RENDER_AUDIT.md`
- `docs/roadmap/map_visual_production/mv0/mv0_asset_render_audit.json`

Do not use the generated audit as proof that an asset is legally distributable. `verified_*` status requires an actual licence/provenance record; unresolved imported map assets remain release risks.

Capture the map-only current-state benchmark views through the Godot 4.7 Forward+ renderer:

~~~powershell
python tools/map_visual_audit/capture_mv0_baselines.py --godot C:\path\to\Godot_v4.7_console.exe
~~~

The capture hides HUD controls but keeps world-space country labels and map objects. It writes ten standard-region/mode PNGs plus engine, hardware, memory, draw-call, label, and scripted camera-motion measurements to `tests/baselines/map_visual_mv0/current/`.

Isolate the current camera-motion cost across labels, army markers, and the base map:

~~~powershell
python tools/map_visual_audit/run_mv0_performance_probe.py --godot C:\path\to\Godot_v4.7_console.exe
~~~

This writes `mv0_performance_probe.json` beside the captures. It is a rendered wall-frame diagnostic, not a substitute for an external GPU pass capture.
