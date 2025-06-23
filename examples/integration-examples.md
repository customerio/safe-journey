# Integration Examples

This document provides practical examples for integrating the SafeJourney pattern checker into various development workflows and CI/CD pipelines. The checker provides focused static analysis to enforce SafeJourney's elegant thread safety pattern.

> **Note**: These examples show the general integration approach. You may need to adapt commands, paths, and configurations based on your specific project setup and the latest SafeJourney version.

## Table of Contents

- [GitHub Actions](#github-actions)
- [GitLab CI](#gitlab-ci)
- [Xcode Integration](#xcode-integration)
- [Pre-commit Hooks](#pre-commit-hooks)
- [SwiftLint Integration](#swiftlint-integration)
- [Fastlane Integration](#fastlane-integration)
- [Docker Integration](#docker-integration)

## GitHub Actions

### Basic Integration

```yaml
# .github/workflows/thread-safety.yml
name: Thread Safety Check

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  safe-journey:
    runs-on: ubuntu-latest
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v4
      
    - name: Setup Swift
      uses: swift-actions/setup-swift@v1
      with:
        swift-version: "5.9"
        
    - name: Clone SafeJourney
      run: git clone https://github.com/customerio/safe-journey.git .safe-journey
    
    - name: Run Thread Safety Check
      run: swift run --package-path .safe-journey sj Sources/
```

### Advanced Integration with Custom Config

```yaml
# .github/workflows/thread-safety-advanced.yml
name: Advanced Thread Safety Check

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  safe-journey:
    runs-on: ubuntu-latest
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v4
      
    - name: Setup Swift
      uses: swift-actions/setup-swift@v1
      with:
        swift-version: "5.9"
    
    - name: Clone SafeJourney
      run: git clone https://github.com/customerio/safe-journey.git .safe-journey
    
    - name: Create configuration
      run: |
        cat > safejourney.json << EOF
        {
          "queueWrapperMethods": ["sync", "async", "customAsync", "safeExecute"],
          "excludePatterns": ["Tests", "Mock", "Example"]
        }
        EOF
    
    - name: Run Thread Safety Check
      run: swift run --package-path .safe-journey sj --config safejourney.json Sources/
      
    - name: Upload results as artifact
      if: failure()
      uses: actions/upload-artifact@v3
      with:
        name: thread-safety-violations
        path: |
          safe-journey-violations.log
```

### Matrix Testing Across Swift Versions

```yaml
# .github/workflows/thread-safety-matrix.yml
name: Thread Safety Matrix

on: [push, pull_request]

jobs:
  test:
    strategy:
      matrix:
        swift-version: ["5.7", "5.8", "5.9"]
        config: ["strict", "permissive"]
        
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Setup Swift ${{ matrix.swift-version }}
      uses: swift-actions/setup-swift@v1
      with:
        swift-version: ${{ matrix.swift-version }}
    
    - name: Clone SafeJourney
      run: git clone https://github.com/customerio/safe-journey.git .safe-journey
      
    - name: Copy config
      run: cp .safe-journey/examples/${{ matrix.config }}-config.json safejourney.json
    
    - name: Run checks
      run: swift run --package-path .safe-journey sj --config safejourney.json Sources/
```

## GitLab CI

### Basic GitLab CI Integration

```yaml
# .gitlab-ci.yml
stages:
  - lint
  - test

thread-safety-check:
  stage: lint
  image: swift:5.9
  
  script:
    - git clone https://github.com/customerio/safe-journey.git .safe-journey
    - swift run --package-path .safe-journey sj Sources/
  
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
```

### Advanced GitLab Integration with Artifacts

```yaml
# .gitlab-ci.yml
thread-safety-advanced:
  stage: lint
  image: swift:5.9
  
  before_script:
    - git clone https://github.com/customerio/safe-journey.git .safe-journey
  
  script:
    - swift run --package-path .safe-journey sj Sources/ > thread-safety-report.txt 2>&1 || true
    - cat thread-safety-report.txt
    - if grep -q "❌" thread-safety-report.txt; then exit 1; fi
  
  artifacts:
    reports:
      junit: thread-safety-report.xml
    paths:
      - thread-safety-report.txt
    expire_in: 1 week
    when: always
```

## Xcode Integration

### Build Phase Script

Add this as a "Run Script" build phase in your Xcode project:

```bash
#!/bin/bash

# SafeJourney Thread Safety Check
# Add this as a Run Script build phase

SAFEJOURNEY_PATH="${SRCROOT}/.safe-journey"
CONFIG_PATH="${SRCROOT}/safejourney.json"

# Clone SafeJourney if it doesn't exist
if [ ! -d "$SAFEJOURNEY_PATH" ]; then
    echo "Cloning SafeJourney..."
    git clone https://github.com/customerio/safe-journey.git "$SAFEJOURNEY_PATH"
fi

# Run the checker
echo "Running SafeJourney thread safety check..."

cd "$SAFEJOURNEY_PATH"
if [ -f "$CONFIG_PATH" ]; then
    swift run sj --config "$CONFIG_PATH" "${SRCROOT}/Sources"
else
    swift run sj "${SRCROOT}/Sources"
fi

# Exit with error code if violations found
if [ $? -ne 0 ]; then
    echo "error: Thread safety violations found. Please fix before building."
    exit 1
fi

echo "✅ Thread safety check passed!"
```

### Scheme-based Integration

Add to your scheme's build pre-actions:

```bash
# Pre-action script for Xcode scheme
cd "${SRCROOT}"

if [ ! -d ".safe-journey" ]; then
    git clone https://github.com/customerio/safe-journey.git .safe-journey
fi

cd .safe-journey
swift run sj "${SRCROOT}/Sources"
```

## Pre-commit Hooks

### Git Pre-commit Hook

Create `.git/hooks/pre-commit`:

```bash
#!/bin/sh
# Git pre-commit hook for SafeJourney

echo "🔍 Running SafeJourney thread safety check..."

# Download checker if not present
if [ ! -f "safe-journey-checker.swift" ]; then
    echo "Downloading SafeJourney checker..."
    curl -O https://raw.githubusercontent.com/customerio/safe-journey/main/src/safe-journey-checker.swift
    chmod +x safe-journey-checker.swift
fi

# Run the checker on staged Swift files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.swift$')

if [ -n "$STAGED_FILES" ]; then
    # Check entire Sources directory for context
    ./safe-journey-checker.swift Sources/
    
    if [ $? -ne 0 ]; then
        echo ""
        echo "❌ Thread safety violations found in staged files."
        echo "Please fix the violations before committing."
        echo ""
        exit 1
    fi
fi

echo "✅ Thread safety check passed!"
```

### Pre-commit Framework Integration

`.pre-commit-config.yaml`:

```yaml
repos:
  - repo: local
    hooks:
      - id: safe-journey
        name: SafeJourney Thread Safety Check
        entry: ./scripts/run-safe-journey.sh
        language: script
        files: '\.swift$'
        pass_filenames: false
```

`scripts/run-safe-journey.sh`:

```bash
#!/bin/bash
set -e

if [ ! -f "safe-journey-checker.swift" ]; then
    curl -O https://raw.githubusercontent.com/customerio/safe-journey/main/src/safe-journey-checker.swift
    chmod +x safe-journey-checker.swift
fi

./safe-journey-checker.swift Sources/
```

## SwiftLint Integration

### Custom SwiftLint Rule

Add to `.swiftlint.yml`:

```yaml
custom_rules:
  underscore_guards_check:
    name: "SafeJourney Pattern"
    message: "Run SafeJourney checker for comprehensive thread safety analysis"
    regex: '^class\s+\w+.*@unchecked Sendable'
    severity: warning
    
  underscore_private_only:
    name: "Underscore items must be private"
    message: "Properties and functions with underscore prefix must be private"
    regex: '^(?!.*private).*\s+(var|func)\s+_\w+'
    severity: error
    
  mutable_sendable_property:
    name: "Mutable Sendable properties should use underscore"
    message: "Mutable properties in Sendable classes should use underscore prefix"
    regex: 'class\s+\w+.*Sendable.*\n(?:.*\n)*?.*var\s+(?!_)\w+.*='
    severity: warning
```

### SwiftLint Script Integration

Create `scripts/swiftlint-with-safe-journey.sh`:

```bash
#!/bin/bash

echo "Running SwiftLint..."
swiftlint lint

echo "Running SafeJourney check..."
if [ ! -f "safe-journey-checker.swift" ]; then
    curl -O https://raw.githubusercontent.com/customerio/safe-journey/main/src/safe-journey-checker.swift
    chmod +x safe-journey-checker.swift
fi

./safe-journey-checker.swift Sources/
```

## Fastlane Integration

### Fastfile Lane

```ruby
# Fastfile
lane :check_thread_safety do
  # Download checker if needed
  unless File.exist?("safe-journey-checker.swift")
    sh("curl -O https://raw.githubusercontent.com/customerio/safe-journey/main/src/safe-journey-checker.swift")
    sh("chmod +x safe-journey-checker.swift")
  end
  
  # Run the checker
  begin
    sh("./safe-journey-checker.swift Sources/")
    UI.success("✅ Thread safety check passed!")
  rescue => ex
    UI.user_error!("❌ Thread safety violations found!")
  end
end

# Add to your existing lanes
lane :test do
  check_thread_safety
  scan
end

lane :release do
  check_thread_safety
  build_app
  upload_to_app_store
end
```

## Docker Integration

### Dockerfile for CI

```dockerfile
# Dockerfile.safe-journey
FROM swift:5.9

WORKDIR /app

# Install dependencies
RUN apt-get update && apt-get install -y curl

# Copy checker
COPY safe-journey-checker.swift /usr/local/bin/
RUN chmod +x /usr/local/bin/safe-journey-checker.swift

# Default command
CMD ["safe-journey-checker.swift", "Sources/"]
```

### Docker Compose for Development

```yaml
# docker-compose.yml
version: '3.8'

services:
  thread-safety-check:
    build:
      context: .
      dockerfile: Dockerfile.safe-journey
    volumes:
      - .:/app
    working_dir: /app
    command: ["safe-journey-checker.swift", "Sources/"]
```

### Multi-stage Build

```dockerfile
# Multi-stage Dockerfile
FROM swift:5.9 as checker

WORKDIR /tools
RUN curl -O https://raw.githubusercontent.com/customerio/safe-journey/main/src/safe-journey-checker.swift
RUN chmod +x safe-journey-checker.swift

FROM swift:5.9

COPY --from=checker /tools/safe-journey-checker.swift /usr/local/bin/

WORKDIR /app
COPY . .

RUN safe-journey-checker.swift Sources/
RUN swift build
```

## IDE Integration

### Visual Studio Code

`.vscode/tasks.json`:

```json
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "SafeJourney Check",
            "type": "shell",
            "command": "./safe-journey-checker.swift",
            "args": ["Sources/"],
            "group": "build",
            "presentation": {
                "echo": true,
                "reveal": "always",
                "focus": false,
                "panel": "shared"
            },
            "problemMatcher": {
                "owner": "safe-journey",
                "fileLocation": "relative",
                "pattern": {
                    "regexp": "^(❌|⚠️)\\s+(.+):(\\d+):\\s+(.+)$",
                    "file": 2,
                    "line": 3,
                    "message": 4
                }
            }
        }
    ]
}
```

### Vim/Neovim Integration

Add to your `.vimrc` or `init.vim`:

```vim
" SafeJourney integration
command! UnderscoreGuardsCheck !./safe-journey-checker.swift Sources/

" Auto-run on Swift file save
autocmd BufWritePost *.swift silent! UnderscoreGuardsCheck
```

## Tips for Integration

1. **Start with warnings**: Use permissive config initially, then gradually increase strictness
2. **Exclude test files**: Most projects should exclude test directories from checking
3. **Cache the checker**: Download once and reuse to improve CI performance
4. **Fail fast**: Configure CI to fail immediately on critical violations
5. **Provide context**: Include violation examples in your team documentation
6. **Monitor trends**: Track violation counts over time to measure adoption