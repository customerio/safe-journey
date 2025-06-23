import Testing
import Foundation
@testable import SafeJourney

@Suite("SafeJourney Pattern Rules")
struct SafeJourneyRuleSwiftTests {
    
    // MARK: - Rule 1: All vars must be private with underscore prefix
    
    @Test("Public var without underscore should trigger error")
    func publicVarWithoutUnderscoreShouldFail() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            public var publicVar: String = ""
        }
        """
        
        let violations = try checkCode(code)
        #expect(violations.contains { violation in
            violation.message.contains("must use underscore prefix") &&
            violation.type == .error
        })
    }
    
    @Test("Internal var without underscore should trigger error")
    func internalVarWithoutUnderscoreShouldFail() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            internal var internalVar: String = ""
        }
        """
        
        let violations = try checkCode(code)
        #expect(violations.contains { violation in
            violation.message.contains("must use underscore prefix")
        })
    }
    
    @Test("Private var without underscore should trigger error")
    func privateVarWithoutUnderscoreShouldFail() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private var privateVar: String = ""
        }
        """
        
        let violations = try checkCode(code)
        #expect(violations.contains { violation in
            violation.message.contains("must use underscore prefix") &&
            violation.type == .error
        })
    }
    
    @Test("Private var with underscore should pass")
    func privateVarWithUnderscoreShouldPass() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private var _privateVar: String = ""
        }
        """
        
        let violations = try checkCode(code)
        #expect(!violations.contains { violation in
            violation.message.contains("must use underscore prefix")
        })
    }
    
    // MARK: - Rule 2: Immutable properties don't require underscore
    
    @Test("Let properties should pass without underscore")
    func letPropertiesShouldPass() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private let immutableProperty: String = ""
        }
        """
        
        let violations = try checkCode(code)
        #expect(!violations.contains { violation in
            violation.message.contains("must use underscore prefix")
        })
    }
    
    @Test("Static vars should pass without underscore")
    func staticVarsShouldPass() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            static var staticVar: String = ""
        }
        """
        
        let violations = try checkCode(code)
        #expect(!violations.contains { violation in
            violation.message.contains("must use underscore prefix")
        })
    }
    
    // MARK: - Rule 3: Underscore items must be private
    
    @Test("Public underscore function should trigger error")
    func publicUnderscoreFunctionShouldFail() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            public func _publicUnderscoreFunc() {}
        }
        """
        
        let violations = try checkCode(code)
        #expect(violations.contains { violation in
            violation.message.contains("Underscore items must be private") &&
            violation.type == .error
        })
    }
    
    @Test("Private underscore function should pass")
    func privateUnderscoreFunctionShouldPass() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private func _privateUnderscoreFunc() {}
        }
        """
        
        let violations = try checkCode(code)
        #expect(!violations.contains { violation in
            violation.message.contains("Underscore items must be private")
        })
    }
    
    // MARK: - Rule 4: Queue protection required for underscore access
    
    @Test("Direct underscore access should fail")
    func directUnderscoreAccessShouldFail() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private let queue = DispatchQueue(label: "test")
            private var _data: String = ""
            
            public func updateData() {
                _data = "new value"  // Direct access - should fail
            }
        }
        """
        
        let violations = try checkCode(code)
        #expect(violations.contains { violation in
            violation.message.contains("cannot directly access") &&
            violation.message.contains("_data") &&
            violation.type == .error
        })
    }
    
    @Test("Queue protected access should pass")
    func queueProtectedAccessShouldPass() async throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private let queue = DispatchQueue(label: "test")
            private var _data: String = ""
            
            public func updateData() {
                queue.sync {
                    _data = "new value"  // Queue protected - should pass
                }
            }
        }
        """
        
        let violations = try checkCode(code)
        #expect(!violations.contains { violation in
            violation.message.contains("cannot directly access") &&
            violation.message.contains("_data")
        })
    }
    
    // MARK: - Custom Queue Wrapper Methods
    
    @Test("Custom queue wrapper methods should be recognized")
    func customQueueWrapperMethodsShouldBeRecognized() async throws {
        let customConfig = CheckerConfig(
            excludePatterns: ["Tests"],
            queueWrapperMethods: ["asyncUtility", "syncUtility", "customAsync"]
        )
        let customChecker = SafeJourneyChecker(config: customConfig)
        
        let code = """
        final class CustomUtilityClass: @unchecked Sendable {
            private var _data: String = ""
            
            public func updateData() {
                asyncUtility {
                    self._data = "updated via asyncUtility"
                }
            }
            
            public func getData() -> String {
                syncUtility {
                    return _data
                }
            }
        }
        """
        
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("safe-journey-swift-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let testFile = tempDir.appendingPathComponent("CustomUtilityTest.swift")
        try code.write(to: testFile, atomically: true, encoding: .utf8)
        let violations = customChecker.checkSingleFile(testFile.path)
        
        #expect(!violations.contains { violation in
            violation.message.contains("cannot directly access") &&
            (violation.message.contains("_data"))
        })
    }
    
    // MARK: - SafeJourney only applies to Sendable classes
    
    @Test("Non-Sendable classes should be ignored")
    func nonSendableClassesShouldBeIgnored() async throws {
        let code = """
        class RegularClass {
            var badProperty: String = ""
            public var _publicUnderscore: String = ""
            
            public func _publicUnderscoreMethod() {
                badProperty = "test"
            }
        }
        """
        
        let violations = try checkCode(code)
        #expect(violations.isEmpty)
    }
    
    @Test("Actors should be ignored")
    func actorsShouldBeIgnored() async throws {
        let code = """
        actor TestActor: Sendable {
            var badProperty: String = ""
            public var _publicUnderscore: String = ""
            
            func _publicUnderscoreMethod() {
                badProperty = "test"
            }
        }
        """
        
        let violations = try checkCode(code)
        #expect(violations.isEmpty)
    }
    
    @Test("Structs should be ignored")
    func structsShouldBeIgnored() async throws {
        let code = """
        struct TestStruct: Sendable {
            var badProperty: String = ""
            public var _publicUnderscore: String = ""
        }
        """
        
        let violations = try checkCode(code)
        #expect(violations.isEmpty)
    }
    
    @Test("Classes should be checked")
    func classesShouldBeChecked() async throws {
        let code = """
        final class TestClass: @unchecked Sendable {
            var badProperty: String = ""
        }
        """
        
        let violations = try checkCode(code)
        #expect(!violations.isEmpty)
    }
    
    // MARK: - Complex Valid Scenario
    
    @Test("Complex valid scenario should pass")
    func complexValidScenarioShouldPass() async throws {
        let code = """
        public final class ComplexValidClass: @unchecked Sendable {
            private let queue = DispatchQueue(label: "complex.queue")
            private let immutableConfig: String
            
            private var _events: [String] = []
            private var _isProcessing: Bool = false
            private var _counter: Int = 0
            
            init(config: String) {
                self.immutableConfig = config
            }
            
            public func addEvent(_ event: String) {
                queue.sync {
                    _events.append(event)
                    _counter += 1
                    if _events.count >= 10 {
                        _processBatch()
                    }
                }
            }
            
            public func getCount() -> Int {
                queue.sync {
                    return _counter
                }
            }
            
            private func _processBatch() {
                guard !_isProcessing else { return }
                _isProcessing = true
                
                let batch = _events
                _events.removeAll()
                
                _handleEvents(batch)
                _isProcessing = false
            }
            
            private func _handleEvents(_ events: [String]) {
                _counter += events.count
            }
        }
        """
        
        let violations = try checkCode(code)
        #expect(violations.isEmpty)
    }
    
    // MARK: - Helper methods
    
    private func checkCode(_ code: String, file: String = "TestFile.swift") throws -> [Violation] {
        let checker = SafeJourneyChecker()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("safe-journey-swift-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let testFile = tempDir.appendingPathComponent(file)
        try code.write(to: testFile, atomically: true, encoding: .utf8)
        return checker.checkSingleFile(testFile.path)
    }
}