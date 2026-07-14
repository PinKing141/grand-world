extends SceneTree

const CountryRegistryScript = preload("res://scripts/simulation/country_registry.gd")
const GrandWorldSimulationController = preload("res://scripts/simulation/simulation_controller.gd")

const PREVIOUSLY_MISSING_SCENE_TAGS: Array[String] = [
	"ALQ", "ALU", "BEM", "CMR", "DNE", "DUA", "EVK", "FMC", "GCH",
	"GLC", "HET", "HRP", "INU", "JUK", "JVR", "KHN", "KSN", "KWK",
	"KYU", "LGT", "LST", "MIC", "NCN", "NGU", "NIL", "NNT", "OGE",
	"PNG", "RPN", "SHC", "SKH", "SWZ", "TEH", "THT", "TSW", "TZI",
]


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Country registry runtime test failed: %s" % message)
		quit(1)


func _run() -> void:
	var registry = CountryRegistryScript.new().load_registry()
	_require(registry.is_valid(), "generated registry must load: %s" % registry.error())
	_require(registry.country_count() == 1007, "registry must contain 1,007 unique scenario countries")
	_require(registry.has_country("KER"), "KER must resolve to one canonical country")
	_require(registry.display_name("KER") == "Keres", "KER must use the canonical Keres display name")
	_require(registry.display_name("DAU") == "Dauphine", "DAU must not retain filename whitespace")
	_require(not registry.has_country("No Owner"), "No Owner must not be a scenario country")
	_require(not registry.has_country("Ocean"), "Ocean must not be a scenario country")
	var keres_colour: Color = registry.country_colour("KER")
	_require(
		is_equal_approx(keres_colour.r, 183.0 / 255.0)
		and is_equal_approx(keres_colour.g, 76.0 / 255.0)
		and is_equal_approx(keres_colour.b, 132.0 / 255.0),
		"KER must use the canonical 183,76,132 political colour"
	)

	var packed := load("res://scenes/main.tscn") as PackedScene
	_require(packed != null, "main scene must load")
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var simulation := scene.get_node("SimulationController") as GrandWorldSimulationController
	var country_data := scene.get_node("Map/ProvinceSelector/CountryData") as CountryData
	_require(simulation != null and simulation.initialized, "simulation must bootstrap from the registry")
	_require(simulation.country_registry != null and simulation.country_registry.is_valid(), "controller registry must be valid")
	_require(simulation.scenario_definition.is_valid(), "scenario ownership must validate")
	_require(
		simulation.world.country_states.size() == registry.country_count(),
		"WorldState country catalogue must exactly match the canonical registry"
	)
	_require(not simulation.world.country_states.has("No Owner"), "No Owner must not enter WorldState")
	_require(not simulation.world.country_states.has("Ocean"), "Ocean must not enter WorldState")

	for tag in registry.country_tags():
		_require(simulation.world.country_states.has(tag), "WorldState is missing registry country %s" % tag)
		_require(country_data.country_id_to_country_name.has(tag), "presentation cache is missing %s" % tag)
		_require(
			String(country_data.country_id_to_country_name[tag]) == registry.display_name(tag),
			"presentation name for %s does not match the registry" % tag
		)

	for tag in PREVIOUSLY_MISSING_SCENE_TAGS:
		_require(simulation.world.country_states.has(tag), "formerly omitted country %s was not restored" % tag)
		_require(not simulation.world.get_country_provinces(tag).is_empty(), "%s lost its starting territory" % tag)

	_require(simulation.world.get_province_owner(4632) == "KER", "Keres province 4632 must remain owned by KER")
	for raw_province_id in simulation.world.province_states:
		var province_id := int(raw_province_id)
		var owner := simulation.world.get_province_owner(province_id)
		_require(owner.is_empty() or simulation.world.country_states.has(owner), "province %d has invalid owner %s" % [province_id, owner])

	_require(country_data.country_id_to_country_name.get("KER", "") == "Keres", "CountryData mirror must use Keres")
	var mirrored_colour: Color = country_data.country_id_to_color.get("KER", Color.TRANSPARENT)
	_require(mirrored_colour.is_equal_approx(keres_colour), "CountryData KER colour must match the registry")
	print("Country registry runtime test passed.")
	quit(0)
