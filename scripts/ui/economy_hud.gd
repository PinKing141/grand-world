class_name EconomyHUD
extends Control

const EconomySystemScript = preload("res://scripts/simulation/economy_system.gd")
const EconomyDefinitionsScript = preload("res://scripts/simulation/economy_definitions.gd")
const SimulationDateScript = preload("res://scripts/simulation/simulation_date.gd")

@export var simulation_controller: GrandWorldSimulationController
@export var province_selector: ProvinceSelector
@export var map_hud: MapHUD
@export var notification_hud: SimulationHUD

@onready var resource_bar: PanelContainer = %ResourceBar
@onready var treasury_label: Label = %TreasuryLabel
@onready var balance_label: Label = %BalanceLabel
@onready var manpower_label: Label = %ManpowerLabel
@onready var queue_label: Label = %QueueLabel
@onready var debt_label: Label = %DebtLabel
@onready var economy_button: Button = %EconomyButton
@onready var economy_panel: PanelContainer = %EconomyPanel
@onready var economy_title: Label = %EconomyTitle
@onready var ledger_label: Label = %LedgerLabel
@onready var queue_details: Label = %QueueDetails
@onready var maintenance_option: OptionButton = %MaintenanceOption
@onready var take_loan_button: Button = %TakeLoanButton
@onready var repay_loan_button: Button = %RepayLoanButton
@onready var close_economy_button: Button = %CloseEconomyButton
@onready var province_economy_panel: PanelContainer = %ProvinceEconomyPanel
@onready var province_economy_title: Label = %ProvinceEconomyTitle
@onready var province_values: Label = %ProvinceValues
@onready var province_queue: Label = %ProvinceQueue
@onready var tax_building_button: Button = %TaxBuildingButton
@onready var workshop_button: Button = %WorkshopButton
@onready var barracks_button: Button = %BarracksButton
@onready var recruit_button: Button = %RecruitButton
@onready var cancel_construction_button: Button = %CancelConstructionButton

var _selected_province_id := -1
var _selected_owner := ""


func _ready() -> void:
	resource_bar.hide()
	economy_panel.hide()
	province_economy_panel.hide()
	for percentage in [25, 50, 75, 100]:
		maintenance_option.add_item("%d%%" % percentage)
		maintenance_option.set_item_metadata(maintenance_option.item_count - 1, percentage * 100)
	economy_button.pressed.connect(func() -> void:
		economy_panel.visible = not economy_panel.visible
		_refresh_economy_panel())
	close_economy_button.pressed.connect(economy_panel.hide)
	maintenance_option.item_selected.connect(_on_maintenance_selected)
	take_loan_button.pressed.connect(_take_loan)
	repay_loan_button.pressed.connect(_repay_first_loan)
	tax_building_button.pressed.connect(func() -> void: _construct("tax_office"))
	workshop_button.pressed.connect(func() -> void: _construct("workshop"))
	barracks_button.pressed.connect(func() -> void: _construct("barracks"))
	recruit_button.pressed.connect(_recruit)
	cancel_construction_button.pressed.connect(_cancel_selected_construction)
	%TaxMapButton.pressed.connect(func() -> void: _set_economy_map_mode("tax"))
	%ProductionMapButton.pressed.connect(func() -> void: _set_economy_map_mode("production"))
	%ManpowerMapButton.pressed.connect(func() -> void: _set_economy_map_mode("manpower"))
	%DevelopmentMapButton.pressed.connect(func() -> void: _set_economy_map_mode("development"))
	%ConstructionMapButton.pressed.connect(func() -> void: _set_economy_map_mode("construction"))
	province_selector.province_selected.connect(_on_province_selected)
	province_selector.selection_cleared.connect(func() -> void:
		_selected_province_id = -1
		province_economy_panel.hide())
	_connect_events()
	_refresh_all()


