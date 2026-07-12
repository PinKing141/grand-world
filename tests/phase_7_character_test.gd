extends SceneTree

const CampaignWorldStateScript = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBusScript = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationSchedulerScript = preload("res://scripts/simulation/simulation_scheduler.gd")
const EconomyDefinitionsScript = preload("res://scripts/simulation/economy_definitions.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const WarfareSystemScript = preload("res://scripts/simulation/warfare_system.gd")
const CharacterDefinitionsScript = preload("res://scripts/simulation/character_definitions.gd")
const CharacterSystemScript = preload("res://scripts/simulation/character_system.gd")
const ArrangeMarriageCommandScript = preload("res://scripts/simulation/commands/arrange_marriage_command.gd")
const AssignCommanderCommandScript = preload("res://scripts/simulation/commands/assign_commander_command.gd")
const DeclareClaimWarCommandScript = preload("res://scripts/simulation/commands/declare_claim_war_command.gd")
const OfferPeaceCommandScript = preload("res://scripts/simulation/commands/offer_peace_command.gd")
const AcceptPeaceCommandScript = preload("res://scripts/simulation/commands/accept_peace_command.gd")

const OWNERS := {
	206: "CAS", 215: "CAS", 217: "CAS", 219: "CAS", 224: "CAS", 225: "CAS",
	211: "ARA", 212: "ARA", 214: "ARA", 220: "ARA",
	227: "POR", 228: "POR", 231: "POR",
	222: "GRA", 223: "GRA", 226: "GRA", 4546: "GRA", 210: "NAV",
}
const NAMES := {"CAS": "Castile", "ARA": "Aragon", "POR": "Portugal", "GRA": "Granada", "NAV": "Navarre"}


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Phase 7 character test failed: %s" % message)
		quit(1)


func _make_simulation() -> Dictionary:
	var world := CampaignWorldStateScript.new()
	world.initialize(OWNERS, NAMES, "phase7_character_test", 14441111)
	var economy = EconomyDefinitionsScript.load_default()
	EconomySystemScript.initialize_world(world, economy)
	WarfareSystemScript.initialize_armies(world)
	var definitions := CharacterDefinitionsScript.load_default()
	CharacterSystemScript.initialize_world(world, definitions)
	var events := SimulationEventBusScript.new()
	root.add_child(events)
	var scheduler := SimulationSchedulerScript.new(world, events)
	scheduler.monthly_systems.append(func(month_world: CampaignWorldState) -> void:
		CharacterSystemScript.process_month(month_world, events)
		EconomySystemScript.process_month(month_world, events, economy))
	return {"world": world, "events": events, "scheduler": scheduler, "definitions": definitions}


func _cleanup(simulation: Dictionary) -> void:
	var scheduler: SimulationScheduler = simulation.get("scheduler")
	if scheduler != null:
		scheduler.monthly_systems.clear()
	var events: SimulationEventBus = simulation.get("events")
	if is_instance_valid(events):
		events.free()
	simulation.clear()


func _run() -> void:
	var definitions := CharacterDefinitionsScript.load_default()
	_require(definitions.is_valid(), "character definitions must validate: %s" % definitions.error())
	var malformed := definitions.characters()
	malformed["ch_cas_juan_ii"]["father_id"] = "ch_cas_juan_ii"
	var malformed_data := {
		"version": 1, "characters": malformed, "dynasties": definitions.dynasties(),
		"titles": definitions.titles(), "country_rulers": definitions.country_rulers(), "claims": definitions.claims(),
	}
	_require(not CharacterDefinitionsScript.from_data(malformed_data).is_valid(), "definition validation must reject ancestry cycles")

	var simulation := _make_simulation()
	var world: CampaignWorldState = simulation["world"]
	var scheduler: SimulationScheduler = simulation["scheduler"]
	_require(world.character_registry.size() == 12, "the Iberian slice must load twelve starting characters")
	_require(world.dynasty_registry.size() == 5 and world.title_registry.size() == 5, "dynasties and primary titles must load")
	_require(CharacterSystemScript.ruler_id(world, "CAS") == "ch_cas_juan_ii", "Castile must start with its authoritative ruler")
	_require(CharacterSystemScript.heir_id(world, "CAS") == "ch_cas_enrique", "Castile must start with a valid heir")
	_require(String(world.title_registry["k_castile"]["holder_id"]) == "ch_cas_juan_ii", "country ruler and primary title holder must agree")
	_require(CharacterSystemScript.age_years(world, "ch_cas_enrique") == 19, "ages must be derived from birth date and campaign date")
	_require(int(world.country_runtime("CAS").get("ruler_modifiers", {}).get("tax_modifier_bp", 0)) != 0, "ruler skills and traits must create country modifiers")

	# Commands preserve family and army ownership invariants.
	var marriage := ArrangeMarriageCommandScript.new("ch_cas_enrique", "ch_nav_blanca", "CAS")
	_require(marriage.validate(world).is_empty(), "two valid unmarried adults must be marriage candidates")
	scheduler.submit(marriage)
	scheduler.process_commands()
	_require(String(world.character_registry["ch_cas_enrique"]["spouse_id"]) == "ch_nav_blanca", "marriage must update the first spouse")
	_require(String(world.character_registry["ch_nav_blanca"]["spouse_id"]) == "ch_cas_enrique", "marriage must be symmetric")
	_require(not ArrangeMarriageCommandScript.new("ch_cas_juan_ii", "ch_cas_enrique", "CAS").validate(world).is_empty(), "parents and children must never be valid spouses")
	var cas_army := world.country_armies("CAS")[0]
	var commander := AssignCommanderCommandScript.new("CAS", cas_army, "ch_cas_enrique")
	_require(commander.validate(world).is_empty(), "adult court members must be valid commanders")
	scheduler.submit(commander)
	scheduler.process_commands()
	_require(String(world.get_army(cas_army).get("commander_id", "")) == "ch_cas_enrique", "commander assignment must reach authoritative army state")
	_require(not AssignCommanderCommandScript.new("GRA", cas_army, "ch_gra_yusuf").validate(world).is_empty(), "another country cannot assign this army's commander")

	var opinion := CharacterSystemScript.opinion_breakdown(world, "ch_cas_enrique", "ch_nav_blanca")
	_require(int(opinion.get("total", 0)) > 0 and (opinion.get("sources", []) as Array).size() >= 3, "opinions must expose named, explainable sources")

	# The same pre-death save must produce byte-identical succession outcomes.
	var pre_death_save := world.to_save_dict("phase7-test")
	var replay := _make_simulation()
	var replay_world: CampaignWorldState = replay["world"]
	_require(replay_world.apply_save_dict(pre_death_save).is_empty(), "pre-death character save must load")
	CharacterSystemScript.kill_character(world, simulation["events"], "ch_cas_juan_ii", "test succession")
	CharacterSystemScript.kill_character(replay_world, replay["events"], "ch_cas_juan_ii", "test succession")
	_require(CharacterSystemScript.ruler_id(world, "CAS") == "ch_cas_enrique", "ruler death must install the deterministic first heir")
	_require(String(world.title_registry["k_castile"]["holder_id"]) == "ch_cas_enrique", "succession must transfer the primary title")
	_require(not bool(world.character_registry["ch_cas_juan_ii"]["alive"]), "dead characters must remain as historical records")
	_require(world.checksum() == replay_world.checksum(), "succession from the same saved state must be deterministic")

	var round_trip := _make_simulation()
	var round_trip_world: CampaignWorldState = round_trip["world"]
	var post_succession_save := world.to_save_dict("phase7-test")
	_require(round_trip_world.apply_save_dict(post_succession_save).is_empty(), "post-succession save must retain valid family/title references")
	_require(round_trip_world.checksum() == world.checksum(), "character registries must round-trip exactly")
	var ancestry_corruption := post_succession_save.duplicate(true)
	ancestry_corruption["character_registry"]["ch_cas_juan_ii"]["father_id"] = "ch_cas_enrique"
	var ancestry_target := _make_simulation()
	_require((ancestry_target["world"] as CampaignWorldState).apply_save_dict(ancestry_corruption).contains("cycle"), "save validation must reject ancestry cycles before mutation")
	var title_corruption := post_succession_save.duplicate(true)
	title_corruption["title_registry"]["k_castile"]["liege_title_id"] = "k_aragon"
	title_corruption["title_registry"]["k_aragon"]["liege_title_id"] = "k_castile"
	var title_target := _make_simulation()
	_require((title_target["world"] as CampaignWorldState).apply_save_dict(title_corruption).contains("cycle"), "save validation must reject title-liege cycles before mutation")

	# A schema-3 campaign migrates onto the scenario's authoritative character setup.
	var legacy := pre_death_save.duplicate(true)
	legacy["schema_version"] = 3
	legacy.erase("character_registry")
	legacy.erase("dynasty_registry")
	legacy.erase("title_registry")
	legacy.erase("claim_registry")
	var migrated := CampaignWorldStateScript.migrate_save_data(legacy)
	_require(int(migrated["schema_version"]) == 4, "schema 3 saves must migrate to schema 4")
	var migration_target := _make_simulation()
	_require((migration_target["world"] as CampaignWorldState).apply_save_dict(migrated).is_empty(), "migrated saves must merge scenario character defaults")
	_require((migration_target["world"] as CampaignWorldState).character_registry.size() == 12, "migration must retain the Phase 7 scenario roster")

	# Claims use a dedicated war goal and enforce through an atomic peace term.
	var claim_sim := _make_simulation()
	var claim_world: CampaignWorldState = claim_sim["world"]
	var claim_scheduler: SimulationScheduler = claim_sim["scheduler"]
	var claim_war := DeclareClaimWarCommandScript.new("CAS", "GRA", "claim_cas_granada")
	_require(claim_war.validate(claim_world).is_empty(), "a living court claimant must unlock a title claim war")
	claim_scheduler.submit(claim_war)
	claim_scheduler.process_commands()
	var war_id := String(claim_world.war_registry.keys()[0])
	_require(String((claim_world.war_registry[war_id]["war_goal"] as Dictionary).get("type", "")) == "press_claim", "claim declarations need a distinct war-goal type")
	claim_world.war_registry[war_id]["total_war_score"] = 40
	claim_scheduler.submit(OfferPeaceCommandScript.new(war_id, "CAS", "GRA", [{"type": "press_claim", "claim_id": "claim_cas_granada"}]))
	claim_scheduler.process_commands()
	var offer_id := String((claim_world.war_registry[war_id]["peace_offers"] as Dictionary).keys()[0])
	claim_scheduler.submit(AcceptPeaceCommandScript.new(war_id, offer_id, "GRA"))
	claim_scheduler.process_commands()
	_require(bool(claim_world.claim_registry["claim_cas_granada"].get("pressed", false)), "accepted peace must mark the claim pressed")
	_require(String(claim_world.title_registry["k_granada"].get("holder_id", "")) == "ch_cas_enrique", "accepted claim peace must transfer the legal title")
	_require(String(claim_world.war_registry[war_id].get("status", "")) == "ended", "claim peace must close the war normally")

	# Reproduction is periodic and deterministic rather than per-frame.
	var children_before := claim_world.character_registry.size()
	claim_scheduler.submit(ArrangeMarriageCommandScript.new("ch_cas_enrique", "ch_nav_blanca", "CAS"))
	claim_scheduler.process_commands()
	claim_scheduler.advance_days(3650)
	_require(claim_world.character_registry.size() > children_before, "a fertile adult marriage must produce the next generation during a decade soak")
	for character in claim_world.character_registry.values():
		var record: Dictionary = character
		for raw_child in record.get("children", []):
			_require(claim_world.character_registry.has(String(raw_child)), "all child references must remain valid")

	print("Phase 7 character test passed. characters=%d dynasties=%d titles=%d checksum=%s" % [
		claim_world.character_registry.size(), claim_world.dynasty_registry.size(), claim_world.title_registry.size(), claim_world.checksum().left(16),
	])
	_cleanup(simulation)
	_cleanup(replay)
	_cleanup(round_trip)
	_cleanup(ancestry_target)
	_cleanup(title_target)
	_cleanup(migration_target)
	_cleanup(claim_sim)
	quit(0)
