# Changelog

All notable changes to this project will be documented in this file.

## [1.1.0] - 2025-04-29 (Initial fork)

### Added
- Enhanced color coding for win rates with multiple thresholds:
  - Green: Win rates ≥ 5.5
  - Light Green: Win rates ≥ 5.2 and < 5.5
  - Default color: Win rates ≥ 4.8 and < 5.2
  - Light Red: Win rates ≥ 4.5 and < 4.8
  - Red: Win rates < 4.5
- Improved terminal theme compatibility by removing white color from character names
- Added support for both light and dark terminal themes

### Changed
- Modified color display logic to use awk for more reliable floating-point comparisons
- Updated character name display to use bold without color for better readability
- Self-matches (--) now display in default terminal color
- Changed win rate display format from percentages to estimated best-of-10 results (e.g., 5.5 represents 5.5 wins out of 10 matches)

## [1.0.0] - 2024-02-19
- Initial release
- Basic functionality for displaying SF6 character stats
- Support for different ranks and character-specific win rates 