import Testing
import Foundation
@testable import SafeJourney

@Suite("SafeJourney False Positive Detection Tests")
struct SafeJourneyFalsePositiveTests {
    
    // MARK: - Helper methods
    
    func checkCodeWithSyntaxChecker(_ code: String, file: String = "TestFile.swift") throws -> [Violation] {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("safe-journey-false-positive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let testFile = tempDir.appendingPathComponent(file)
        try code.write(to: testFile, atomically: true, encoding: .utf8)
        
        let checker = SafeJourneySyntaxChecker()
        return checker.checkSingleFile(testFile.path)
    }
    
    // MARK: - Custom queue wrapper auto-detection tests
    
    @Test("Custom async/sync wrappers should auto-detect and not trigger false positives")
    func customAsyncSyncWrappersShouldAutoDetect() async throws {
        let code = """
        import Foundation
        
        public final class ThreadSafeCounter: @unchecked Sendable {
            private let queue = DispatchQueue(label: "counter.queue")
            private var _count: Int = 0
            
            public func increment() {
                async {
                    self._increment()  // Should NOT trigger violation - inside auto-detected wrapper
                }
            }
            
            public func get() -> Int {
                sync {
                    return _count  // Should NOT trigger violation - inside auto-detected wrapper
                }
            }
            
            // These should be auto-detected as queue wrappers
            private func async(_ operation: @escaping () -> Void) {
                queue.async(execute: operation)
            }
            
            private func sync<T>(_ operation: () -> T) -> T {
                queue.sync(execute: operation)
            }
            
            private func _increment() {
                _count += 1
            }
        }
        """
        
        let violations = try checkCodeWithSyntaxChecker(code)
        
        // Should NOT have violations for underscore access inside auto-detected wrappers
        #expect(!violations.contains { violation in
            violation.message.contains("cannot directly access") && 
            violation.message.contains("_increment")
        })
        
        #expect(!violations.contains { violation in
            violation.message.contains("cannot directly access") && 
            violation.message.contains("_count")
        })
    }
    
    @Test("Complex auto-detected wrapper with closure parameters should work")
    func complexAutoDetectedWrapperWithClosures() async throws {
        let code = """
        import Foundation
        
        public final class EventProcessor: @unchecked Sendable {
            private let processingQueue = DispatchQueue(label: "events.queue")
            private var _events: [String] = []
            
            public func enqueue(_ event: String) {
                async {
                    self._enqueue(event)  // Should NOT trigger violation
                }
            }
            
            private func async(_ operation: @escaping () -> Void) {
                processingQueue.async(execute: operation)
            }
            
            private func _enqueue(_ event: String) {
                _events.append(event)
            }
        }
        """
        
        let violations = try checkCodeWithSyntaxChecker(code)
        
        // Should NOT have violations for underscore access inside auto-detected wrapper
        #expect(!violations.contains { violation in
            violation.message.contains("cannot directly access") && 
            violation.message.contains("_enqueue")
        })
    }
    
    @Test("Custom queue helper with parameters should auto-detect")
    func customQueueHelperWithParametersShouldAutoDetect() async throws {
        let code = """
        import Foundation
        
        public final class DataManager: @unchecked Sendable {
            private let queue = DispatchQueue(label: "data.queue")
            private var _data: [String] = []
            
            private func differentAsyncHelper(_ block: @escaping @Sendable (Date) -> Void) {
                let time = Date()
                queue.async {
                    block(time)  // Fixed: should be 'time' not 'date'
                }
            }

            public func updateWithHelper() {
                differentAsyncHelper { timestamp in 
                    print(timestamp)
                    _data.append("test")  // Should NOT trigger violation
                }
            }
        }
        """
        
        let violations = try checkCodeWithSyntaxChecker(code)
        
        // Should NOT have violations for underscore access inside auto-detected helper
        #expect(!violations.contains { violation in
            violation.message.contains("cannot directly access") && 
            violation.message.contains("_data")
        })
    }
    
    // MARK: - Duplicate violation detection tests
    
    @Test("Should not report duplicate violations for same violation")
    func shouldNotReportDuplicateViolations() async throws {
        let code = """
        import Foundation
        
        public final class TestClass: @unchecked Sendable {
            private var _data: String = ""
            
            public func badMethod() {
                _data = "test"  // Should trigger exactly ONE violation, not multiple
            }
        }
        """
        
        let violations = try checkCodeWithSyntaxChecker(code)
        
        // Filter violations related to _data access
        let dataViolations = violations.filter { violation in
            violation.message.contains("cannot directly access") && 
            violation.message.contains("_data")
        }
        
        // Should have exactly 1 violation, not duplicates
        #expect(dataViolations.count == 1)
    }
    
    @Test("Complex code should not produce duplicate violations")
    func complexCodeShouldNotProduceDuplicateViolations() async throws {
        let code = """
        import Foundation
        
        public final class ComplexClass: @unchecked Sendable {
            private let queue = DispatchQueue(label: "test.queue")
            private var _count: Int = 0
            
            public func complexMethod() {
                async {
                    self._increment()  // Should trigger exactly ONE violation per call
                }
            }
            
            public func anotherMethod() {
                async {
                    self._increment()  // Should trigger exactly ONE violation per call
                }
            }
            
            private func async(_ operation: @escaping () -> Void) {
                queue.async(execute: operation)
            }
            
            private func _increment() {
                _count += 1
            }
        }
        """
        
        let violations = try checkCodeWithSyntaxChecker(code)
        
        // Count violations for each specific method call
        let complexMethodViolations = violations.filter { violation in
            violation.line == 9  // Line with self._increment() in complexMethod
        }
        
        let anotherMethodViolations = violations.filter { violation in
            violation.line == 14  // Line with self._increment() in anotherMethod
        }
        
        // Each method should have at most 1 violation, not duplicates
        #expect(complexMethodViolations.count <= 1)
        #expect(anotherMethodViolations.count <= 1)
    }
    
    // MARK: - Edge case detection tests
    
    @Test("Valid SafeJourney pattern from GoodExample should have no violations")
    func validSafeJourneyPatternFromGoodExampleShouldHaveNoViolations() async throws {
        let code = """
        import Foundation

        public final class ThreadSafeCounter: @unchecked Sendable {
            private let queue = DispatchQueue(label: "counter.queue")
            private var _count: Int = 0
            private var _history: [Int] = []
            
            public func increment() {
                async {
                    self._increment()  // Should NOT trigger - inside auto-detected wrapper
                }
            }
            
            public func get() -> Int {
                sync {
                    return _count  // Should NOT trigger - inside auto-detected wrapper
                }
            }
            
            public func reset() {
                async {
                    self._reset()  // Should NOT trigger - inside auto-detected wrapper
                }
            }
            
            private func async(_ operation: @escaping () -> Void) {
                queue.async(execute: operation)
            }
            
            private func sync<T>(_ operation: () -> T) -> T {
                queue.sync(execute: operation)
            }
            
            private func _increment() {
                _history.append(_count)
                _count += 1
            }
            
            private func _reset() {
                _history.removeAll()
                _count = 0
            }
        }
        """
        
        let violations = try checkCodeWithSyntaxChecker(code)
        
        // Should have NO violations - this is valid SafeJourney pattern
        let underscoreAccessViolations = violations.filter { violation in
            violation.message.contains("cannot directly access")
        }
        
        #expect(underscoreAccessViolations.isEmpty)
    }
}