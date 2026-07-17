# N1.1 Naval Maritime Graph Data Validation

- Source graph content hash: **ec65d10b6e1e8d0b**
- Total water records: **566**
- Total coastal land records: **1373**
- Sea zones classified: **566**
- Port candidates derived: **1141**
- Ports with a human-reviewed override: **29**
- Sea-zone overrides applied: **10**
- Port overrides applied: **29**
- Sea zones reclassified away from their derived default: **0**
- Ports without any sea exit (should be zero by construction): **0**
- Coastal land excluded as port candidates (touches only closed_water/lake zones, no real naval exit): **210**
- Asymmetric sea-neighbour edges found: **0**

## Sea-zone classification counts

- `coastal_sea`: 335
- `inland_sea`: 0
- `open_ocean`: 147
- `closed_water`: 84

## Rejected or malformed override rows

- None.

## Reciprocity issues

- None. Every sea-neighbour edge is reciprocal.

## Channel/Iberian fixture ports (N0.3)

- `87` Calais: enabled=True, primary_exit=1269, Calais - England Channel fixture port
- `89` Picardie: enabled=True, primary_exit=1271, Picardie - Burgundy-held hostile Channel interception fixture port
- `90` Vlaanderen: enabled=True, primary_exit=1269, Vlaanderen - Flanders secondary Channel interception fixture port
- `167` Caux: enabled=True, primary_exit=1271, Caux - England-held Normandy Channel fixture port
- `168` Normandie: enabled=True, primary_exit=1271, Normandie - England-held Channel fixture port
- `197` Roussillon: enabled=True, primary_exit=1296, Roussillon - Aragon Mediterranean fixture port
- `206` Galicia: enabled=True, primary_exit=1278, Galicia - Castile Iberian fixture port
- `207` Asturias: enabled=True, primary_exit=1276, Asturias - Castile Iberian fixture port
- `209` Vizcaya: enabled=True, primary_exit=1276, Vizcaya - Castile Iberian fixture port
- `212` Girona: enabled=True, primary_exit=1296, Girona - Aragon Mediterranean fixture port
- `213` Barcelona: enabled=True, primary_exit=1295, Barcelona - Aragon Mediterranean fixture port
- `220` Val�ncia: enabled=True, primary_exit=1295, Valencia - Aragon Mediterranean fixture port
- `224` Andaluc�a: enabled=True, primary_exit=1293, Andalucia - Castile Gibraltar-crossing fixture port
- `227` Lisboa: enabled=True, primary_exit=1291, Lisboa - Portugal Iberian fixture port
- `229` Beja: enabled=True, primary_exit=1292, Beja - Portugal Iberian fixture port
- `230` Algarve: enabled=True, primary_exit=1292, Algarve - Portugal Gibraltar-crossing fixture port
- `231` Porto: enabled=True, primary_exit=1291, Porto - Portugal Iberian fixture port
- `233` Cornwall: enabled=True, primary_exit=1272, Cornwall - England Channel fixture port
- `235` Kent: enabled=True, primary_exit=1270, Kent - England Channel fixture port
- `333` The Baleares: enabled=True, primary_exit=1295, The Baleares - Aragon Mediterranean island fixture port
- `1749` Cadiz: enabled=True, primary_exit=1293, Cadiz - Castile Gibraltar-crossing fixture port
- `1751` Ceuta: enabled=True, primary_exit=1293, Ceuta - Portugal Gibraltar-crossing fixture port
- `2988` Tarragona: enabled=True, primary_exit=1295, Tarragona - Aragon Mediterranean fixture port
- `4371` Sussex: enabled=True, primary_exit=1271, Sussex - England Channel fixture port
- `4373` Devon: enabled=True, primary_exit=1272, Devon - England Channel fixture port
- `4374` Dorset: enabled=True, primary_exit=1272, Dorset - England Channel fixture port
- `4385` Cotentin: enabled=True, primary_exit=1271, Cotentin - England-held Normandy Channel fixture port
- `4548` Huelva: enabled=True, primary_exit=1293, Huelva - Castile Gibraltar-crossing fixture port
- `4556` Aviero: enabled=True, primary_exit=1291, Aviero - Portugal Iberian fixture port
