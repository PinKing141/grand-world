# Country Label Font

Country labels use the bundled `LibreBaskerville-Variable.ttf` resource. The file is the unmodified Libre Baskerville variable font from the [Google Fonts repository](https://github.com/google/fonts/tree/main/ofl/librebaskerville).

- Upstream filename: `LibreBaskerville[wght].ttf`
- SHA-256: `05A95421961341C5B2556285E8415DF9DB27DAB4F4ABE22B446B3C6A8B916C5D`
- Licence: SIL Open Font License 1.1; see `OFL-LibreBaskerville.txt`
- Required current coverage: Basic Latin, Latin-1 Supplement, and Latin Extended characters used by the 1444 English catalogue
- Future localisation: scripts outside the bundled font's coverage require explicitly bundled fallback families and renewed layout baselines

The asset is loaded by resource path rather than requested from the operating system, keeping metrics identical in the editor and exported builds.
