# Grand World Documentation

This folder contains the design, production, technical, content, and quality plans for Grand World.

## Confirmed Campaign Scope

- Historical start date: 11 November 1444.
- Initial campaign endpoint: 1 January 1700.
- Future extension target: 3 January 1821.
- Initial product model: country-first, pauseable real-time grand strategy.
- Planned later layer: rulers, characters, dynasties, titles, succession, and vassals.

The 1700–1821 period is intentionally deferred until the 1444–1700 game is stable, performant, content-complete, and enjoyable.

## Documentation Map

- [Map setup guide](../MAP_SETUP.md)
- [Detailed architecture and system plan](../GRAND_STRATEGY_DEVELOPMENT_PLAN.md)
- [Roadmap index](roadmap/README.md)
- [Master production roadmap](roadmap/MASTER_ROADMAP.md)
- [Product vision and pillars](roadmap/PRODUCT_VISION.md)
- [Production framework](roadmap/PRODUCTION_FRAMEWORK.md)
- [Content pipeline](roadmap/CONTENT_PIPELINE.md)
- [1444 historical ownership policy](data/HISTORICAL_OWNERSHIP_1444.md)
- [Quality, performance, and release gates](roadmap/QA_PERFORMANCE_RELEASE_GATES.md)
- [Risk register](roadmap/RISK_REGISTER.md)

## Documentation Rules

1. The master roadmap owns milestone order and project-wide scope.
2. Phase documents own the detailed work breakdown and exit criteria for their phase.
3. The architecture plan owns technical direction and data-model guidance.
4. Cross-cutting documents own quality, performance, content, and risk standards.
5. A phase is not complete because its code exists; it is complete only when its exit criteria pass in a playable build.
6. Scope added to an active phase must identify its cost, dependency impact, and displaced work.
7. Deferred work remains visible in the backlog but does not silently enter the current milestone.
