import Foundation

// ✅ GOOD: Proper SafeJourney implementation
public final class ThreadSafeCounter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "counter.queue")
    
    // ✅ Mutable state with underscore prefix
    private var _count: Int = 0
    private var _history: [Int] = []
    
    // ✅ Public API with atomic wrapper
    public func increment() {
        async {
            self._increment()
        }
    }

    public func get() -> Int {
        sync {
            return _count
        }
    }
    
    public func getHistory() -> [Int] {
        sync {
            return _history
        }
    }
    
    public func reset() {
        async {
            self._reset()
        }
    }
    
    // ✅ Atomic wrapper functions
    private func async(_ operation: @escaping () -> Void) {
        queue.async(execute: operation)
    }
    
    private func sync<T>(_ operation: () -> T) -> T {
        queue.sync(execute: operation)
    }
    
    // ✅ Underscore functions for business logic
    private func _increment() {
        _history.append(_count)
        _count += 1
    }
    
    private func _reset() {
        _history.removeAll()
        _count = 0
    }
}

// ✅ GOOD: Event processing with batching
public final class EventProcessor: @unchecked Sendable {
    private let processingQueue = DispatchQueue(label: "events.queue")
    private let maxBatchSize: Int
    
    // ✅ Protected mutable state
    private var _events: [String] = []
    private var _isProcessing: Bool = false
    private var _processedCount: Int = 0
    
    public init(maxBatchSize: Int = 10) {
        self.maxBatchSize = maxBatchSize
    }
    
    public func enqueue(_ event: String) {
        async {
            self._enqueue(event)
        }
    }
    
    public func getProcessedCount() -> Int {
        sync {
            return _processedCount
        }
    }
    
    // ✅ Atomic wrapper with context preservation
    private func async(_ operation: @escaping () -> Void) {
        processingQueue.async(execute: operation)
    }
    
    private func sync<T>(_ operation: () -> T) -> T {
        processingQueue.sync(execute: operation)
    }
    
    // ✅ Underscore functions handle business logic
    private func _enqueue(_ event: String) {
        _events.append(event)
        
        if _events.count >= maxBatchSize && !_isProcessing {
            _processBatch()
        }
    }
    
    private func _processBatch() {
        guard !_isProcessing && !_events.isEmpty else { return }
        
        _isProcessing = true
        let batch = _events
        _events.removeAll()
        
        _handleBatch(batch)
        _isProcessing = false
    }
    
    private func _handleBatch(_ events: [String]) {
        // Process events...
        _processedCount += events.count
    }
}

// ✅ GOOD: Simple data manager
public final class UserDataManager: @unchecked Sendable {
    private let queue = DispatchQueue(label: "userdata.queue")
    
    // ✅ Underscore prefix for mutable state
    private var _currentUser: User?
    private var _preferences: [String: Any] = [:]
    
    public func setUser(_ user: User) {
        queue.sync {
            _currentUser = user
        }
    }
    
    public func getUser() -> User? {
        queue.sync {
            return _currentUser
        }
    }
    
    public func updatePreference(key: String, value: Any) {
        queue.sync {
            _preferences[key] = value
        }
    }
    
    public func getPreferences() -> [String: Any] {
        queue.sync {
            return _preferences
        }
    }
}

// Supporting types
public struct User {
    let id: String
    let name: String
}