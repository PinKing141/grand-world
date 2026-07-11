extends SceneTree

const CampaignWorldState = preload("res://scripts/simulation/campaign_world_state.gd")
const SimulationEventBus = preload("res://scripts/simulation/simulation_event_bus.gd")
const SimulationScheduler = preload("res://scripts/simulation/simulation_scheduler.gd")
const EconomyDefinitionsScript = preload("res://scripts/simulation/economy_definitions.gd")
const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const ArmyMovementSystemScript = preload("res://scripts/simulation/army_movement_system.gd")
const DiplomacySystemScript = preload("res://scripts/simulation/diplomacy_system.gd")
const WarfareSystemScript = preload("res://scripts/simulation/warfare_system.gd")
const ImproveRelationsCommandScript = preload("res://scripts/simulation/commands/improve_relations_command.gd")
const FormAllianceCommandScript = preload("res://scripts/simulation/commands/form_alliance_command.gd")
const BreakAllianceCommandScript = preload("res://scripts/simulation/commands/break_alliance_command.gd")
const RequestMilitaryAccessCommandScript = preload("res://scripts/simulation/commands/request_military_access_command.gd")
const GrantMilitaryAccessCommandScript = preload("res://scripts/simulation/commands/grant_military_access_command.gd")
const DeclareWarCommandScript = preload("res://scripts/simulation/commands/declare_war_command.gd")
const MoveArmyCommandScript = preload("res://scripts/simulation/commands/move_army_command.gd")
const OfferPeaceCommandScript = preload("res://scripts/simulation/commands/offer_peace_command.gd")
const AcceptPeaceCommandScript = preload("res://scripts/simulation/commands/accept_peace_command.gd")
const ProvincePathfinderScript = preload("res://scripts/simulation/province_pathfinder.gd")

const GIBRALTAR := 226
const CEUTA := 1751
const CADIZ := 227


func _initialize() -> void:
	call_deferred("_run")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("Phase 5 warfare test failed: %s" % message)
		quit(1)


func _make_world() -> CampaignWorldState:
	var world := CampaignWorldState.new()
	world.initialize(
		{GIBRALTAR: "CAS", CEUTA: "MOR", CADIZ: "POR"},
		{"CAS": "Castile", "MOR": "Morocco", "POR": "Portugal"},
		"phase5_test",
		14441111
	)
	world.global_flags["enforce_military_access"] = true
	var alliance := DiplomacySystemScript.relation(world, "CAS", "POR")
	alliance["alliance"] = true
	DiplomacySystemScript.set_relation(world, "CAS", "POR", alliance)
	EconomySystemScript.initialize_world(world, EconomyDefinitionsScript.load_default())
	WarfareSystemScript.initialize_armies(world)
	var castile := world.get_army("a_CAS")
	castile["strength"] = 5000
	castile["maximum_strength"] = 5000
	castile["attack"] = 175
	world.army_registry["a_CAS"] = castile
	var morocco := world.get_army("a_MOR")
	morocco["strength"] = 750
	morocco["maximum_strength"] = 750
	morocco["attack"] = 80
	world.army_registry["a_MOR"] = morocco
	return world


func _make_scheduler(world: CampaignWorldState, events: SimulationEventBus) -> SimulationScheduler:
	var scheduler := SimulationScheduler.new(world, events)
	scheduler.daily_systems.append(func(day_world: CampaignWorldState) -> void: ArmyMovementSystemScript.advance_day(day_world, events))
	scheduler.daily_systems.append(func(day_world: CampaignWorldState) -> void: WarfareSystemScript.advance_day(day_world, events))
	return scheduler


func _active_battle_count(world: CampaignWorldState, war_id: String) -> int:
	var count := 0
	for battle in (world.war_registry[war_id].get("battles", {}) as Dictionary).values():
		if String((battle as Dictionary).get("status", "")) == "active":
			count += 1
	return count


