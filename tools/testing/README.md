# Automated Phase 1–5 Test Harness

Run the complete automated suite from the project root:

~~~powershell
python tools/testing/run_all_tests.py
~~~

The runner finds Godot automatically, runs every Python and GDScript regression, performs the deterministic 1444–1700 Alpha campaign plus regional/global soaks, exports a temporary Windows debug build, starts that package headlessly, and writes `docs/test_reports/latest_headless_report.md`.

Useful options:

~~~powershell
# Fast development pass: no soak or export
python tools/testing/run_all_tests.py --quick

# Full gameplay/soak coverage without packaging
python tools/testing/run_all_tests.py --skip-export

# Explicit engine path
python tools/testing/run_all_tests.py --godot "C:\path\to\Godot_console.exe"
~~~

Close the Godot editor before the packaging check. Windows cannot replace the loaded `map_editor` GDExtension DLL while the editor is using it.

The harness treats error text as failure even if a GDScript test accidentally exits with code zero. It also requires a positive success marker from every test, validates that the baked graph/economy plus economy and war UI are present in the export log, and verifies the exported game parses all expected provinces and countries.

Phase 5 coverage includes directional opinions, alliances, access, war declaration validation, ally participation, deterministic combat and reinforcement, retreat and recovery, siege and occupation, owner/controller separation, war score, province and money peace terms, white peace, truces, repeated wars, active-war save/load, corrupted war references, UI actions, and relations/war overlays.
