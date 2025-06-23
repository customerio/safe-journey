import XCTest
@testable import SafeJourney

final class SafeJourneySyntaxTests: XCTestCase {
    
    var syntaxChecker: SafeJourneySyntaxChecker!
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        syntaxChecker = SafeJourneySyntaxChecker()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("safe-journey-syntax-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testMinimalSendableDetection() throws {
        let code = """
        class Test: @unchecked Sendable {
            var bad: String = ""
        }
        """
        
        let violations = try checkCodeWithSyntax(code)
        print("DEBUG: Found \(violations.count) violations")
        for violation in violations {
            print("DEBUG: \(violation.line): \(violation.message)")
        }
        
        // Should find 1 violation for mutable property without underscore
        XCTAssertEqual(violations.count, 1, "Should find exactly 1 violation, found \(violations.count)")
        XCTAssertTrue(violations.contains { violation in
            violation.message.contains("must use underscore prefix")
        }, "Should detect mutable property without underscore")
    }
    
    func testSyntaxCheckerBasicViolations() throws {
        let code = """
        final class BadExample: @unchecked Sendable {
            var badProperty: String = ""  // Should trigger error
            public var _publicUnderscore: String = ""  // Should trigger error
            
            public func badMethod() {
                _publicUnderscore = "test"  // Should trigger error
            }
            
            public func _publicUnderscoreMethod() {}  // Should trigger error
        }
        """
        
        let violations = try checkCodeWithSyntax(code)
        print("DEBUG: Found \(violations.count) violations in complex test")
        for violation in violations {
            print("DEBUG: \(violation.line): \(violation.message)")
        }
        
        // Should find multiple violations
        XCTAssertTrue(violations.count >= 3, "Should find multiple violations, found \(violations.count)")
        
        // Should find mutable property without underscore
        XCTAssertTrue(violations.contains { violation in
            violation.message.contains("must use underscore prefix")
        }, "Should detect mutable property without underscore")
        
        // Should find public underscore item
        XCTAssertTrue(violations.contains { violation in
            violation.message.contains("must be private")
        }, "Should detect public underscore items")
        
        // Should find direct underscore access
        XCTAssertTrue(violations.contains { violation in
            violation.message.contains("cannot directly access")
        }, "Should detect direct underscore access")
    }
    
    func testSyntaxCheckerValidCode() throws {
        let code = """
        final class GoodExample: @unchecked Sendable {
            private let queue = DispatchQueue(label: "test")
            private var _data: String = ""
            
            public func updateData(_ value: String) {
                queue.sync {
                    _data = value
                }
            }
            
            private func _helperMethod() {
                _data = "helper"
            }
        }
        """
        
        let violations = try checkCodeWithSyntax(code)
        
        // Should find no violations
        XCTAssertTrue(violations.isEmpty, "Valid code should have no violations, found: \(violations.map { $0.message })")
    }
    
    func testSyntaxCheckerCustomQueueMethods() throws {
        let customConfig = CheckerConfig(
            excludePatterns: [],
            queueWrapperMethods: ["sync", "async", "customSync"]
        )
        let customSyntaxChecker = SafeJourneySyntaxChecker(config: customConfig)
        
        let code = """
        final class CustomQueueExample: @unchecked Sendable {
            private var _data: String = ""
            
            public func updateData() {
                customSync {
                    _data = "updated"  // Should be valid with custom queue method
                }
            }
        }
        """
        
        let testFile = tempDir.appendingPathComponent("CustomQueueTest.swift")
        try code.write(to: testFile, atomically: true, encoding: .utf8)
        let violations = customSyntaxChecker.checkSingleFile(testFile.path)
        
        // Should find no violations when using custom queue method
        XCTAssertTrue(violations.isEmpty, "Custom queue method should be recognized, found: \(violations.map { $0.message })")
    }
    
    func testSyntaxCheckerUnderscoreFunctionCalls() throws {
        let code = """
        final class UnderscoreFunctionTest: @unchecked Sendable {
            private var _data: String = ""
            
            public func publicMethod() {
                print("public method")
            }
            
            private func _underscoreMethod() {
                publicMethod()  // Should trigger error - underscore calling non-underscore
            }
            
            private func _anotherUnderscoreMethod() {
                _underscoreMethod()  // Should be valid - underscore calling underscore
                print("system function")  // Should be valid - system function
            }
        }
        """
        
        let violations = try checkCodeWithSyntax(code)
        
        // Should find exactly 1 violation for underscore function calling non-underscore function
        XCTAssertEqual(violations.count, 1, "Should find exactly 1 violation for underscore function call")
        XCTAssertTrue(violations.contains { violation in
            violation.message.contains("cannot call non-underscore function 'publicMethod'")
        }, "Should detect underscore function calling non-underscore function")
    }
    
