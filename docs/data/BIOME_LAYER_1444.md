# 1444 Physical Biome Layer

The map separates two questions:

- **Political layer:** who controls a province on 11 November 1444?
- **Physical layer:** what broad terrain and vegetation should remain visible whether or not that province has an owner?

The physical layer uses 16 land and inland-water biome families derived from the WWF terrestrial ecoregion system. It covers desert and xeric scrub, tropical rainforest, dry forest, savanna, temperate forest, conifer forest, grassland, Mediterranean scrub, boreal forest, tundra, mountain grassland, mangrove, floodplain, rock and ice.

The source baseline is the [Global Biomes ArcGIS feature layer](https://services.arcgis.com/BG6nSlhZSAWtExvp/arcgis/rest/services/GlobalBiomes/FeatureServer/0), which is derived from WWF terrestrial ecoregions. The complete province assignment is recorded in `1444_biome_manifest.csv` and can be regenerated with `tools/terrain/build_biome_map.py`.

The imported strategy map uses a cropped Mercator-style projection rather than a pole-to-pole equirectangular projection. The geographic audit and biome builder share a calibrated map-Y-to-latitude transform so southern Africa, South America, Australia and New Zealand are not mistakenly sampled as Antarctic terrain.

## Historical interpretation

No exact worldwide vegetation survey exists for 1444. The layer should therefore be read as a historically appropriate pre-industrial gameplay baseline, not a metre-accurate reconstruction. Broad stable features—such as the Sahara, Arabian and Australian deserts; Congo and Amazon rainforests; major mountain systems; boreal forest; tundra; and Greenland ice—are represented explicitly. Future regional research can replace individual manifest rows without changing the rendering architecture.
