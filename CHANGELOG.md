# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Nothing yet

### Changed
- Nothing yet

### Deprecated
- Nothing yet

### Removed
- Nothing yet

### Fixed
- Nothing yet

### Security
- Nothing yet

## [2.0.0] - 2025-10-23

### Added
- Complete OCSP (Online Certificate Status Protocol) responder implementation
  - RFC 6960 compliant OCSP server using FastAPI
  - RESTful API with health and status endpoints
  - Integration with CRL revocation database
  - Docker support with Dockerfile and docker-compose.yaml
  - Comprehensive documentation (README, QUICKSTART, IMPLEMENTATION_NOTES)
  - Test suite (test_ocsp.sh) and example workflow (example_workflow.sh)
  - Quick start script (start.sh) for easy deployment
- Documentation restructure for better maintainability
  - Comprehensive AGENTS.md with architectural decisions
  - Consolidated documentation in docs/ directory
  - Brief README.md with references to detailed docs
  - This CHANGELOG.md following Keep a Changelog format
- Enhanced certificate generation with OCSP and CRL URLs
  - Helper functions for generating certificates with AIA and CDP extensions
  - OpenSSL-based certificate generation for X.509 extensions
  - Configuration helper script (add_ocsp_to_profiles.sh)
- Complete documentation for embedding OCSP/CRL URLs in certificates
  - Step-by-step OpenSSL instructions
  - Helper function examples for steps.sh
  - Verification and testing procedures

### Changed
- Updated README.md to be more concise with references to detailed documentation
- Certificate validity periods updated to match current industry standards (Oct 2025)
  - TLS/SSL certificates: 47 days (following CA/Browser Forum trends)
  - Email certificates: 265 days (~9 months)
- Reorganized documentation into logical topic-based files in docs/
- Improved code organization and structure for OCSP responder

### Fixed
- Documentation formatting and consistency across all files
- Cross-reference links between documentation files

## [1.5.0] - 2024 (Estimated)

### Added
- Certificate Revocation List (CRL) management system
  - crl_mk.sh script for CRL operations
  - crl_check.sh for certificate revocation checking
  - crl_test.sh for testing CRL functionality
- CRL distribution in both PEM and DER formats
- Revocation database with serial number tracking
- Support for multiple revocation reasons (keyCompromise, CACompromise, etc.)
- CRL verification and certificate status checking
- Build CA bundle script (build_ca_bundle.sh)

### Changed
- Enhanced certificate generation with better error handling
- Improved validation and expiry checking

## [1.0.0] - 2023 (Estimated)

### Added
- Initial release of demo-cfssl
- Root CA and Intermediate CA generation using CFSSL
- Host/Server certificate generation with SAN support
- S/MIME email certificate generation
- PKCS#12 export for email certificates
- Document signing with timestamps (tsa_sign.sh, tsa_verify.sh)
- HAProxy integration example
- Squid proxy configuration example
- PDF signing tool (pdf-signer/)
- Docker support for certificate generation
- Basic documentation and examples
- Test implementations (Java, Python)
- Certificate profiles (profiles.json)
- Certificate bundles (2-level and 3-level chains)

### Documentation
- README.md with basic usage instructions
- CRL_MANAGEMENT.md
- CRL_EXAMPLES.md
- ADDING_CAs.md for system integration

### Scripts
- steps.sh - Main certificate generation
- mkCert.sh - Docker-based generation
- demoHaproxy.sh - HAProxy demonstration

## [0.1.0] - 2022 (Estimated)

### Added
- Initial project structure
- Basic CA generation scripts
- Simple certificate generation examples

---

## Version Number Scheme

- **MAJOR version**: Incompatible API changes or major feature additions
- **MINOR version**: Backwards-compatible functionality additions
- **PATCH version**: Backwards-compatible bug fixes

## Links

- [Repository](https://github.com/yourusername/demo-cfssl)
- [Issues](https://github.com/yourusername/demo-cfssl/issues)
- [Documentation](docs/)

---

[Unreleased]: https://github.com/yourusername/demo-cfssl/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/yourusername/demo-cfssl/compare/v1.5.0...v2.0.0
[1.5.0]: https://github.com/yourusername/demo-cfssl/compare/v1.0.0...v1.5.0
[1.0.0]: https://github.com/yourusername/demo-cfssl/compare/v0.1.0...v1.0.0
[0.1.0]: https://github.com/yourusername/demo-cfssl/releases/tag/v0.1.0

