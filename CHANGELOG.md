# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Checkout fetch-depth by @ilyichv

## [0.5.0] - 2026-04-14

### Added
- Add git cliff by @ilyichv

### Changed
- Update arke to v0.6.0 by @ilyichv
- Update_key which run jsonbset by @ErikFerrari
- Nested logic operators by @ilyichv

## [0.4.1] - 2025-09-08

### Fixed
- Nested filters and order by @ilyichv in [#50](https://github.com/arkemishub/arke-postgres/pull/50)

## [0.4.0] - 2025-06-03

### Added
- Add nested filters and order by @ilyichv in [#49](https://github.com/arkemishub/arke-postgres/pull/49)

### Fixed
- Gh action by @ErikFerrari in [#48](https://github.com/arkemishub/arke-postgres/pull/48)

## [0.3.7] - 2024-09-11

### Changed
- Print err by @ErikFerrari

## [0.3.6] - 2024-08-05

### Added
- Add management for adding metadata in parameter and arke manager by @vittorio-reinaudo in [#42](https://github.com/arkemishub/arke-postgres/pull/42)

### Fixed
- Default metadata init unit by @ErikFerrari in [#41](https://github.com/arkemishub/arke-postgres/pull/41)

## [0.3.5] - 2024-07-10

### Fixed
- Make handle_fiters public by @ErikFerrari in [#39](https://github.com/arkemishub/arke-postgres/pull/39)

## [0.3.4] - 2024-07-02

### Added
- Add distinct to query link by id and starting unit by @vittorio-reinaudo in [#38](https://github.com/arkemishub/arke-postgres/pull/38)

### New Contributors
* @vittorio-reinaudo made their first contribution in [#38](https://github.com/arkemishub/arke-postgres/pull/38)

## [0.3.3] - 2024-05-22

### Fixed
- Topology query distinct by @ErikFerrari in [#36](https://github.com/arkemishub/arke-postgres/pull/36)

## [0.3.2] - 2024-05-21

### Changed
- Use Arke utils for init by @ErikFerrari in [#34](https://github.com/arkemishub/arke-postgres/pull/34)
- Starting_unit in link info by @ErikFerrari in [#35](https://github.com/arkemishub/arke-postgres/pull/35)

## [0.3.1] - 2024-05-08

### Fixed
- Link query multiple id by @ErikFerrari in [#33](https://github.com/arkemishub/arke-postgres/pull/33)

## [0.3.0] - 2024-04-23

### Changed
- Set version to v0.3.0 by @ErikFerrari
- Registry file by @ErikFerrari in [#32](https://github.com/arkemishub/arke-postgres/pull/32)

### New Contributors
* @manolo-battista made their first contribution

## [0.2.11] - 2023-12-22

### Changed
- Handled `?` operator for jsonb by @dorianmercatante

## [0.2.10] - 2023-12-11

### Changed
- Set version to v0.2.10 by @ilyichv

### Fixed
- Adjust postgres datetime cast by @ilyichv in [#26](https://github.com/arkemishub/arke-postgres/pull/26)

## [0.2.9] - 2023-12-04

### Changed
- Set version to v0.2.9 by @ilyichv

### Fixed
- Metadata is not a pk in arke_link by @ilyichv in [#25](https://github.com/arkemishub/arke-postgres/pull/25)

## [0.2.8] - 2023-11-21

### Fixed
- Fixed negate filters by @dorianmercatante

## [0.2.7] - 2023-10-17

### Removed
- Removed refereces to ParamsManager by @dorianmercatante

## [0.2.6] - 2023-10-05

### Changed
- Load remote arke modules by @dorianmercatante

## [0.2.5] - 2023-08-30

### Changed
- Permission handler by @dorianmercatante

## [0.2.4] - 2023-07-11

### Changed
- Set version to v0.2.4 by @ErikFerrari
- Isnull query by @ErikFerrari in [#17](https://github.com/arkemishub/arke-postgres/pull/17)

### Fixed
- Adjust how int and floats are parsed by @ilyichv in [#16](https://github.com/arkemishub/arke-postgres/pull/16)
- Adjust how link parameters are handled by @ilyichv in [#20](https://github.com/arkemishub/arke-postgres/pull/20)
- Mix task if process already started by @ErikFerrari in [#18](https://github.com/arkemishub/arke-postgres/pull/18)

### Removed
- Remove mix env check by @ErikFerrari in [#21](https://github.com/arkemishub/arke-postgres/pull/21)

## [0.2.3] - 2023-06-28

### Changed
- Set version to v0.2.3 by @ilyichv

### Fixed
- Env test by @ErikFerrari in [#10](https://github.com/arkemishub/arke-postgres/pull/10)

## [0.2.2] - 2023-06-19

### Changed
- Set version to v0.2.2 by @ErikFerrari

### Fixed
- With filters by @ErikFerrari in [#15](https://github.com/arkemishub/arke-postgres/pull/15)

## [0.2.1] - 2023-06-15

### Changed
- Set version to v0.2.1 by @ErikFerrari

### Fixed
- Date, time and datetime query by @ErikFerrari in [#13](https://github.com/arkemishub/arke-postgres/pull/13)

## [0.2.0] - 2023-06-15

### Changed
- Set version to v0.2.0 by @ErikFerrari

### Fixed
- Date sorting by @ErikFerrari in [#11](https://github.com/arkemishub/arke-postgres/pull/11)

## [0.1.9] - 2023-06-14

### Changed
- Handle parameter_manager improvements by @dorianmercatante

### New Contributors
* @dorianmercatante made their first contribution

## [0.1.8] - 2023-06-01

### Added
- Add create project command by @ilyichv in [#7](https://github.com/arkemishub/arke-postgres/pull/7)

### Changed
- Set version to 0.1.8 by @ilyichv

## [0.1.7] - 2023-05-31

### Added
- Add arke_auth to ensure load by @ErikFerrari in [#6](https://github.com/arkemishub/arke-postgres/pull/6)

### Changed
- Set version to v0.1.7 by @ErikFerrari

## [0.1.6] - 2023-05-30

### Changed
- Set version to 0.1.6 by @ilyichv

### Fixed
- Init_db task waits for arke_auth by @ilyichv in [#5](https://github.com/arkemishub/arke-postgres/pull/5)

### New Contributors
* @ilyichv made their first contribution

## [0.1.5] - 2023-05-30

### Changed
- Set version to v0.1.5 by @ErikFerrari

### Fixed
- Init db by @ErikFerrari in [#4](https://github.com/arkemishub/arke-postgres/pull/4)

## [0.1.4] - 2023-05-19

### Changed
- Set version to v0.1.4 by @ErikFerrari

## [0.1.3] - 2023-05-19

### Added
- Add release workflow by @ErikFerrari in [#2](https://github.com/arkemishub/arke-postgres/pull/2)

### Changed
- Change release action by @ErikFerrari
- Set version to v0.1.3 by @ErikFerrari

### Fixed
- Umbrella deps by @ErikFerrari in [#3](https://github.com/arkemishub/arke-postgres/pull/3)

### New Contributors
* @ErikFerrari made their first contribution

[unreleased]: https://github.com/arkemishub/arke-postgres/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/arkemishub/arke-postgres/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/arkemishub/arke-postgres/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/arkemishub/arke-postgres/compare/v0.3.7...v0.4.0
[0.3.7]: https://github.com/arkemishub/arke-postgres/compare/v0.3.6...v0.3.7
[0.3.6]: https://github.com/arkemishub/arke-postgres/compare/v0.3.5...v0.3.6
[0.3.5]: https://github.com/arkemishub/arke-postgres/compare/v0.3.4...v0.3.5
[0.3.4]: https://github.com/arkemishub/arke-postgres/compare/v0.3.3...v0.3.4
[0.3.3]: https://github.com/arkemishub/arke-postgres/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/arkemishub/arke-postgres/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/arkemishub/arke-postgres/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/arkemishub/arke-postgres/compare/v0.2.11...v0.3.0
[0.2.11]: https://github.com/arkemishub/arke-postgres/compare/v0.2.10...v0.2.11
[0.2.10]: https://github.com/arkemishub/arke-postgres/compare/v0.2.9...v0.2.10
[0.2.9]: https://github.com/arkemishub/arke-postgres/compare/v0.2.8...v0.2.9
[0.2.8]: https://github.com/arkemishub/arke-postgres/compare/v0.2.7...v0.2.8
[0.2.7]: https://github.com/arkemishub/arke-postgres/compare/v0.2.6...v0.2.7
[0.2.6]: https://github.com/arkemishub/arke-postgres/compare/v0.2.5...v0.2.6
[0.2.5]: https://github.com/arkemishub/arke-postgres/compare/v0.2.4...v0.2.5
[0.2.4]: https://github.com/arkemishub/arke-postgres/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/arkemishub/arke-postgres/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/arkemishub/arke-postgres/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/arkemishub/arke-postgres/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/arkemishub/arke-postgres/compare/v0.1.9...v0.2.0
[0.1.9]: https://github.com/arkemishub/arke-postgres/compare/v0.1.8...v0.1.9
[0.1.8]: https://github.com/arkemishub/arke-postgres/compare/v0.1.7...v0.1.8
[0.1.7]: https://github.com/arkemishub/arke-postgres/compare/v0.1.6...v0.1.7
[0.1.6]: https://github.com/arkemishub/arke-postgres/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/arkemishub/arke-postgres/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/arkemishub/arke-postgres/compare/v0.1.3...v0.1.4

<!-- generated by git-cliff -->