func _connect_events() -> void:
	var events := simulation_controller.event_bus
	events.player_country_changed.connect(func(_old: String, _new: String) -> void: _refresh_all())
	events.date_changed.connect(func(_day: int, _date: Dictionary) -> void:
		if province_economy_panel.visible:
			_refresh_province_panel())
	events.economy_month_processed.connect(func(_day: int) -> void:
		_notify("Monthly economy processed.")
		_refresh_all())
	events.building_started.connect(func(_id: String, _province: int, _building: String) -> void:
		_notify("Building construction started.")
		_refresh_all())
	events.building_cancelled.connect(func(_id: String, _province: int, refund: int) -> void:
		_notify("Construction cancelled · refund %s" % EconomySystemScript.format_money(refund))
		_refresh_all())
	events.building_completed.connect(func(_id: String, _province: int, building: String) -> void:
		_notify("%s completed." % EconomyDefinitionsScript.load_default().building(building).get("name", building))
		_refresh_all())
	events.recruitment_started.connect(func(_id: String, _province: int, _unit: String) -> void:
		_notify("Infantry recruitment started.")
		_refresh_all())
	events.recruitment_completed.connect(func(_id: String, _army: String, _province: int) -> void:
		_notify("Infantry regiment recruited.")
		_refresh_all())
	events.maintenance_changed.connect(func(_tag: String, _value: int) -> void: _refresh_all())
	events.loan_taken.connect(func(_id: String, _tag: String, principal: int) -> void:
		_notify("Loan taken · %s" % EconomySystemScript.format_money(principal))
		_refresh_all())
	events.loan_repaid.connect(func(_id: String, _tag: String, principal: int) -> void:
		_notify("Loan repaid · %s" % EconomySystemScript.format_money(principal))
		_refresh_all())
	events.world_reloaded.connect(func(_checksum: String) -> void: _refresh_all())


func _notify(message: String) -> void:
	if notification_hud != null:
		notification_hud._show_status(message)


func _player_country() -> String:
	return simulation_controller.world.player_country if simulation_controller.initialized else ""


func _refresh_all() -> void:
	var tag := _player_country()
	resource_bar.visible = not tag.is_empty()
	if tag.is_empty():
		economy_panel.hide()
		province_economy_panel.hide()
		return
	var runtime := simulation_controller.country_economy(tag)
	var ledger: Dictionary = runtime.get("ledger", {})
	treasury_label.text = "Treasury  %s" % EconomySystemScript.format_money(int(runtime.get("treasury", 0)))
	var balance := int(ledger.get("balance", 0))
	balance_label.text = "%s%s / month" % ["+" if balance >= 0 else "", EconomySystemScript.format_money(balance)]
	balance_label.modulate = Color("8bd49c") if balance >= 0 else Color("ef8d82")
	manpower_label.text = "Manpower  %d / %d" % [int(runtime.get("manpower", 0)), int(runtime.get("maximum_manpower", 0))]
	queue_label.text = "Build %d  ·  Recruit %d" % [_country_queue_count(tag, true), _country_queue_count(tag, false)]
	debt_label.text = "Debt  %s" % EconomySystemScript.format_money(int(runtime.get("debt", 0)))
	debt_label.visible = int(runtime.get("debt", 0)) > 0
	_refresh_economy_panel()
	_refresh_province_panel()


func _country_queue_count(tag: String, construction: bool) -> int:
	var registry := simulation_controller.world.construction_registry if construction else simulation_controller.world.recruitment_registry
	var count := 0
	for raw_id in registry:
		if String(registry[raw_id].get("country_tag", "")) == tag:
			count += 1
	return count


func _refresh_economy_panel() -> void:
	if not economy_panel.visible:
		return
	var tag := _player_country()
	if tag.is_empty():
		return
	var runtime := simulation_controller.country_economy(tag)
	var ledger: Dictionary = runtime.get("ledger", {})
	var country_name: String = simulation_controller.country_data.country_id_to_country_name.get(tag, tag)
	economy_title.text = "%s economy  ·  %s" % [country_name, tag]
	ledger_label.text = "INCOME\n  Tax                         +%s\n  Production                  +%s\n  Other                       +%s\n  Total                       +%s\n\nEXPENSES\n  Army maintenance            -%s\n  Interest                    -%s\n  Other                       -%s\n  Total                       -%s\n\nMONTHLY BALANCE               %s%s" % [
		EconomySystemScript.format_money(int(ledger.get("tax", 0))),
		EconomySystemScript.format_money(int(ledger.get("production", 0))),
		EconomySystemScript.format_money(int(ledger.get("event_income", 0))),
		EconomySystemScript.format_money(int(ledger.get("total_income", 0))),
		EconomySystemScript.format_money(int(ledger.get("army_maintenance", 0))),
		EconomySystemScript.format_money(int(ledger.get("interest", 0))),
		EconomySystemScript.format_money(int(ledger.get("event_expenses", 0))),
		EconomySystemScript.format_money(int(ledger.get("total_expenses", 0))),
		"+" if int(ledger.get("balance", 0)) >= 0 else "",
		EconomySystemScript.format_money(int(ledger.get("balance", 0))),
	]
	queue_details.text = "Treasury %s  ·  Debt %s\nConstruction projects %d  ·  Recruitments %d" % [
		EconomySystemScript.format_money(int(runtime.get("treasury", 0))),
		EconomySystemScript.format_money(int(runtime.get("debt", 0))),
		_country_queue_count(tag, true), _country_queue_count(tag, false),
	]
	var maintenance := int(runtime.get("army_maintenance_bp", 10000))
	for index in maintenance_option.item_count:
		if int(maintenance_option.get_item_metadata(index)) == maintenance:
			maintenance_option.select(index)
			break
	repay_loan_button.disabled = _first_country_loan(tag).is_empty()


