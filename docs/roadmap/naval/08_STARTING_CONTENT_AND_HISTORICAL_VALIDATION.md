# 08 - Starting Content and Historical Validation

**Status:** Discovery  
**Purpose:** provide enough reviewed 1444 content to validate the system without pretending worldwide fleets are complete

## Content Principle

System completion and global historical completion are separate. G1 needs representative, source-tracked Channel and Iberian fleets. It does not require speculative naval rosters for all 1,007 countries.

Every authored row records:

- Source/provenance text or URL/reference ID.
- Evidence class: contemporary, near-period, scholarly reconstruction, later secondary, gameplay placeholder.
- Confidence.
- Researcher/reviewer and dates where the content pipeline supports them.
- Review status: unreviewed, needs revision, approved placeholder, approved historical, rejected.
- Notes explaining abstraction from historical vessel/fleet detail into game classes.

## Initial Ship Definitions

Minimum 1444 variants:

- Early heavy sailing warship/carrack family.
- Early light sailing/barque family.
- Galley family.
- Cog/transport family.

Definitions need gameplay roles first, but names, dates, relative strengths, costs, crew, and regional suitability require review. Later variants should be outlined through 1700 so IDs and upgrade chains do not dead-end, even if balance/content arrives later.

Suggested definition content waves:

1. 1444 baseline four-family variants.
2. 15th/early-16th-century upgrades needed by colonisation/trade testing.
3. 16th/17th-century variants through the current 1700 endpoint.
4. Future 1700-1821 definitions remain outside current completion.

## Port Content

### Channel acceptance region

- Key southern English and northern French ports connected to the correct Channel zones.
- At least one legal home/repair/construction port per test side.
- Port/fort/shipyard level values explicitly marked as historical or gameplay fixtures.

### Iberian integration region

- Portugal, Castile, and Aragon receive representative Atlantic/Mediterranean ports.
- Granada receives an explicit reviewed maritime capability decision.
- Gibraltar/nearby strait access and exits validate.

### Optional second validation region

Venice, Genoa, and the Ottoman interface are valuable for galley/inland-sea behaviour, but this content begins only if it does not delay Channel G1.

Derived port candidates outside these regions may exist with generic capabilities, but they must be labelled generated/unreviewed and cannot be counted as historical content complete.

## Starting Countries

### England

Must support:

- At least one combat-capable fleet.
- Sufficient transport fixture for the Channel acceptance army.
- Home port, maintenance, sailor, and admiral content.
- AI ability to protect transport and contest blockade.

### France

Must support:

- A fleet capable of interception/contest without a predetermined win.
- Transport or construction capability sufficient to exercise the reverse crossing.
- Home port and repair access.

### Portugal

Must support:

- Maritime orientation and later exploration hooks.
- Representative heavy/light/transport composition.
- Atlantic supply/range test role.

### Castile

Must support:

- Atlantic and Mediterranean decision pressure where geography permits.
- Transport and combat fixture.
- Later colonisation/trade hooks.

### Aragon

Must support:

- Mediterranean galley emphasis.
- Coastal transport and blockade fixture.

Initial counts are not approved until sources and balance simulations are reviewed. Tests should refer to fixture capabilities rather than fragile exact ship counts where possible.

## Admirals and Characters

- Reuse existing character records when a defensible historical naval leader exists.
- Do not invent a named historical person merely to fill a slot.
- Neutral generated/placeholder admirals require clear status and deterministic IDs/skills.
- Assignment dates, country service, life dates, traits, and roles must validate.
- Character content review must distinguish historical identity from gameplay-balanced skill values.

## Naming

- Ship names are optional for first implementation but IDs are mandatory.
- If names ship, use reviewed country/period pools with deterministic allocation and duplicate policy.
- Generic display such as `Early Carrack 1` is preferable to invented historical claims.
- Fleet names follow localisation-ready templates unless a reviewed historical formation is documented.

## Balance Baselines

Track ranges rather than one assumed perfect number:

- Starting treasury burden from navy maintenance.
- Sailor pool and recovery.
- Construction affordability/time.
- Fleet effective power by family and water type.
- Transport capacity relative to army sizes.
- Repair time after representative battle.
- Blockade power against representative Channel/Iberian ports.
- AI reserve and replacement behaviour.

Balance must not force deterministic historical winners. England-France and Mediterranean fixtures should allow different seeded outcomes within bounded plausibility.

## Content Validation

Automated checks:

- Known country, province/port, character, and ship-definition IDs.
- Port is valid coastal land with legal exit.
- Starting fleet location and home port are legal.
- Every ship belongs to exactly one starting fleet.
- Definition is unlocked at the start date.
- Commander is alive, eligible, and not assigned incompatibly.
- Starting sailors/maintenance can support the fleet under approved baseline rules.
- Provenance and review status fields exist.
- No duplicate stable IDs or ship names where uniqueness is required.
- Export includes the exact content versions.

Manual review:

- Geographic port placement and exits.
- Relative regional fleet character.
- Naming/localisation quality.
- Historical claims and uncertainty language.
- Player readability of class roles.
- No unlicensed or copied third-party naval art.

## Content Deliverables

- Naval definition source file and validation report.
- Port candidate report plus Channel/Iberian override file.
- Starting-force content for the five initial countries.
- Admiral/character additions or documented placeholders.
- Provenance/review register.
- Balance fixture report with seeds and ranges.
- Export manifest/currentness test.

## Exit Gate

Starting content is G1-ready when England and France satisfy the complete Channel acceptance fixture, Portugal/Castile/Aragon exercise Atlantic/Mediterranean logistics, all rows validate and carry review status, and no placeholder is represented as final historical fact.
