import Foundation

// ❌ BAD: Multiple SafeJourney violations
public final class UnsafeCounter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "counter.queue")
    
    // ❌ VIOLATION: Mutable property without underscore prefix
    private var count: Int = 0  // Should be _count
    
    // ❌ VIOLATION: Non-private underscore item
    public var _publicUnderscore: Int = 0  // Should be private
    
    // ❌ VIOLATION: Direct underscore access without queue protection
    public func increment() {
        _publicUnderscore += 1  // Unsafe! Should use queue.sync
    }
    
    public func get() -> Int {
        // ❌ VIOLATION: Direct access to non-underscore mutable property
        return count  // Should use queue.sync
    }
    
    // ❌ VIOLATION: Underscore function using queue operations
    private func _process() {
        queue.sync {  // Deadlock risk! Already in queue context
            _publicUnderscore = 0
        }
    }
    
    // ❌ VIOLATION: Mixing queue and direct access
    public func unsafeUpdate() {
        queue.sync {
            count += 1  // Direct access inside queue
        }
        _publicUnderscore += 1  // Direct access outside queue
    }
}

// ❌ BAD: Missing thread safety entirely
public final class CompletelyUnsafe {
    // ❌ VIOLATION: Mutable state without any protection
    public var data: [String] = []
    public var isProcessing: Bool = false
    
    public func addData(_ item: String) {
        // ❌ Race condition waiting to happen
        data.append(item)
        
        if !isProcessing {
            processData()
        }
    }
    
    private func processData() {
        isProcessing = true
        // Process data...
        data.removeAll()
        isProcessing = false
    }
}

// ❌ BAD: Inconsistent pattern application
public final class InconsistentExample: @unchecked Sendable {
    private let queue = DispatchQueue(label: "inconsistent.queue")
    
    // ✅ Good: Some properties follow the pattern
    private var _goodProperty: String = ""
    
    // ❌ Bad: Some don't
    private var badProperty: Int = 0
    
    public func goodMethod() {
        queue.sync {
            _goodProperty = "updated"
        }
    }
    
    // ❌ VIOLATION: Direct access to non-underscore property
    public func badMethod() {
        badProperty += 1  // Should use queue protection
    }
    
    // ❌ VIOLATION: Mixing protected and unprotected access
    public func mixedMethod() {
        queue.sync {
            _goodProperty = "safe"
        }
        badProperty = 42  // Unsafe!
    }
}

// ❌ BAD: Nested queue deadlock scenario
public final class DeadlockExample: @unchecked Sendable {
    private let queue = DispatchQueue(label: "deadlock.queue")
    private var _data: [String] = []
    
    public func addData(_ item: String) {
        queue.sync {
            _data.append(item)
            _processIfNeeded()  // This will deadlock!
        }
    }
    
    // ❌ VIOLATION: Underscore function calling non-underscore method
    private func _processIfNeeded() {
        if _data.count > 10 {
            processData()  // Calls non-underscore method from underscore context
        }
    }
    
    private func processData() {
        queue.sync {  // Deadlock! We're already in the queue
            _data.removeAll()
        }
    }
}

// ❌ BAD: Exposing underscore methods
public final class BadEncapsulation: @unchecked Sendable {
    private let queue = DispatchQueue(label: "bad.queue")
    private var _internalState: String = ""
    
    // ❌ VIOLATION: Exposing underscore function as public
    public func _exposedUnderscoreMethod() {
        _internalState = "modified"
    }
    
    // ❌ VIOLATION: Internal access pattern exposed
    public func directAccess() -> String {
        return _internalState  // Should use queue protection
    }
}

// ❌ BAD: Wrong access level for underscore items
class AccessLevelViolations: @unchecked Sendable {
    private let queue = DispatchQueue(label: "access.queue")
    
    // ❌ VIOLATION: Underscore property not private
    internal var _internalUnderscore: String = ""
    
    // ❌ VIOLATION: Underscore property not private
    public var _publicUnderscore: Int = 0
    
    // ❌ VIOLATION: Underscore function not private
    internal func _internalUnderscoreFunc() {
        _internalUnderscore = "bad"
    }
    
    // ❌ VIOLATION: Underscore function not private
    public func _publicUnderscoreFunc() {
        _publicUnderscore = 42
    }
}