func _run() -> void:
	# Relationship commands are deterministic and directional where required.
	var relation_world := CampaignWorldState.new()
	relation_world.initialize({1: "SWE", 12: "DAN"}, {"SWE": "Sweden", "DAN": "Denmark"}, "relations_test")
	var relation_events := SimulationEventBus.new()
	root.add_child(relation_events)
	var relation_scheduler := SimulationScheduler.new(relation_world, relation_events)
	relation_world.global_flags["enforce_military_access"] = true
	_require(not ProvincePathfinderScript.can_enter(ProvinceGraph.load_default(), relation_world, "SWE", 12), "neutral territory must require diplomatic access")
	for index in range(3):
		relation_scheduler.submit(ImproveRelationsCommandScript.new("SWE", "DAN"))
	relation_scheduler.process_commands()
	_require(DiplomacySystemScript.opinion(relation_world, "SWE", "DAN") == 30, "improve-relations commands must accumulate")
	_require(DiplomacySystemScript.opinion(relation_world, "DAN", "SWE") == 0, "opinions must remain directional")
	relation_scheduler.submit(FormAllianceCommandScript.new("SWE", "DAN"))
	relation_scheduler.process_commands()
	_require(DiplomacySystemScript.are_allied(relation_world, "SWE", "DAN"), "countries with sufficient opinion must form an alliance")
	relation_scheduler.submit(BreakAllianceCommandScript.new("SWE", "DAN"))
	relation_scheduler.process_commands()
	_require(not DiplomacySystemScript.are_allied(relation_world, "SWE", "DAN"), "breaking an alliance must update the bilateral relationship")
	relation_scheduler.submit(RequestMilitaryAccessCommandScript.new("SWE", "DAN"))
	relation_scheduler.process_commands()
	var request_relation := DiplomacySystemScript.relation(relation_world, "SWE", "DAN")
	_require(bool((request_relation["access_requests"] as Dictionary).get("SWE", false)), "access requests must be stored")
	relation_scheduler.submit(GrantMilitaryAccessCommandScript.new("DAN", "SWE"))
	relation_scheduler.process_commands()
	_require(DiplomacySystemScript.has_access(relation_world, "SWE", "DAN"), "the host must be able to grant directional access")
	_require(ProvincePathfinderScript.can_enter(ProvinceGraph.load_default(), relation_world, "SWE", 12), "granted access must open the host's territory")

	# Complete deterministic Castile-Morocco war loop.
	var world := _make_world()
	var events := SimulationEventBus.new()
	root.add_child(events)
	var scheduler := _make_scheduler(world, events)
	var battle_started_count := [0]
	var battle_reinforced_count := [0]
	var occupation_count := [0]
	events.battle_started.connect(func(_war: String, _battle: String, _province: int) -> void: battle_started_count[0] += 1)
	events.battle_reinforced.connect(func(_battle: String, _army: String, _side: String) -> void: battle_reinforced_count[0] += 1)
	events.occupation_changed.connect(func(_war: String, _province: int, _controller: String) -> void: occupation_count[0] += 1)

	scheduler.submit(DeclareWarCommandScript.new("CAS", "MOR", CEUTA))
	scheduler.process_commands()
	_require(world.war_registry.size() == 1, "a valid declaration must create one war")
	var war_id := String(world.war_registry.keys()[0])
	_require(DiplomacySystemScript.are_at_war(world, "CAS", "MOR"), "war participants must become hostile")
	_require((world.war_registry[war_id]["attackers"] as Array).has("POR"), "an eligible ally must join its leader's war side deterministically")
	_require(String((world.war_registry[war_id]["war_goal"] as Dictionary)["type"]) == "conquer_province", "the initial war goal must be conquest")

	scheduler.submit(MoveArmyCommandScript.new("a_CAS", CEUTA, "CAS"))
	scheduler.process_commands()
	var guard := 0
	while _active_battle_count(world, war_id) == 0 and guard < 40:
		scheduler.advance_one_day()
		guard += 1
	_require(battle_started_count[0] == 1, "opposing armies meeting must begin a battle")
	_require(_active_battle_count(world, war_id) == 1, "the battle must be authoritative in WarState")
	var reinforcement := CampaignWorldState.make_army_record("a_CAS_reinforcement", "CAS", CEUTA)
	reinforcement["strength"] = 600
	reinforcement["maximum_strength"] = 600
	world.army_registry["a_CAS_reinforcement"] = reinforcement
	scheduler.advance_one_day()
	_require(battle_reinforced_count[0] == 1, "a same-side army arriving during combat must reinforce the active battle")

	# Save/load on an active combat round must preserve the exact future.
	var mid_battle_save := world.to_save_dict("phase5-test")
	var corrupted_war_save := mid_battle_save.duplicate(true)
	corrupted_war_save["war_registry"][war_id]["war_goal"]["province_id"] = 999999
	var corrupted_target := _make_world()
	_require(corrupted_target.apply_save_dict(corrupted_war_save).contains("war goal"), "malformed war references must be rejected before state mutation")
	var reloaded := _make_world()
	_require(reloaded.apply_save_dict(mid_battle_save).is_empty(), "an active battle save must load")
	var reloaded_events := SimulationEventBus.new()
	root.add_child(reloaded_events)
	var reloaded_scheduler := _make_scheduler(reloaded, reloaded_events)
	for day in range(360):
		scheduler.advance_one_day()
		reloaded_scheduler.advance_one_day()
	_require(world.checksum() == reloaded.checksum(), "battle, retreat, siege, occupation, score, and RNG must survive save/load deterministically")
	_require(_active_battle_count(world, war_id) == 0, "the battle must eventually finish")
	_require(world.get_province_owner(CEUTA) == "MOR", "occupation must not change legal ownership")
	_require(world.get_province_controller(CEUTA) == "CAS", "a successful siege must change controller")
	_require(occupation_count[0] >= 1, "occupation must publish an event")
	_require(int(world.war_registry[war_id].get("total_war_score", 0)) >= 16, "battle, occupation, and ticking score must support the war goal and money demand")

	var castile_treasury_before := int(world.country_runtime("CAS").get("treasury", 0))
	var morocco_treasury_before := int(world.country_runtime("MOR").get("treasury", 0))
	var terms := [
		{"type": "transfer_province", "province_id": CEUTA, "to": "CAS"},
		{"type": "money", "from": "MOR", "to": "CAS", "amount": 10000},
	]
	scheduler.submit(OfferPeaceCommandScript.new(war_id, "CAS", "MOR", terms))
	scheduler.process_commands()
	var offers: Dictionary = world.war_registry[war_id]["peace_offers"]
	_require(offers.size() == 1, "a valid peace offer must be stored in the war")
	var offer_id := String(offers.keys()[0])
	var pending_checksum := world.checksum()
	var pending_save := world.to_save_dict("phase5-test")
	var pending_reload := _make_world()
	_require(pending_reload.apply_save_dict(pending_save).is_empty() and pending_reload.checksum() == pending_checksum, "pending peace offers must round-trip exactly")

	scheduler.submit(AcceptPeaceCommandScript.new(war_id, offer_id, "MOR"))
	scheduler.process_commands()
	_require(String(world.war_registry[war_id]["status"]) == "ended", "accepted peace must end active hostility")
	_require(not DiplomacySystemScript.are_at_war(world, "CAS", "MOR"), "ended wars must not leave stale hostility")
	_require(world.get_province_owner(CEUTA) == "CAS" and world.get_province_controller(CEUTA) == "CAS", "peace must transfer legal ownership and clear occupation")
	_require(int(world.country_runtime("CAS").get("treasury", 0)) == castile_treasury_before + 10000, "peace money must reach the recipient")
	_require(int(world.country_runtime("MOR").get("treasury", 0)) == morocco_treasury_before - 10000, "peace money must leave the payer")
	_require(DiplomacySystemScript.has_active_truce(world, "CAS", "MOR"), "peace must create a dated truce")

	var checksum_before_blocked_war := world.checksum()
	scheduler.submit(DeclareWarCommandScript.new("MOR", "CAS", CEUTA))
	scheduler.process_commands()
	_require(world.checksum() == checksum_before_blocked_war, "a truce-blocked declaration must not mutate state")
	_require(not bool(scheduler.command_history[-1]["accepted"]) and String(scheduler.command_history[-1]["failure_reason"]).contains("truce"), "invalid declarations must explain the truce")

	world.current_day = int(DiplomacySystemScript.relation(world, "CAS", "MOR")["truce_until_day"])
	scheduler.submit(DeclareWarCommandScript.new("MOR", "CAS", CEUTA))
	scheduler.process_commands()
	var active_rematch := DiplomacySystemScript.active_war_between(world, "CAS", "MOR")
	_require(not active_rematch.is_empty() and active_rematch != war_id, "war must become legal on the exact truce-expiration day")
	scheduler.submit(OfferPeaceCommandScript.new(active_rematch, "MOR", "CAS", [{"type": "white_peace"}]))
	scheduler.process_commands()
	var rematch_offers: Dictionary = world.war_registry[active_rematch]["peace_offers"]
	var white_offer_id := String(rematch_offers.keys()[0])
	scheduler.submit(AcceptPeaceCommandScript.new(active_rematch, white_offer_id, "CAS"))
	scheduler.process_commands()
	_require(DiplomacySystemScript.country_wars(world, "CAS").is_empty(), "repeated wars and white peace must leave no stale active participant references")

	print("Phase 5 warfare test passed. war=%s battles=%d score=%d" % [war_id, battle_started_count[0], int(world.war_registry[war_id]["total_war_score"])])
	quit(0)
