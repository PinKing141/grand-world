# Phase 4 — Economy and Country Gameplay Loop

## Mission

Create the first repeatable strategic resource loop: provinces generate value, countries make spending decisions, construction changes future output, and armies consume limited resources.

## Production Gate

Economy Loop Gate.

## Player Outcome

The player receives monthly income and manpower, understands the ledger, constructs a building, recruits an army, pays maintenance, and experiences meaningful scarcity.

## Entry Conditions

- Movement Gate passes.
- Country and province runtime states are stable.
- Save/load supports versioned migrations.
- Monthly scheduling works.

## Design Principles

- Every number must be explainable.
- Early formulas should be simple enough to balance.
- Money and manpower should create competing priorities.
- Economic changes should be visible on the map and in the ledger.
- Use integer or fixed-point accounting for authoritative values.

## Major Deliverables

### Province Economy

Initial province values:

- Base tax.
- Base production.
- Base manpower.
- Development.
- Control.
- Unrest placeholder.
- Devastation placeholder.
- Terrain modifier.
- Resource or trade-good ID.
- Building slots.

Initial monthly outputs:

- Tax.
- Production.
- Manpower recovery contribution.

### Country Economy

Initial values:

- Treasury.
- Debt.
- Monthly income.
- Monthly expenses.
- Manpower.
- Maximum manpower.
- Army maintenance policy.

### Explainable Ledger

Income categories:

- Tax.
- Production.
- Subject income placeholder.
- Event income.

Expense categories:

- Army maintenance.
- Fort maintenance placeholder.
- Interest.
- Construction.
- Event expenses.

The ledger must expose both total and source breakdown.

### Construction

Initial building set:

- Tax building.
- Production building.
- Manpower building.

Construction rules:

- Upfront or staged cost decision.
- Build time.
- Province eligibility.
- Slot limit.
- Cancellation and refund policy.
- Completion notification.

### Recruitment

Initial unit:

- Generic levy or infantry regiment.

Recruitment rules:

- Money cost.
- Manpower cost.
- Recruitment duration.
- Province eligibility.
- Spawn province.
- Maintenance.

### Country Commands

- ConstructBuildingCommand.
- CancelConstructionCommand.
- RecruitUnitCommand.
- DisbandArmyCommand.
- SetArmyMaintenanceCommand.
- TakeLoanCommand where required.

### Economic Map Modes

- Tax.
- Production.
- Manpower.
- Development.
- Construction.

Each mode includes a legend and selected-province explanation.

### Notifications

- Building started.
- Building completed.
- Recruitment started.
- Army recruited.
- Insufficient money.
- Insufficient manpower.
- Loan taken.
- Negative monthly balance.

### Save Integration

Save:

- Treasury and debt.
- Manpower.
- Province economic values.
- Completed buildings.
- Construction queues.
- Recruitment queues.
- Maintenance settings.

## Initial Formula Direction

Keep formulas data-driven and explainable:

~~~text
province tax =
base tax
× control
× terrain modifier
× building modifier
× country modifier
× temporary modifier
~~~

~~~text
monthly country balance =
tax
+ production
+ other income
- army maintenance
- interest
- other expenses
~~~

## Acceptance Criteria

- Monthly economy fires exactly once per month.
- Province totals match the country ledger.
- The same scenario and commands produce the same economic result.
- A building can be ordered, completed, saved, and loaded.
- A recruited army appears in WorldState and on the map.
- Army maintenance affects the monthly balance.
- Insufficient resources reject commands with a clear reason.
- Economic map modes match underlying values.
- AI can query economic actions through the same APIs, even if strategic AI is not implemented yet.

## Balance Targets for the Prototype

- The player cannot build everything immediately.
- Maintaining the largest possible army prevents continuous construction.
- Losing manpower matters.
- A stronger economy provides options but does not guarantee military victory.
- The player can recover from a small mistake without restarting.

## Performance Gates

- Monthly updates operate on data arrays, not scene nodes.
- Ledger computation is cached after monthly processing.
- Map modes reuse baked province lookup data.
- Construction and recruitment queues do not require per-frame polling.

## QA Focus

- Month boundaries.
- Pausing on the last day of a month.
- Save/load before completion.
- Cancelling construction.
- Negative treasury.
- Maximum debt.
- Country losing a construction province.
- Country annexation with active queues.
- Recruitment during ownership or control changes.

## Primary Risks

- Economy becomes too complicated before warfare exists.
- Floating-point accounting creates drift.
- Ledger totals disagree with displayed sources.
- Construction ownership edge cases corrupt queues.
- Prototype balance is mistaken for final historical balance.

## Explicitly Out of Scope

- Global trade routes.
- Inflation depth.
- Complex estates.
- Detailed population classes.
- Naval economy.
- Final technology unlocks.

