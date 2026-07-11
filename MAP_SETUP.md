# Map Setup Guide

This project now contains the map demo assets and the installed `map_editor` addon.

## 1. Verify plugin installation

1. Open Godot.
2. Go to `Project -> Project Settings -> Plugins`.
3. Confirm `Grand Strategy Map Editor` is enabled.
4. In the General settings, confirm the rendering method is `Forward+`. The map's compute shaders do not work with the Compatibility renderer.

## 2. Verify required files

The project should contain these folders:
- `addons/map_editor/` — addon plugin files
- `assets/` — province and map textures
- `scripts/` — map rendering and selection logic
- `shaders/` — map shaders
- `scenes/` — demo scene files

## 3. Open the demo scene

1. In the Godot FileSystem dock, open `scenes/main.tscn`.
2. Inspect the scene tree and confirm the `Map` node is using `ComputeHelper`.
3. Confirm `ProvinceSelector` exists under `Map`, with `MapData` and `CountryData` beneath `ProvinceSelector`.

## 4. Run the demo

1. Press the Play button in Godot.
2. `scenes/main.tscn` is already configured as the project's main scene.
3. Use the following controls:
   - Arrow keys: move the camera
   - Mouse wheel: zoom in/out
   - Left mouse drag: pan the map; movement beyond 7 pixels cancels province selection
   - Middle mouse drag: pan immediately without selecting
   - WASD or arrow keys: move the camera
   - `+` / `-` or Page Up / Page Down: keyboard zoom
   - Home: reset the camera view
   - Hover: inspect a province, its owner, and its terrain
   - Left click: select a province and open its information panel; the owning country's territory lights up
   - `1` / `2` / `3`: switch between the political, terrain, and debug province-ID map modes
   - `/` or Ctrl+F: search countries and provinces; Enter focuses the first result
   - Right click or Escape: clear the current selection

Normal map interaction no longer changes province ownership. Ownership editing is disabled by default and is available only through the explicit debug settings on the `Map` node.

## 5. If the map does not appear

1. Wait for Godot's first asset import to finish before running the scene.
2. Confirm the project is using `Forward+`, not the Compatibility renderer.
3. Confirm `scenes/main.tscn` can see the textures in `assets/`.
4. Confirm `shaders/` and `scripts/` are present in the project.
5. Confirm the plugin is enabled in `Project Settings`.
6. Open the Godot Output panel and look for load errors.

The project disables parallel asset imports because Godot 4.7 can crash when these compute shaders are imported concurrently.

If the Output panel reports `progress_dialog.cpp` errors about flushing the message queue, another Godot editor or headless import is usually touching the same `.godot` import cache. Keep only one editor/import process open for this project. When the editor is already open, let its FileSystem dock import changed assets automatically; do not launch a separate `Godot --import` process at the same time. Restart the editor once after stopping any orphaned headless Godot process to clear stale progress tasks.

The demo now loads prebaked political-map textures by default. Rebuild them after ownership-data changes with:

~~~powershell
python tools/historical_ownership/bake_political_textures.py
~~~

The original compute generation remains available by disabling `use_prebaked_map_textures` on the `Map` node, but it is intended only for editor-side map topology work.

## 6. Phase 1A interaction smoke test

Run the automated map-UX smoke test from the project folder:

~~~powershell
& "C:\path\to\Godot.exe" --headless --path . --script res://tests/phase_1a_smoke.gd
~~~

The test verifies tooltip updates, selection and country highlighting, province metadata (including terrain and coastal status), map-mode switching without viewport rebuilds, search indexing, camera focus, clearing selection, and non-mutating normal clicks.

## 7. Optional: use the addon in your own scene

1. Add the plugin by placing `addons/map_editor/` in the project.
2. Create a `CountryData` resource if needed.
3. Select that resource and use the custom inspector panel provided by the addon.
4. Connect your map scene to the `CountryData` and `MapData` nodes.

---

### Cleaned up

The unused attached package folder `gs-map-editor/` was removed because the project now uses the copied demo assets directly.
