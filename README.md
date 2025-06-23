# SafeJourney Pattern

> An elegant thread safety pattern for Swift that makes concurrency constraints visible and enforceable through naming conventions and focused static analysis.

[![Swift](https://img.shields.io/badge/Swift-5.5+-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%20%7C%20macOS%20%7C%20Linux-blue.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Quick Start

```bash
# Clone or add SafeJourney as a dependency
git clone https://github.com/customerio/safe-journey.git
cd safe-journey

# Check your Swift project
swift run sj Sources/
```

## Table of Contents

- [What is SafeJourney?](#what-is-safejourney)
- [Why Use This Pattern?](#why-use-this-pattern)
- [Pattern Rules](#pattern-rules)
- [Installation](#installation)
- [Usage](#usage)
- [Integration with CI/CD](#integration-with-cicd)
- [Examples](#examples)
- [FAQ](#faq)
- [Contributing](#contributing)

## What is SafeJourney?

SafeJourney is a basic thread safety pattern for Swift that uses visual naming conventions to make mutable state visible and provides simple static checks to maintain consistency. Originally developed by Customer.io for their mobile SDKs, it focuses on a specific pattern rather than comprehensive concurrency analysis.

**SafeJourney is not a sophisticated static analyzer** - it's a focused pattern matcher with clear limitations. It works well for teams that adopt the underscore naming convention and want basic guard rails to prevent common mistakes.

### Core Concept

By marking shared mutable state and its access paths explicitly, SafeJourney makes threading intent visible and verifiable.

```swift
public final class EventsProcessor: @unchecked Sendable {
    private let maxEventsBatchSize: Int
    private let batchSyncQueue: DispatchQueue

    // ✅ Requires protection
    private var _eventData: [[String: Any]] = []
    private var _timerCancellable: AnyCancellable?

    public func enqueue(eventPayload: [String: Any]) throws {
        async { [weak self] in
            self?._eventData.append(eventPayload)
            self?._persistEvents()
        }
    }

    private func _persistEvents() {
        storage.save(_eventData)
    }
}
```

## Why Use This Pattern?

### Thread Safety You Can See

Underscore-prefixed properties and methods make mutable state and its access constraints immediately visible in code reviews.

### Prevents Deadlocks by Design

Underscore functions never re-enter queues. Public methods enforce queue protection. This eliminates many common pitfalls in concurrent code.

### Enforceable via Basic Pattern Matching

A simple checker catches violations of the pattern within individual files. It has limitations but provides useful guard rails for teams using this convention.

### Low Friction for Teams

The pattern is simple to learn, fast to apply, and helps teams avoid subtle concurrency bugs without heavyweight solutions.

### ⚡ Performance-Efficient

DispatchQueue is a performant serial queue. SafeJourney encourages batching and queue-local operations.

## Pattern Rules

### Rule 1: Prefix Mutable State with an Underscore

```swift
// ❌ Unsafe: the need for protection is not clear
private var mutableProperty: String = ""

// ✅ Safe: clearly marked for protected access
private var _mutableProperty: String = ""
```

### Rule 2: Underscore Properties Must Be Private

```swift
// ❌ Unsafe: exposed mutable state can be misused
public var _state: String = ""

// ✅ Safe: only accessible within the class
private var _state: String = ""
```

### Rule 3: Public Methods Must Use Queue Protection

```swift
func updateState() {
    // ❌ Unsafe direct access
    _mutableProperty = "new"

    // ✅ Safe access inside queue
    queue.sync {
        _mutableProperty = "new"
    }
}
```

### Rule 4: Underscore Methods Must Not Call Non-Underscore Methods

```swift
private func _processData() {
    // ❌ Unsafe: might cause re-entry or deadlocks
    publicMethod()
    
    // ❌ Unsafe: calls to non-underscore methods in same file
    helperMethod()

    // ✅ Safe: underscore methods can call other underscore methods
    _state = "processed"
    _helperMethod()
}

// Note: SafeJourney checker only analyzes functions within the same file.
// Calls to external functions/frameworks are not analyzed (tool limitation).
```

## Installation

A convention is great till it fails due to human error. Hence a complementary static check acts as a consistent guard rail.

### Option 1: Clone Repository (Recommended)

```bash
git clone https://github.com/customerio/safe-journey.git
cd safe-journey
swift run sj
```

### Option 2: Swift Package Manager

Add SafeJourney as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/customerio/safe-journey.git", from: "1.0.0")
]
```

Then run the checker from your project root:
```bash
swift run --package-path path/to/safe-journey sj Sources/
```

## Usage

```bash
swift run sj           # Current directory
swift run sj Sources/  # Specific directory
swift run sj MyFile.swift  # Specific file
swift run sj --help    # Help menu

# Custom queue wrapper methods
swift run sj --queue-methods customAsync,safeSync Sources/

# Using configuration file
swift run sj --config safejourney.json Sources/
```

### Configuration

Create a `safejourney.json` file to customize queue wrapper methods:

```json
{
  "queueWrapperMethods": ["sync", "async", "customAsync", "safeExecute"],
  "excludePatterns": ["Tests", "Generated"]
}
```

Or pass custom methods via CLI:
```bash
swift run sj --queue-methods customAsync,differentAsyncHelper Sources/
```

### Example Output

````
🔍 SafeJourney Pattern Checker
🎯 Checking: Sources/

❌ Sources/EventProcessor.swift:45: Function 'updateState' cannot directly access _eventData. Use queue protection
   💡 Suggestion: Wrap in queue.sync { } or queue.async { }

⚠️  Sources/UserManager.swift:23: Mutable property should use underscore prefix
   💡 Suggestion: Change 'var property' to 'private var _property'

📊 Summary: 1 error, 1 warning
🚨 Fix violations before committing.

## Integration with CI/CD

### GitHub Actions

```yaml
name: Thread Safety Check
on: [push, pull_request]

jobs:
  safe-journey:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Swift
        uses: swift-actions/setup-swift@v1
        with:
          swift-version: "5.9"

      - name: Run Thread Safety Check
        run: swift run sj Sources/
```

### Pre-commit Hook

```bash
#!/bin/sh
# Ensure SafeJourney is available
if [ ! -d ".safe-journey" ]; then
    echo "📥 Cloning SafeJourney..."
    git clone https://github.com/customerio/safe-journey.git .safe-journey
fi

swift run --package-path .safe-journey sj Sources/
if [ $? -ne 0 ]; then
    echo "❌ Thread safety violations found. Please fix before committing."
    exit 1
fi
```

### Xcode Build Phase

```bash
# Ensure SafeJourney is available
if [ ! -d "${SRCROOT}/.safe-journey" ]; then
    echo "📥 Cloning SafeJourney..."
    git clone https://github.com/customerio/safe-journey.git "${SRCROOT}/.safe-journey"
fi

# Run SafeJourney checker
cd "${SRCROOT}/.safe-journey"
swift run sj "${SRCROOT}/Sources"
```

## Examples

See the `examples/` directory for complete working examples of the SafeJourney pattern.

## Limitations

SafeJourney is a **basic pattern matcher**, not a comprehensive static analyzer. Here are its intentional limitations:

### ✅ **What SafeJourney Detects**
- Underscore property access without queue protection
- Non-private underscore properties and functions  
- Underscore functions calling non-underscore functions **in the same file**
- Mutable properties without underscore prefix

### ❌ **What SafeJourney Does NOT Detect**
- Cross-file function calls (calls to external modules/frameworks are ignored)
- Complex data flow analysis
- Race conditions beyond the basic pattern
- Sophisticated concurrency issues
- System function safety (assumes system calls are safe)

### 🎯 **Design Philosophy**
SafeJourney prioritizes **simplicity and clarity** over comprehensive analysis. It's designed to catch common violations of a specific naming convention, not to solve all concurrency problems.

If you need comprehensive static analysis, consider tools like Swift's built-in concurrency checking (`-strict-concurrency=complete`) or more sophisticated analyzers.

## FAQ

### Q: Why not just use actors?

Actors are useful in isolation, but in many real-world systems, concurrency is cross-cutting. `await` boundaries introduce partial transaction points, making it hard to reason about state. SafeJourney gives finer control over execution and lets you isolate concerns cleanly.

### Q: Does this impact performance?

Not meaningfully. Serial queues are efficient and widely used in many performant applications.

### Q: How do I migrate existing code?

Start small. Apply the pattern to your most shared or error-prone classes first. Let the checker identify violations incrementally.

### Q: Can underscore methods invoke callbacks?

Yes, as long as they escape to another queue.

```swift
private func _process(completion: @escaping () -> Void, callbackQueue: DispatchQueue = .global()) {
    // work...
    callbackQueue.async {
        completion()
    }
}
```

## Contributing

We welcome contributions. See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

```bash
git clone https://github.com/customerio/safe-journey.git
cd safe-journey
./test.sh
```

## License

MIT License — see [LICENSE](LICENSE).

## Acknowledgments

Developed by Customer.io to solve production-grade concurrency challenges in their SDKs. Special thanks to the Mobile team for pioneering this effort.

---

**Ready to bring clarity and safety to your concurrency model?**

Start with the [Quick Start](#quick-start) guide above!
````
