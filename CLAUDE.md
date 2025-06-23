# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the **SafeJourney** Swift package - an elegant thread safety pattern for Swift that makes concurrency constraints visible through naming conventions, accompanied by a focused static checker. SafeJourney was developed by Customer.io to solve complex concurrency challenges in their mobile SDKs while maintaining clean, readable code.

**Current Status**: Simplified checker implementation complete. The elegant SafeJourney pattern is supported by focused static analysis with clear limitations. Prioritizes reliability and simplicity over comprehensive analysis.

## Build and Development Commands

### Building the Project
```bash
# Build the entire package
swift build

# Build in release mode
swift build -c release

# Build only the checker executable
swift build --product sj
```

### Running Tests
```bash
# Run all tests
swift test

# Run specific test targets
swift test --filter SafeJourneyFalsePositiveTests
swift test --filter SafeJourneyComplexPatternTests
swift test --filter SafeJourneySyntaxComprehensiveTests
```

### Using the Checker
```bash
# Run checker on current directory
swift run sj

# Run checker on specific path
swift run sj Sources/

# Run with help
swift run sj --help
```

## Code Architecture

### Package Structure
- **Sources/Library/**: Core library code
  - `SimpleSafeJourneyChecker`: Basic pattern matcher implementation
  - `CheckerConfig`: Configuration for queue wrapper methods and exclusions  
  - `Violation`/`ViolationType`: Violation reporting structures
- **Sources/Checker/**: Executable command-line tool (`main.swift`)
  - CLI argument parsing with simplified options
  - JSON configuration file support (`safejourney.json`)
- **tests/**: Swift Testing-based unit tests with comprehensive coverage
- **examples/**: Example Swift files and configuration files

### Core Components

#### SimpleSafeJourneyChecker
A basic pattern matcher that implements core SafeJourney naming convention checks:
1. **Rule 1**: Mutable properties must use underscore prefix (`private var _property`)
2. **Rule 2**: All underscore items must be private
3. **Rule 3**: Non-underscore functions need queue protection for underscore access
4. **Rule 4**: Underscore functions cannot call non-underscore functions (same-file only)

#### Configuration System
Simple JSON-based configuration:
```json
{
  "queueWrapperMethods": ["sync", "async", "customAsync"],
  "excludePatterns": ["Tests", "Generated"]  
}
```

### SafeJourney Pattern and Checker
The SafeJourney pattern delivers elegant thread safety through visual naming conventions. The accompanying checker provides:
- **Focused Pattern Matching**: Reliable enforcement of core SafeJourney rules
- **Same-File Analysis**: Clear scope limitation to maintain reliability  
- **User Configuration**: Custom queue wrapper methods via CLI or JSON
- **Honest Capabilities**: Transparent about what it can and cannot detect

## Integration Points

### GitHub Actions
The repository includes `action.yml` for GitHub Actions integration with configurable failure conditions and comprehensive reporting.

### Git Hooks
Pre-commit and pre-push hooks are available in `git-hooks/` directory for local development enforcement.

### Configuration Files
Simple JSON configuration files:
- `queueWrapperMethods`: Array of custom queue wrapper method names
- `excludePatterns`: File patterns to skip during checking

Example configuration:
```bash
# CLI usage
swift run sj --queue-methods customAsync,safeExecute Sources/

# JSON configuration  
swift run sj --config safejourney.json Sources/
```

## Development Workflow

### Current Implementation Status
**✅ COMPLETE**: Elegant SafeJourney pattern supported by a reliable, focused checker with clear limitations and honest capabilities.

### Key Design Decisions
1. **Simplicity over sophistication**: Basic pattern matching instead of complex analysis
2. **Same-file analysis only**: Clear limitation rather than attempting cross-file analysis  
3. **User configuration**: Explicit queue wrapper method specification
4. **Clear boundaries**: Honest about what the tool can and cannot detect

### When Modifying the Checker
1. Update `Sources/Library/SimpleSafeJourneyChecker.swift` for core functionality
2. Update `Sources/Checker/main.swift` for CLI changes
3. Add tests in `tests/` for new behavior
4. Test with example files in `examples/` directory
5. Update configuration examples

## Current Test Coverage
- **Comprehensive test suite** using Swift Testing framework
- **False positive prevention** tests to ensure reliability
- **Basic pattern coverage** for core SafeJourney rules
- **Configuration testing** for CLI and JSON options
- **Clear test boundaries** matching tool limitations