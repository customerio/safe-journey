import Testing
import Foundation
@testable import SafeJourney

@Suite("SafeJourney SwiftSyntax Comprehensive Rule Tests")
struct SafeJourneySyntaxComprehensiveTests {
    
    // MARK: - Helper methods
    
    func checkCodeWithSyntaxChecker(_ code: String, file: String = "TestFile.swift") throws -> [Violation] {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("safe-journey-syntax-comprehensive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let testFile = tempDir.appendingPathComponent(file)
        try code.write(to: testFile, atomically: true, encoding: .utf8)
        
        let checker = SafeJourneySyntaxChecker()
        return checker.checkSingleFile(testFile.path)
    }
    
    // MARK: - Rule 1: All vars must be private with underscore prefix
    
    @Test("SwiftSyntax: Public var without underscore should trigger error")
    func rule1PublicVarShouldFail() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            public var publicVar: String = ""
        }
        """
        
        let violations = try checkCodeWithSyntaxChecker(code)
        #expect(violations.contains { violation in
            violation.message.contains("must use underscore prefix") &&
            violation.type == .error
        })
    }
    
    @Test("SwiftSyntax: Internal var without underscore should trigger error")
    func rule1InternalVarShouldFail() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            internal var internalVar: String = ""
        }
        """
        
