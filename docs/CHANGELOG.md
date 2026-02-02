# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Nothing yet

### Changed
- Nothing yet

### Fixed
- Nothing yet

## [1.0.0] - 2026-02-02

### Added
- Initial release
- `service.sh` for property cleanup at boot_completed stage
- `customize.sh` for installation with root solution detection
- Runtime property cleanup using `resetprop --delete`
- Dynamic property discovery (catches unlisted properties)
- `/data/property/` file cleanup for persistence prevention
- Comprehensive logging to `/data/local/tmp/pihooks_remover.log`
- Log rotation (100KB max)
- Execution time tracking
- Exit codes (0=success, 1=partial, 2=resetprop missing)
- `uninstall.sh` for clean removal
- GitHub Actions CI/CD pipeline
  - Automated releases on tag push
  - ShellCheck linting
  - Build validation
  - OTA update.json generation
- Comprehensive documentation
  - User guide (README.md)
  - Technical documentation (TECHNICAL.md)
  - Changelog (CHANGELOG.md)
- MIT License

### Architecture
- Single-stage execution (boot_completed only)
- No system partition modifications
- No overlay/mount dependencies
- Universal compatibility (KernelSU, Magisk, APatch)

### Compatibility
- KernelSU: Full support
- Magisk: Full support
- APatch: Experimental support
- Android: 10+ (API 29+)
- Tested on:
  - Nothing Phone 2 (Infinity-X)

---

## Version History

| Version | Date | Highlights |
|---------|------|------------|
| 1.0.0 | 2026-02-02 | Initial release |

[Unreleased]: https://github.com/MiguVT/pihooks-remover/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/MiguVT/pihooks-remover/releases/tag/v1.0.0
