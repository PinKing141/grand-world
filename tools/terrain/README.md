# Terrain and Biome Pipeline

The physical terrain layer is independent from political ownership. Every province receives a biome, including unowned and impassable land, while oceans and inland water remain water.

Run the source refresh when the biome assignments need to be rebuilt:

~~~powershell
python tools/terrain/build_biome_map.py --refresh
~~~

For normal deterministic rebakes, use the reviewed manifest already stored in the project:

~~~powershell
python tools/terrain/build_biome_map.py
~~~

If Godot is open while the baker writes `assets/biome_map.png`, let the existing editor import it automatically. Do not run a second headless `Godot --import` instance against the project at the same time; Godot 4.7 can otherwise report invalid or duplicated editor progress tasks.

The refresh uses the generalized Global Biomes feature layer derived from WWF terrestrial ecoregions. Province-centroid assignments are stored in `docs/data/1444_biome_manifest.csv`. Explicit gameplay overrides handle large mountain, desert, rainforest and ice wasteland blocks. The generated `assets/biome_map.png` is aligned pixel-for-pixel with `assets/provinces.bmp`.

This is a global 1444 gameplay reconstruction of physical habitat, not a claim of exact local vegetation in every province. Precise global vegetation observations do not exist for 1444; the source layer supplies potential natural biome families, while the override layer records deliberate historical-map decisions.