        let violations = try checkCodeWithSyntaxChecker(code)
        #expect(violations.contains { violation in
            violation.message.contains("must use underscore prefix") &&
            violation.type == .error
        })
    }
    
    @Test("SwiftSyntax: Private var without underscore should trigger error")
    func rule1PrivateVarShouldFail() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private var privateVar: String = ""
        }
        """
        
        let violations = try checkCodeWithSyntaxChecker(code)
        #expect(violations.contains { violation in
            violation.message.contains("must use underscore prefix") &&
            violation.type == .error
        })
    }
    
    @Test("SwiftSyntax: Private var with underscore should pass")
    func rule1PrivateUnderscoreVarShouldPass() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private var _privateVar: String = ""
        }
        """
        
        let violations = try checkCodeWithSyntaxChecker(code)
        #expect(!violations.contains { violation in
            violation.message.contains("must use underscore prefix")
        })
    }
    
    @Test("SwiftSyntax: Let declarations should not trigger var rule")
    func rule1LetDeclarationsShouldPass() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            public let publicLet: String = ""
            private let privateLet: String = ""
        }
        """
        
        let violations = try checkCodeWithSyntaxChecker(code)
        #expect(!violations.contains { violation in
            violation.message.contains("must use underscore prefix")
        })
    }
    
    @Test("SwiftSyntax: Static vars should not trigger var rule")
    func rule1StaticVarsShouldPass() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            static var staticVar: String = ""
            public static var publicStaticVar: String = ""
        }
        """
        
        let violations = try checkCodeWithSyntaxChecker(code)
        #expect(!violations.contains { violation in
            violation.message.contains("must use underscore prefix")
        })
    }
    
    // MARK: - Rule 2: All underscore items must be private
    
    @Test("SwiftSyntax: Public underscore var should trigger error")
    func rule2PublicUnderscoreVarShouldFail() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            public var _publicUnderscore: String = ""
        }
        """
        
        let violations = try checkCodeWithSyntaxChecker(code)
        #expect(violations.contains { violation in
            violation.message.contains("must be private") &&
            violation.type == .error
        })
    }
    
    @Test("SwiftSyntax: Internal underscore var should trigger error")
    func rule2InternalUnderscoreVarShouldFail() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            internal var _internalUnderscore: String = ""
        }
        """
        
        let violations = try checkCodeWithSyntaxChecker(code)
        #expect(violations.contains { violation in
            violation.message.contains("must be private") &&
            violation.type == .error
        })
    }
    
    @Test("SwiftSyntax: Public underscore function should trigger error")
    func rule2PublicUnderscoreFunctionShouldFail() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            public func _publicUnderscoreFunction() {}
        }
        """
        
        let violations = try checkCodeWithSyntaxChecker(code)
        #expect(violations.contains { violation in
            violation.message.contains("must be private") &&
            violation.type == .error
        })
    }
    
    @Test("SwiftSyntax: Private underscore items should pass")
    func rule2PrivateUnderscoreItemsShouldPass() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private var _privateVar: String = ""
            private func _privateFunction() {}
        }
        """
        
        let violations = try checkCodeWithSyntaxChecker(code)
        #expect(!violations.contains { violation in
            violation.message.contains("must be private")
        })
    }
    
    // MARK: - Rule 3: Non-underscore functions must access underscore items through queue
    
    @Test("SwiftSyntax: Direct underscore access without queue should trigger error")
    func rule3DirectUnderscoreAccessShouldFail() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private var _data: String = ""
            
            public func badMethod() {
                _data = "test"  // Direct access without queue protection
            }
        }
        """
        
        let violations = try checkCodeWithSyntaxChecker(code)
        #expect(violations.contains { violation in
            violation.message.contains("cannot directly access") &&
            violation.type == .error
        })
    }
    
    @Test("SwiftSyntax: Queue protected underscore access should pass")
    func rule3QueueProtectedAccessShouldPass() async throws {
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
        
        let violations = try checkCodeWithSyntaxChecker(code)
        #expect(!violations.contains { violation in
            violation.message.contains("cannot directly access")
        })
    }
    
    @Test("SwiftSyntax: Underscore function accessing underscore data should pass")
    func rule3UnderscoreFunctionAccessShouldPass() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private var _data: String = ""
            
            private func _helper() {
                _data = "test"  // Underscore function can access underscore data
            }
        }
        """
        
        let violations = try checkCodeWithSyntaxChecker(code)
        #expect(!violations.contains { violation in
            violation.message.contains("cannot directly access")
        })
    }
    
    // MARK: - Rule 4: Underscore functions cannot call non-underscore functions
    
    @Test("SwiftSyntax: Underscore function calling non-underscore function should trigger error")
    func rule4UnderscoreFunctionCallingPublicShouldFail() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            public func publicMethod() {}
            
            private func _underscoreMethod() {
                publicMethod()  // Underscore function calling non-underscore
            }
        }
        """
        
        let violations = try checkCodeWithSyntaxChecker(code)
        #expect(violations.contains { violation in
            violation.message.contains("cannot call non-underscore function") &&
            violation.type == .error
        })
    }
    
    @Test("SwiftSyntax: Underscore function calling underscore function should pass")
    func rule4UnderscoreFunctionCallingUnderscoreShouldPass() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private func _helper() {}
            
            private func _underscoreMethod() {
                _helper()  // Underscore function calling underscore function
            }
        }
        """
        
        let violations = try checkCodeWithSyntaxChecker(code)
        #expect(!violations.contains { violation in
            violation.message.contains("cannot call non-underscore function")
        })
    }
    
    @Test("SwiftSyntax: System function calls should be allowed in underscore functions")
    func rule4SystemFunctionCallsShouldBeAllowed() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private var _data: [String] = []
            
            private func _helper() {
                print("debug")  // System function should be allowed
                _data.append("test")  // Array method should be allowed
            }
        }
        """
        
        let violations = try checkCodeWithSyntaxChecker(code)
        #expect(!violations.contains { violation in
            violation.message.contains("cannot call non-underscore function")
        })
    }
    
    // MARK: - Rule 5: No queue operations in underscore functions
    
    @Test("SwiftSyntax: Queue sync in underscore function should trigger error")
    func rule5QueueSyncInUnderscoreFunctionShouldFail() async throws {
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
        
        let violations = try checkCodeWithSyntaxChecker(code)
        #expect(violations.contains { violation in
            violation.message.contains("cannot use queue operations") &&
            violation.type == .error
        })
    }
    
    @Test("SwiftSyntax: Queue async in underscore function should trigger error")
    func rule5QueueAsyncInUnderscoreFunctionShouldFail() async throws {
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
        
        let violations = try checkCodeWithSyntaxChecker(code)
        #expect(violations.contains { violation in
            violation.message.contains("cannot use queue operations") &&
            violation.type == .error
        })
    }
    
    // MARK: - Rule 6: Queue consistency - multiple queue detection
    
    @Test("SwiftSyntax: Multiple DispatchQueue declarations should trigger warning")
    func rule6MultipleQueuesShouldFail() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private let queue1 = DispatchQueue(label: "queue1")
            private let queue2 = DispatchQueue(label: "queue2")  // Multiple queues
            private var _data: String = ""
        }
        """
        
        let violations = try checkCodeWithSyntaxChecker(code)
        #expect(violations.contains { violation in
            violation.message.contains("Multiple queues detected") ||
            violation.message.contains("single queue")
        })
    }
    
    // MARK: - Sendable class scope tests
    
    @Test("SwiftSyntax: Non-Sendable class should not be checked")
    func sendableClassScopeShouldSkipNonSendable() async throws {
        let code = """
        class TestClass {  // Not Sendable
            public var badVar: String = ""  // Would normally trigger error
        }
        """
        
        let violations = try checkCodeWithSyntaxChecker(code)
        #expect(!violations.contains { violation in
            violation.message.contains("must use underscore prefix")
        })
    }
    
    @Test("SwiftSyntax: Sendable class should be checked")
    func sendableClassScopeShouldCheckSendable() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            public var badVar: String = ""  // Should trigger error
        }
        """
        
        let violations = try checkCodeWithSyntaxChecker(code)
        #expect(violations.contains { violation in
            violation.message.contains("must use underscore prefix")
        })
    }
    
    @Test("SwiftSyntax: Struct should not be checked even if Sendable")
    func sendableClassScopeShouldSkipStructs() async throws {
        let code = """
        struct TestStruct: Sendable {
            public var badVar: String = ""  // Should not trigger error
        }
        """
        
        let violations = try checkCodeWithSyntaxChecker(code)
        #expect(!violations.contains { violation in
            violation.message.contains("must use underscore prefix")
        })
    }
    
    @Test("SwiftSyntax: Actor should not be checked")
    func sendableClassScopeShouldSkipActors() async throws {
        let code = """
        actor TestActor {
            public var badVar: String = ""  // Should not trigger error
        }
        """
        
        let violations = try checkCodeWithSyntaxChecker(code)
        #expect(!violations.contains { violation in
            violation.message.contains("must use underscore prefix")
        })
    }
    
    // MARK: - SwiftSyntax-specific features
    
    @Test("SwiftSyntax: Automatic queue wrapper method detection")
    func syntaxSpecificAutoQueueWrapperDetection() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private let queue = DispatchQueue(label: "test")
            private var _data: String = ""
            
            // This method should be auto-detected as a queue wrapper
            public func safeUpdate(_ value: String) {
                queue.sync {
                    _data = value
                }
            }
            
            // This should be treated as queue-protected automatically
            public func useAutoDetectedWrapper() {
                safeUpdate("test")  // Should NOT trigger violation
            }
            
            public func directAccess() {
                _data = "direct"  // Should trigger violation
            }
        }
        """
        
        let violations = try checkCodeWithSyntaxChecker(code)
        
        // Should find exactly 1 violation for direct access, not for auto-detected wrapper
        #expect(violations.count == 1)
        #expect(violations.contains { violation in
            violation.message.contains("directAccess") && violation.message.contains("cannot directly access")
        })
        #expect(!violations.contains { violation in
            violation.message.contains("safeUpdate")
        })
    }
    
    @Test("SwiftSyntax: Complex Sendable inheritance patterns")
    func syntaxSpecificSendableInheritanceDetection() async throws {
        let code = """
        class TestClassUnchecked: @unchecked Sendable {
            public var badVar1: String = ""  // Should trigger error
        }
        
        class TestClassRegular: Sendable {
            public var badVar2: String = ""  // Should trigger error
        }
        
        final class TestClassFinalSendable: @unchecked Sendable {
            public var badVar3: String = ""  // Should trigger error
        }
        """
        
        let violations = try checkCodeWithSyntaxChecker(code)
        
        // Should detect all three violations in different Sendable class patterns
        #expect(violations.count == 3)
        #expect(violations.filter { $0.message.contains("must use underscore prefix") }.count == 3)
    }
    
    @Test("SwiftSyntax: Nested class with Sendable inheritance")
    func syntaxSpecificNestedSendableClassDetection() async throws {
        let code = """
        class OuterClass {
            class InnerClass: @unchecked Sendable {
                public var badVar: String = ""  // Should trigger error
            }
            
            class AnotherInner {  // Not Sendable
                public var okVar: String = ""  // Should not trigger error
            }
        }
        """
        
        let violations = try checkCodeWithSyntaxChecker(code)
        
        // Should find exactly 1 violation from the Sendable inner class
        #expect(violations.count == 1)
        #expect(violations.contains { violation in
            violation.message.contains("must use underscore prefix")
        })
    }
    
    @Test("SwiftSyntax: Custom queue wrapper with configuration")
    func syntaxSpecificCustomQueueWrapperWithConfig() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private let queue = DispatchQueue(label: "test")
            private var _data: String = ""
            
            public func goodMethod() {
                customSync {
                    _data = "test"  // Should be valid with custom queue method
                }
            }
        }
        """
        
        let customConfig = CheckerConfig(
            excludePatterns: [],
            queueWrapperMethods: ["sync", "async", "customSync"]
        )
        
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("safe-journey-syntax-custom-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let testFile = tempDir.appendingPathComponent("TestFile.swift")
        try code.write(to: testFile, atomically: true, encoding: .utf8)
        
        let checker = SafeJourneySyntaxChecker(config: customConfig)
        let violations = checker.checkSingleFile(testFile.path)
        
        #expect(!violations.contains { violation in
            violation.message.contains("cannot directly access")
        })
    }
}