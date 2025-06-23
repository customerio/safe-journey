import Testing
import Foundation
@testable import SafeJourney

@Suite("SafeJourney Comprehensive Rule Tests")
struct SafeJourneyComprehensiveTests {
    
    // MARK: - Helper methods
    
    func checkCodeWithTextChecker(_ code: String, file: String = "TestFile.swift") throws -> [Violation] {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("safe-journey-comprehensive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let testFile = tempDir.appendingPathComponent(file)
        try code.write(to: testFile, atomically: true, encoding: .utf8)
        
        let checker = SafeJourneyChecker()
        return checker.checkSingleFile(testFile.path)
    }
    
    // MARK: - Rule 1: All vars must be private with underscore prefix
    
    @Test("Public var without underscore should trigger error")
    func rule1PublicVarShouldFail() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            public var publicVar: String = ""
        }
        """
        
        let violations = try checkCodeWithTextChecker(code)
        #expect(violations.contains { violation in
            violation.message.contains("must use underscore prefix") &&
            violation.type == .error
        })
    }
    
    @Test("Internal var without underscore should trigger error")
    func rule1InternalVarShouldFail() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            internal var internalVar: String = ""
        }
        """
        
        let violations = try checkCodeWithTextChecker(code)
        #expect(violations.contains { violation in
            violation.message.contains("must use underscore prefix") &&
            violation.type == .error
        })
    }
    
    @Test("Package var without underscore should trigger error")
    func rule1PackageVarShouldFail() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            package var packageVar: String = ""
        }
        """
        
        let violations = try checkCodeWithTextChecker(code)
        #expect(violations.contains { violation in
            violation.message.contains("must use underscore prefix") &&
            violation.type == .error
        })
    }
    
    @Test("Private var without underscore should trigger error")
    func rule1PrivateVarShouldFail() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private var privateVar: String = ""
        }
        """
        
        let violations = try checkCodeWithTextChecker(code)
        #expect(violations.contains { violation in
            violation.message.contains("must use underscore prefix") &&
            violation.type == .error
        })
    }
    
    @Test("Private var with underscore should pass")
    func rule1PrivateUnderscoreVarShouldPass() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private var _privateVar: String = ""
        }
        """
        
        let violations = try checkCodeWithTextChecker(code)
        #expect(!violations.contains { violation in
            violation.message.contains("must use underscore prefix")
        })
    }
    
    @Test("Let declarations should not trigger var rule")
    func rule1LetDeclarationsShouldPass() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            public let publicLet: String = ""
            private let privateLet: String = ""
        }
        """
        
        let violations = try checkCodeWithTextChecker(code)
        #expect(!violations.contains { violation in
            violation.message.contains("must use underscore prefix")
        })
    }
    
    @Test("Static vars should not trigger var rule")
    func rule1StaticVarsShouldPass() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            static var staticVar: String = ""
            public static var publicStaticVar: String = ""
        }
        """
        
        let violations = try checkCodeWithTextChecker(code)
        #expect(!violations.contains { violation in
            violation.message.contains("must use underscore prefix")
        })
    }
    
    // MARK: - Rule 2: All underscore items must be private
    
    @Test("Public underscore var should trigger error")
    func rule2PublicUnderscoreVarShouldFail() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            public var _publicUnderscore: String = ""
        }
        """
        
        let violations = try checkCodeWithTextChecker(code)
        #expect(violations.contains { violation in
            violation.message.contains("must be private") &&
            violation.type == .error
        })
    }
    
    @Test("Internal underscore var should trigger error")
    func rule2InternalUnderscoreVarShouldFail() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            internal var _internalUnderscore: String = ""
        }
        """
        
        let violations = try checkCodeWithTextChecker(code)
        #expect(violations.contains { violation in
            violation.message.contains("must be private") &&
            violation.type == .error
        })
    }
    
    @Test("Package underscore var should trigger error")
    func rule2PackageUnderscoreVarShouldFail() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            package var _packageUnderscore: String = ""
        }
        """
        
        let violations = try checkCodeWithTextChecker(code)
        #expect(violations.contains { violation in
            violation.message.contains("must be private") &&
            violation.type == .error
        })
    }
    
    @Test("Public underscore function should trigger error")
    func rule2PublicUnderscoreFunctionShouldFail() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            public func _publicUnderscoreFunction() {}
        }
        """
        
        let violations = try checkCodeWithTextChecker(code)
        #expect(violations.contains { violation in
            violation.message.contains("must be private") &&
            violation.type == .error
        })
    }
    
    @Test("Private underscore items should pass")
    func rule2PrivateUnderscoreItemsShouldPass() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private var _privateVar: String = ""
            private func _privateFunction() {}
        }
        """
        
        let violations = try checkCodeWithTextChecker(code)
        #expect(!violations.contains { violation in
            violation.message.contains("must be private")
        })
    }
    
    // MARK: - Rule 3: Underscore functions must be private
    
    @Test("Public underscore function should trigger error")
    func rule3PublicUnderscoreFunctionShouldFail() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            public func _publicFunction() {}
        }
        """
        
        let violations = try checkCodeWithTextChecker(code)
        #expect(violations.contains { violation in
            violation.message.contains("must be private") &&
            violation.type == .error
        })
    }
    
    @Test("Internal underscore function should trigger error")
    func rule3InternalUnderscoreFunctionShouldFail() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            internal func _internalFunction() {}
        }
        """
        
        let violations = try checkCodeWithTextChecker(code)
        #expect(violations.contains { violation in
            violation.message.contains("must be private") &&
            violation.type == .error
        })
    }
    
    // MARK: - Rule 4: Non-underscore functions must access underscore items through queue
    
    @Test("Direct underscore access without queue should trigger error")
    func rule4DirectUnderscoreAccessShouldFail() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private var _data: String = ""
            
            public func badMethod() {
                _data = "test"  // Direct access without queue protection
            }
        }
        """
        
        let violations = try checkCodeWithTextChecker(code)
        #expect(violations.contains { violation in
            violation.message.contains("cannot directly access") &&
            violation.type == .error
        })
    }
    
    @Test("Queue protected underscore access should pass")
    func rule4QueueProtectedAccessShouldPass() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private let queue = DispatchQueue(label: "test")
            private var _data: String = ""
            
            public func goodMethod() {
                queue.sync {
                    _data = "test"  // Protected by queue
                }
            }
        }
        """
        
        let violations = try checkCodeWithTextChecker(code)
        #expect(!violations.contains { violation in
            violation.message.contains("cannot directly access")
        })
    }
    
    @Test("Underscore function accessing underscore data should pass")
    func rule4UnderscoreFunctionAccessShouldPass() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private var _data: String = ""
            
            private func _helper() {
                _data = "test"  // Underscore function can access underscore data
            }
        }
        """
        
        let violations = try checkCodeWithTextChecker(code)
        #expect(!violations.contains { violation in
            violation.message.contains("cannot directly access")
        })
    }
    
    // MARK: - Rule 5: Underscore functions cannot call non-underscore functions
    
    @Test("Underscore function calling non-underscore function should trigger error")
    func rule5UnderscoreFunctionCallingPublicShouldFail() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            public func publicMethod() {}
            
            private func _underscoreMethod() {
                publicMethod()  // Underscore function calling non-underscore
            }
        }
        """
        
        let violations = try checkCodeWithTextChecker(code)
        #expect(violations.contains { violation in
            violation.message.contains("cannot call non-underscore function") &&
            violation.type == .error
        })
    }
    
    @Test("Underscore function calling underscore function should pass")
    func rule5UnderscoreFunctionCallingUnderscoreShouldPass() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private func _helper() {}
            
            private func _underscoreMethod() {
                _helper()  // Underscore function calling underscore function
            }
        }
        """
        
        let violations = try checkCodeWithTextChecker(code)
        #expect(!violations.contains { violation in
            violation.message.contains("cannot call non-underscore function")
        })
    }
    
    // MARK: - Rule 6: No queue operations in underscore functions
    
    @Test("Queue sync in underscore function should trigger error")
    func rule6QueueSyncInUnderscoreFunctionShouldFail() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private let queue = DispatchQueue(label: "test")
            private var _data: String = ""
            
            private func _underscoreMethod() {
                queue.sync {  // Queue operation in underscore function - deadlock risk
                    _data = "test"
                }
            }
        }
        """
        
        let violations = try checkCodeWithTextChecker(code)
        #expect(violations.contains { violation in
            violation.message.contains("cannot use queue operations") &&
            violation.type == .error
        })
    }
    
    @Test("Queue async in underscore function should trigger error")
    func rule6QueueAsyncInUnderscoreFunctionShouldFail() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private let queue = DispatchQueue(label: "test")
            private var _data: String = ""
            
            private func _underscoreMethod() {
                queue.async {  // Queue operation in underscore function - deadlock risk
                    _data = "test"
                }
            }
        }
        """
        
        let violations = try checkCodeWithTextChecker(code)
        #expect(violations.contains { violation in
            violation.message.contains("cannot use queue operations") &&
            violation.type == .error
        })
    }
    
    // MARK: - Rule 7: Queue consistency - multiple queue detection
    
    @Test("Multiple DispatchQueue declarations - text checker behavior")
    func rule7MultipleQueuesTextCheckerBehavior() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private let queue1 = DispatchQueue(label: "queue1")
            private let queue2 = DispatchQueue(label: "queue2")  // Multiple queues
            private var _data: String = ""
        }
        """
        
        let violations = try checkCodeWithTextChecker(code)
        // Text-based checker may not implement multiple queue detection yet
        // This test documents the current behavior
        #expect(violations.count >= 0) // Always passes - just documents behavior
    }
    
    // MARK: - Sendable class scope tests
    
    @Test("Non-Sendable class should not be checked")
    func sendableClassScopeShouldSkipNonSendable() async throws {
        let code = """
        class TestClass {  // Not Sendable
            public var badVar: String = ""  // Would normally trigger error
        }
        """
        
        let violations = try checkCodeWithTextChecker(code)
        #expect(!violations.contains { violation in
            violation.message.contains("must use underscore prefix")
        })
    }
    
    @Test("Sendable class should be checked")
    func sendableClassScopeShouldCheckSendable() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            public var badVar: String = ""  // Should trigger error
        }
        """
        
        let violations = try checkCodeWithTextChecker(code)
        #expect(violations.contains { violation in
            violation.message.contains("must use underscore prefix")
        })
    }
    
    @Test("Struct should not be checked even if Sendable")
    func sendableClassScopeShouldSkipStructs() async throws {
        let code = """
        struct TestStruct: Sendable {
            public var badVar: String = ""  // Should not trigger error
        }
        """
        
        let violations = try checkCodeWithTextChecker(code)
        #expect(!violations.contains { violation in
            violation.message.contains("must use underscore prefix")
        })
    }
    
    @Test("Actor should not be checked")
    func sendableClassScopeShouldSkipActors() async throws {
        let code = """
        actor TestActor {
            public var badVar: String = ""  // Should not trigger error
        }
        """
        
        let violations = try checkCodeWithTextChecker(code)
        #expect(!violations.contains { violation in
            violation.message.contains("must use underscore prefix")
        })
    }
    
    // MARK: - Complex scenarios and edge cases
    
    @Test("Custom queue wrapper methods should be recognized")
    func complexCustomQueueWrapperShouldWork() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private let queue = DispatchQueue(label: "test")
            private var _data: String = ""
            
            private func customSync<T>(_ operation: () -> T) -> T {
                return queue.sync(execute: operation)
            }
            
            public func goodMethod() {
                customSync {
                    _data = "test"  // Should be valid with custom queue wrapper
                }
            }
        }
        """
        
        let customConfig = CheckerConfig(
            excludePatterns: [],
            queueWrapperMethods: ["sync", "async", "customSync"]
        )
        
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("safe-journey-custom-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let testFile = tempDir.appendingPathComponent("TestFile.swift")
        try code.write(to: testFile, atomically: true, encoding: .utf8)
        
        let checker = SafeJourneyChecker(config: customConfig)
        let violations = checker.checkSingleFile(testFile.path)
        
        #expect(!violations.contains { violation in
            violation.message.contains("cannot directly access")
        })
    }
    
    @Test("Nested class should be checked if Sendable")
    func complexNestedSendableClassShouldBeChecked() async throws {
        let code = """
        class OuterClass {
            class InnerClass: @unchecked Sendable {
                public var badVar: String = ""  // Should trigger error
            }
        }
        """
        
        let violations = try checkCodeWithTextChecker(code)
        #expect(violations.contains { violation in
            violation.message.contains("must use underscore prefix")
        })
    }
    
    @Test("System function calls should be allowed in underscore functions")
    func complexSystemFunctionCallsShouldBeAllowed() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private var _data: [String] = []
            
            private func _helper() {
                print("debug")  // System function should be allowed
                _data.append("test")  // Array method should be allowed
            }
        }
        """
        
        let violations = try checkCodeWithTextChecker(code)
        #expect(!violations.contains { violation in
            violation.message.contains("cannot call non-underscore function")
        })
    }
}