func _on_province_selected(info: Dictionary) -> void:
	_selected_province_id = int(info.get("province_id", -1))
	_selected_owner = String(info.get("owner_tag", ""))
	_refresh_province_panel()


func _refresh_province_panel() -> void:
	var tag := _player_country()
	province_economy_panel.visible = _selected_province_id >= 0 and not tag.is_empty() and _selected_owner == tag
	if not province_economy_panel.visible:
		return
	var economy := simulation_controller.province_economy(_selected_province_id)
	var outputs: Dictionary = EconomySystemScript.province_outputs(economy)
	province_economy_title.text = "Province economy  ·  ID %d" % _selected_province_id
	var buildings: Array = economy.get("buildings", [])
	province_values.text = "Development %d  ·  Tax %d  Production %d  Manpower %d\n%s  ·  Control %d%%  ·  Slots %d/%d\nMonthly tax %s  ·  production %s\nManpower capacity %d\nBuildings: %s" % [
		int(economy.get("development", 0)), int(economy.get("base_tax", 0)),
		int(economy.get("base_production", 0)), int(economy.get("base_manpower", 0)),
		String(economy.get("trade_good", "unknown")).replace("_", " ").capitalize(),
		int(economy.get("control_bp", 0)) / 100, buildings.size(), int(economy.get("building_slots", 0)),
		EconomySystemScript.format_money(int(outputs["tax"])), EconomySystemScript.format_money(int(outputs["production"])),
		int(outputs["maximum_manpower"]), ", ".join(buildings) if not buildings.is_empty() else "None",
	]
	var construction_id := _construction_in_selected_province()
	cancel_construction_button.visible = not construction_id.is_empty()
	if not construction_id.is_empty():
		var record: Dictionary = simulation_controller.world.construction_registry[construction_id]
		province_queue.text = "%s completes %s" % [
			String(record["building_id"]).replace("_", " ").capitalize(),
			SimulationDateScript.format_day(int(record["completion_day"])),
		]
	else:
		province_queue.text = "No active construction."
	var owned := simulation_controller.world.get_province_owner(_selected_province_id) == tag
	for button in [tax_building_button, workshop_button, barracks_button, recruit_button]:
		button.disabled = not owned


func _construction_in_selected_province() -> String:
	var ids := simulation_controller.world.construction_registry.keys()
	ids.sort()
	for raw_id in ids:
		if int(simulation_controller.world.construction_registry[raw_id].get("province_id", -1)) == _selected_province_id:
			return String(raw_id)
	return ""


func _construct(building_id: String) -> void:
	simulation_controller.construct_building(_player_country(), _selected_province_id, building_id)


func _recruit() -> void:
	simulation_controller.recruit_unit(_player_country(), _selected_province_id)


func _cancel_selected_construction() -> void:
	var construction_id := _construction_in_selected_province()
	if not construction_id.is_empty():
		simulation_controller.cancel_construction(_player_country(), construction_id)


func _on_maintenance_selected(index: int) -> void:
	simulation_controller.set_army_maintenance(_player_country(), int(maintenance_option.get_item_metadata(index)))


func _take_loan() -> void:
	simulation_controller.take_loan(_player_country())


func _first_country_loan(tag: String) -> String:
	var ids := simulation_controller.world.loan_registry.keys()
	ids.sort()
	for raw_id in ids:
		if String(simulation_controller.world.loan_registry[raw_id].get("country_tag", "")) == tag:
			return String(raw_id)
	return ""


func _repay_first_loan() -> void:
	var loan_id := _first_country_loan(_player_country())
	if not loan_id.is_empty():
		simulation_controller.repay_loan(_player_country(), loan_id)


func _set_economy_map_mode(mode: String) -> void:
	var legends := {
		"tax": "Tax: dark provinces produce less; gold provinces produce more.",
		"production": "Production: fixed 1444 trade-good prices and local output.",
		"manpower": "Manpower: provincial military capacity.",
		"development": "Development: combined tax, production, and manpower.",
		"construction": "Construction: dark none, mid completed buildings, gold active project.",
	}
	map_hud.set_economy_map_mode(mode, legends[mode], simulation_controller.economy_map_values(mode))