    func testSyntaxCheckerNestedQueueOperations() throws {
        let code = """
        final class NestedQueueTest: @unchecked Sendable {
            private let queue = DispatchQueue(label: "test")
            private var _data: String = ""
            
            private func _underscoreMethod() {
                queue.sync {  // Should trigger error - nested queue operation in underscore function
                    _data = "updated"
                }
            }
            
            private func _anotherUnderscoreMethod() {
                queue.async {  // Should trigger error - nested queue operation in underscore function
                    _data = "async update"
                }
            }
            
            public func validMethod() {
                queue.sync {
                    _underscoreMethod()  // Should be valid - non-underscore function using queue
                }
            }
        }
        """
        
        let violations = try checkCodeWithSyntax(code)
        
        // Should find exactly 2 violations for nested queue operations in underscore functions
        XCTAssertEqual(violations.count, 2, "Should find exactly 2 violations for nested queue operations")
        XCTAssertTrue(violations.contains { violation in
            violation.message.contains("cannot use queue operations - will cause deadlock")
        }, "Should detect nested queue operations in underscore functions")
    }
    
    func testSyntaxCheckerQueueConsistency() throws {
        let code = """
        final class QueueConsistencyTest: @unchecked Sendable {
            private let queue1 = DispatchQueue(label: "queue1")
            private let queue2 = DispatchQueue(label: "queue2")  // Multiple queues - should trigger warning
            private var _data: String = ""
            
            public func method1() {
                queue1.sync {
                    _data = "from queue1"
                }
            }
            
            public func method2() {
                queue2.sync {  // Different queue - should trigger warning
                    _data = "from queue2"
                }
            }
            
            public func method3() {
                let dynamicQueue = DispatchQueue(label: "dynamic")  // On-the-fly creation - should trigger warning
                dynamicQueue.sync {
                    _data = "dynamic"
                }
            }
        }
        """
        
        let violations = try checkCodeWithSyntax(code)
        
        // Should find violations for multiple queues and on-the-fly creation
        XCTAssertTrue(violations.count >= 1, "Should find violations for queue consistency issues")
        // Note: This is a complex rule that may require iterative implementation
    }
    
    func testSyntaxCheckerAutoQueueWrapperDetection() throws {
        let code = """
        final class AutoQueueTest: @unchecked Sendable {
            private let queue = DispatchQueue(label: "test")
            private var _data: String = ""
            
            // This method should be auto-detected as a queue wrapper
            public func safeUpdate(_ value: String) {
                queue.sync {
                    _data = value
                }
            }
            
            // This method should be auto-detected as a queue wrapper  
            public func asyncHelper(completion: @escaping () -> Void) {
                queue.async {
                    _data = "async"
                    completion()
                }
            }
            
            // This method should be treated as queue-protected automatically
            public func useAutoDetectedWrapper() {
                safeUpdate("test")  // Should NOT trigger violation - auto-detected as queue wrapper
            }
            
            public func directAccess() {
                _data = "direct"  // Should trigger violation - no queue protection
            }
        }
        """
        
        let violations = try checkCodeWithSyntax(code)
        
        // Should find exactly 1 violation for direct access, but not for the auto-detected wrapper usage
        XCTAssertEqual(violations.count, 1, "Should find exactly 1 violation for direct access")
        XCTAssertTrue(violations.contains { violation in
            violation.message.contains("directAccess") && violation.message.contains("cannot directly access")
        }, "Should detect direct access violation")
        
        // Should NOT find violations for the auto-detected queue wrapper method usage
        XCTAssertFalse(violations.contains { violation in
            violation.message.contains("safeUpdate")
        }, "Should not find violations for auto-detected queue wrapper usage")
    }
    
    // MARK: - Helper methods
    
    private func checkCodeWithSyntax(_ code: String, file: String = "TestFile.swift") throws -> [Violation] {
        let testFile = tempDir.appendingPathComponent(file)
        try code.write(to: testFile, atomically: true, encoding: .utf8)
        return syntaxChecker.checkSingleFile(testFile.path)
    }
}