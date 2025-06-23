import XCTest
@testable import SafeJourney

final class SafeJourneyRuleTests: XCTestCase {
    
    var checker: SafeJourneyChecker!
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        checker = SafeJourneyChecker()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("safe-journey-rule-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - Rule 1: All vars must be private
    
    func testRule1_AllVarsMustBePrivate_PublicVarShouldFail() throws {
        let code = """
        class TestClass: @unchecked Sendable {
            public var publicVar: String = ""
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertTrue(violations.contains { violation in
            violation.message.contains("must use underscore prefix") &&
            violation.type == .error
        }, "Public var without underscore should trigger error")
    }
    
    func testRule1_AllVarsMustBePrivate_InternalVarShouldFail() throws {
        let code = """
        class TestClass: @unchecked Sendable {
            internal var internalVar: String = ""
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertTrue(violations.contains { violation in
            violation.message.contains("must use underscore prefix")
        }, "Internal var without underscore should trigger error")
    }
    
    func testRule1_AllVarsMustBePrivate_PrivateVarWithoutUnderscoreShouldFail() throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private var privateVar: String = ""
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertTrue(violations.contains { violation in
            violation.message.contains("must use underscore prefix") &&
            violation.type == .error
        }, "Private var without underscore should trigger error")
    }
    
    func testRule1_AllVarsMustBePrivate_PrivateVarWithUnderscoreShouldPass() throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private var _privateVar: String = ""
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertFalse(violations.contains { violation in
            violation.message.contains("must use underscore prefix")
        }, "Private var with underscore should not trigger error")
    }
    
    // MARK: - Rule 2: All vars must be prefixed with underscore
    
    func testRule2_AllVarsPrefixedWithUnderscore_LetPropertiesShouldPass() throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private let immutableProperty: String = ""
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertFalse(violations.contains { violation in
            violation.message.contains("must use underscore prefix")
        }, "Immutable let properties should not require underscore")
    }
    
    func testRule2_AllVarsPrefixedWithUnderscore_StaticVarsShouldPass() throws {
        let code = """
        class TestClass: @unchecked Sendable {
            static var staticVar: String = ""
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertFalse(violations.contains { violation in
            violation.message.contains("must use underscore prefix")
        }, "Static vars should not require underscore")
    }
    
    // MARK: - Rule 3: Any function prefixed with underscore must be private
    
    func testRule3_UnderscoreFunctionsMustBePrivate_PublicUnderscoreFunctionShouldFail() throws {
        let code = """
        class TestClass: @unchecked Sendable {
            public func _publicUnderscoreFunc() {}
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertTrue(violations.contains { violation in
            violation.message.contains("Underscore items must be private") &&
            violation.type == .error
        }, "Public underscore function should trigger error")
    }
    
    func testRule3_UnderscoreFunctionsMustBePrivate_InternalUnderscoreFunctionShouldFail() throws {
        let code = """
        class TestClass: @unchecked Sendable {
            internal func _internalUnderscoreFunc() {}
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertTrue(violations.contains { violation in
            violation.message.contains("Underscore items must be private") &&
            violation.type == .error
        }, "Internal underscore function should trigger error")
    }
    
    func testRule3_UnderscoreFunctionsMustBePrivate_PrivateUnderscoreFunctionShouldPass() throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private func _privateUnderscoreFunc() {}
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertFalse(violations.contains { violation in
            violation.message.contains("Underscore items must be private")
        }, "Private underscore function should not trigger error")
    }
    
    // MARK: - Rule 4: Non-underscore functions must access underscore items through queue
    
    func testRule4_NonUnderscoreFunctionsQueueAccess_DirectAccessShouldFail() throws {
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
        XCTAssertTrue(violations.contains { violation in
            violation.message.contains("cannot directly access") &&
            violation.message.contains("_data") &&
            violation.type == .error
        }, "Direct underscore access from non-underscore function should trigger error")
    }
    
    func testRule4_NonUnderscoreFunctionsQueueAccess_QueueProtectedAccessShouldPass() throws {
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
        XCTAssertFalse(violations.contains { violation in
            violation.message.contains("cannot directly access") &&
            violation.message.contains("_data")
        }, "Queue-protected underscore access should not trigger error")
    }
    
    func testRule4_NonUnderscoreFunctionsQueueAccess_AsyncQueueAccessShouldPass() throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private let queue = DispatchQueue(label: "test")
            private var _data: String = ""
            
            public func updateData() {
                queue.async {
                    _data = "new value"  // Async queue protected - should pass
                }
            }
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertFalse(violations.contains { violation in
            violation.message.contains("cannot directly access") &&
            violation.message.contains("_data")
        }, "Async queue-protected underscore access should not trigger error")
    }
    
    func testRule4_NonUnderscoreFunctionsQueueAccess_CallingUnderscoreFunctionDirectlyShouldFail() throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private let queue = DispatchQueue(label: "test")
            private var _data: String = ""
            
            public func updateData() {
                _processData()  // Direct call to underscore function - should fail
            }
            
            private func _processData() {
                _data = "processed"
            }
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertTrue(violations.contains { violation in
            violation.message.contains("cannot directly access") &&
            violation.message.contains("_processData") &&
            violation.type == .error
        }, "Direct call to underscore function from non-underscore function should trigger error")
    }
    
    func testRule4_NonUnderscoreFunctionsQueueAccess_CallingUnderscoreFunctionThroughQueueShouldPass() throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private let queue = DispatchQueue(label: "test")
            private var _data: String = ""
            
            public func updateData() {
                queue.sync {
                    _processData()  // Queue protected call - should pass
                }
            }
            
            private func _processData() {
                _data = "processed"
            }
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertFalse(violations.contains { violation in
            violation.message.contains("cannot directly access") &&
            violation.message.contains("_processData")
        }, "Queue-protected call to underscore function should not trigger error")
    }
    
    // MARK: - Rule 5: No non-underscore functions accessed in underscore functions
    
    func testRule5_NoNonUnderscoreFunctionsInUnderscore_DirectCallShouldFail() throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private let queue = DispatchQueue(label: "test")
            private var _data: String = ""
            
            public func publicMethod() {
                // some implementation
            }
            
            private func _processData() {
                publicMethod()  // Calling non-underscore from underscore - should fail
                _data = "processed"
            }
        }
        """
        
        let violations = try checkCode(code)
        // This should be caught by our queue deadlock detection or a specific rule
        XCTAssertTrue(violations.contains { violation in
            violation.message.contains("cannot directly access") ||
            violation.message.contains("deadlock") ||
            violation.message.contains("publicMethod")
        }, "Calling non-underscore function from underscore function should trigger error")
    }
    
    func testRule5_NoNonUnderscoreFunctionsInUnderscore_CallingOtherUnderscoreFunctionsShouldPass() throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private let queue = DispatchQueue(label: "test")
            private var _data: String = ""
            
            private func _processData() {
                _helperMethod()  // Calling underscore from underscore - should pass
                _data = "processed"
            }
            
            private func _helperMethod() {
                _data = "helper"
            }
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertFalse(violations.contains { violation in
            violation.message.contains("cannot directly access") &&
            violation.message.contains("_helperMethod")
        }, "Calling underscore function from underscore function should not trigger error")
    }
    
    // MARK: - Rule 6: No queue operations in underscore functions
    
    func testRule6_NoQueueOperationsInUnderscore_SyncOperationShouldFail() throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private let queue = DispatchQueue(label: "test")
            private var _data: String = ""
            
            private func _processData() {
                queue.sync {  // Queue operation in underscore function - should fail
                    _data = "processed"
                }
            }
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertTrue(violations.contains { violation in
            violation.message.contains("cannot use queue operations") &&
            violation.message.contains("deadlock") &&
            violation.type == .error
        }, "Queue sync operation in underscore function should trigger error")
    }
    
    func testRule6_NoQueueOperationsInUnderscore_AsyncOperationShouldFail() throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private let queue = DispatchQueue(label: "test")
            private var _data: String = ""
            
            private func _processData() {
                queue.async {  // Queue operation in underscore function - should fail
                    _data = "processed"
                }
            }
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertTrue(violations.contains { violation in
            violation.message.contains("cannot use queue operations") &&
            violation.message.contains("deadlock") &&
            violation.type == .error
        }, "Queue async operation in underscore function should trigger error")
    }
    
    func testRule6_NoQueueOperationsInUnderscore_DispatchQueueCreateShouldFail() throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private var _data: String = ""
            
            private func _processData() {
                let newQueue = DispatchQueue(label: "new")  // Creating queue - should fail
                _data = "processed"
            }
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertTrue(violations.contains { violation in
            violation.message.contains("cannot use queue operations") &&
            violation.type == .error
        }, "Creating DispatchQueue in underscore function should trigger error")
    }
    
    // MARK: - Rule 7: Multiple queue detection
    
    func testRule7_MultipleQueueDetection_DifferentQueuesForUnderscoreAccessShouldFail() throws {
        let code = """
        class TestClass: @unchecked Sendable {
            private let queue1 = DispatchQueue(label: "queue1")
            private let queue2 = DispatchQueue(label: "queue2")
            private var _data: String = ""
            
            public func updateData1() {
                queue1.sync {
                    _data = "from queue1"
                }
            }
            
            public func updateData2() {
                queue2.sync {
                    _data = "from queue2"  // Different queue accessing same underscore var
                }
            }
        }
        """
        
        let violations = try checkCode(code)
        
        // Should detect multiple queues accessing the same underscore variable
        XCTAssertTrue(violations.contains { violation in
            violation.message.contains("multiple queues") && violation.type == .error
        }, "Using different queues to access same underscore variable should trigger error")
    }
    
    // MARK: - SafeJourney only checks Sendable classes (thread safety scope)
    
    func testNonSendableClassesIgnored() throws {
        let code = """
        class RegularClass {
            var badProperty: String = ""  // Should be ignored - not Sendable
            public var _publicUnderscore: String = ""  // Should be ignored - not Sendable
            
            public func _publicUnderscoreMethod() {  // Should be ignored - not Sendable
                badProperty = "test"
            }
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertTrue(violations.isEmpty, "Non-Sendable classes should be ignored by SafeJourney pattern checker")
    }
    
    // MARK: - Complex scenarios
    
    func testComplexValidScenario() throws {
        let code = """
        public final class ComplexValidClass: @unchecked Sendable {
            private let queue = DispatchQueue(label: "complex.queue")
            private let immutableConfig: String
            
            // ✅ Proper underscore prefixed mutable state
            private var _events: [String] = []
            private var _isProcessing: Bool = false
            private var _counter: Int = 0
            
            init(config: String) {
                self.immutableConfig = config
            }
            
            // ✅ Public API with queue protection
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
            
            // ✅ Underscore functions with direct access
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
        XCTAssertTrue(violations.isEmpty, "Complex valid scenario should not produce any violations")
    }
    
    func testComplexInvalidScenario() throws {
        let code = """
        public final class ComplexInvalidClass: @unchecked Sendable {
            private let queue1 = DispatchQueue(label: "queue1")
            private let queue2 = DispatchQueue(label: "queue2")
            
            // ❌ Missing underscore prefix
            private var events: [String] = []
            // ❌ Non-private underscore item
            public var _publicCounter: Int = 0
            // ✅ Correct
            private var _isProcessing: Bool = false
            
            // ❌ Direct underscore access
            public func badMethod() {
                _publicCounter += 1
                events.append("bad")
            }
            
            // ❌ Underscore function with queue operation
            private func _badUnderscoreMethod() {
                queue1.sync {
                    _isProcessing = true
                }
            }
            
            // ❌ Non-private underscore function
            public func _publicUnderscoreMethod() {
                _isProcessing = false
            }
        }
        """
        
        let violations = try checkCode(code)
        
        // Should have multiple violations
        XCTAssertTrue(violations.count > 0, "Complex invalid scenario should produce violations")
        
        // Check for specific violation types
        XCTAssertTrue(violations.contains { $0.message.contains("must use underscore prefix") })
        XCTAssertTrue(violations.contains { $0.message.contains("must be private") })
        XCTAssertTrue(violations.contains { $0.message.contains("cannot directly access") })
        XCTAssertTrue(violations.contains { $0.message.contains("cannot use queue operations") })
    }
    
    // MARK: - SafeJourney Pattern Scope Tests (Classes Only)
    
    func testSafeJourneyPattern_OnlyAppliesToClasses_ActorsShouldBeIgnored() throws {
        let code = """
        actor TestActor: Sendable {
            var badProperty: String = ""  // Should be ignored - actors have their own safety
            public var _publicUnderscore: String = ""  // Should be ignored
            
            func _publicUnderscoreMethod() {  // Should be ignored
                badProperty = "test"
            }
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertTrue(violations.isEmpty, "Actors should be ignored by SafeJourney pattern checker")
    }
    
    func testSafeJourneyPattern_OnlyAppliesToClasses_StructsShouldBeIgnored() throws {
        let code = """
        struct TestStruct: Sendable {
            var badProperty: String = ""  // Should be ignored - structs are value types
            public var _publicUnderscore: String = ""  // Should be ignored
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertTrue(violations.isEmpty, "Structs should be ignored by SafeJourney pattern checker")
    }
    
    func testSafeJourneyPattern_OnlyAppliesToClasses_EnumsShouldBeIgnored() throws {
        let code = """
        enum TestEnum: Sendable {
            case badCase
            static var _staticUnderscore: String = ""  // Should be ignored
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertTrue(violations.isEmpty, "Enums should be ignored by SafeJourney pattern checker")
    }
    
    func testSafeJourneyPattern_OnlyAppliesToClasses_ClassesShouldBeChecked() throws {
        let code = """
        final class TestClass: @unchecked Sendable {
            var badProperty: String = ""  // Should trigger violation
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertFalse(violations.isEmpty, "Classes should be checked by SafeJourney pattern checker")
    }
    
    // MARK: - Enhanced Mutating Method Violation Detection
    
    func testMutatingMethod_CallingPublicMethod_ShouldDetectReentryRisk() throws {
        let code = """
        final class TestClass: @unchecked Sendable {
            private let queue = DispatchQueue(label: "test")
            private var _data: String = ""
            
            public func publicMethod() {
                queue.sync { _data = "public" }
            }
            
            private func _mutatingMethod() {
                _data = "direct access OK"
                publicMethod()  // ❌ Re-entry risk: public method will try to acquire same queue
            }
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertTrue(violations.contains { violation in
            violation.message.contains("cannot call non-underscore function") &&
            violation.message.contains("publicMethod") &&
            violation.message.contains("deadlock")
        }, "Mutating method calling public method should be detected as re-entry risk")
    }
    
    func testMutatingMethod_CallingInternalMethod_ShouldDetectReentryRisk() throws {
        let code = """
        final class TestClass: @unchecked Sendable {
            private let queue = DispatchQueue(label: "test")
            private var _data: String = ""
            
            internal func internalMethod() {
                // Any non-underscore method might use queue
            }
            
            private func _mutatingMethod() {
                internalMethod()  // ❌ Re-entry risk
            }
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertTrue(violations.contains { violation in
            violation.message.contains("cannot call non-underscore function") &&
            violation.message.contains("internalMethod")
        }, "Mutating method calling internal method should be detected as re-entry risk")
    }
    
    func testMutatingMethod_CallingSystemFunctions_ShouldPass() throws {
        let code = """
        final class TestClass: @unchecked Sendable {
            private var _data: [String] = []
            
            private func _mutatingMethod() {
                _data.append("test")  // ✅ System method on underscore property
                print(_data.count)    // ✅ System function
                assert(_data.isEmpty == false)  // ✅ System function
            }
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertFalse(violations.contains { violation in
            violation.message.contains("cannot call non-underscore function")
        }, "Mutating methods should be allowed to call system functions")
    }
    
    // MARK: - False Positive Regression Tests
    
    func testQueueBlockDetection_NoFalsePositiveRegression() throws {
        let code = """
        final class PreferencesManager: @unchecked Sendable {
            private let queue = DispatchQueue(label: "preferences")
            private var _preferences: [String: Any] = [:]
            
            public func updatePreference(key: String, value: Any) {
                queue.sync {
                    _preferences[key] = value  // This was causing false positive in standalone script
                }
            }
        }
        """
        
        let violations = try checkCode(code)
        
        // Should not report violations for queue-protected access
        // This test confirms the library implementation is correct (no false positive)
        XCTAssertFalse(violations.contains { violation in
            violation.message.contains("cannot directly access") &&
            violation.message.contains("_preferences")
        }, "Library should not report false positive for queue-protected underscore access (regression test for examples/GoodExample.swift:140)")
    }
    
    func testShorthandQueueMethods_ShouldRecognizeAsQueueProtection() throws {
        let code = """
        final class Counter: @unchecked Sendable {
            private var _count: Int = 0
            private var _history: [Int] = []
            
            // Custom queue wrapper methods (async/sync shorthand)
            public func increment() {
                async {
                    self._increment()  // ✅ Should be valid - inside async block
                }
            }
            
            public func get() -> Int {
                sync {
                    return _count  // ✅ Should be valid - inside sync block
                }
            }
            
            private func _increment() {
                _count += 1
                _history.append(_count)
            }
        }
        """
        
        let violations = try checkCode(code)
        
        // Should not report violations for shorthand queue methods
        XCTAssertFalse(violations.contains { violation in
            violation.message.contains("cannot directly access") &&
            (violation.message.contains("_increment") || violation.message.contains("_count"))
        }, "Shorthand async/sync blocks should be recognized as queue protection (reproduces examples/GoodExample.swift false positives)")
    }
    
    // MARK: - External Queue Dispatch Pattern Tests
    
    func testMutatingMethod_ExternalQueueDispatch_ShouldPass() throws {
        let code = """
        final class TestClass: @unchecked Sendable {
            private var _data: String = ""
            
            private func _processData(completion: @escaping () -> Void) {
                _data = "processed"
                
                // ✅ Dispatching to external queue is safe
                DispatchQueue.global().async {
                    completion()
                }
            }
        }
        """
        
        let violations = try checkCode(code)
        
        // External queue dispatch from underscore functions should be allowed
        XCTAssertTrue(violations.isEmpty, "External queue dispatch pattern should not produce violations")
    }
    
    // MARK: - Single Queue Consistency Rule Tests
    
    func testSingleQueueRule_MultipleQueuesAccessingSameProperty_ShouldFail() throws {
        let code = """
        final class TestClass: @unchecked Sendable {
            private let readQueue = DispatchQueue(label: "read")
            private let writeQueue = DispatchQueue(label: "write")
            private var _sharedData: String = ""
            
            public func readData() -> String {
                return readQueue.sync {
                    return _sharedData  // ❌ Queue 1 accessing _sharedData
                }
            }
            
            public func writeData(_ value: String) {
                writeQueue.sync {
                    _sharedData = value  // ❌ Queue 2 accessing same _sharedData
                }
            }
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertTrue(violations.contains { violation in
            violation.message.contains("multiple queues") &&
            violation.message.contains("_sharedData") &&
            violation.type == .error
        }, "Multiple queues accessing same underscore property should be detected")
    }
    
    func testSingleQueueRule_OnTheFlyQueueCreation_ShouldFail() throws {
        let code = """
        final class TestClass: @unchecked Sendable {
            private var _data: String = ""
            
            public func updateData(_ value: String) {
                // ❌ Creating queue on-the-fly violates single queue rule
                DispatchQueue(label: "temp").sync {
                    _data = value
                }
            }
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertTrue(violations.contains { violation in
            violation.message.contains("on-the-fly queue creation") &&
            violation.type == .error
        }, "On-the-fly queue creation should be detected as violation")
    }
    
    func testSingleQueueRule_GlobalQueueUsage_ShouldFail() throws {
        let code = """
        final class TestClass: @unchecked Sendable {
            private var _data: String = ""
            
            public func updateData(_ value: String) {
                // ❌ Using global queue violates single queue rule
                DispatchQueue.global().sync {
                    _data = value
                }
            }
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertTrue(violations.contains { violation in
            violation.message.contains("Use dedicated class queue") &&
            violation.type == .error
        }, "Global queue usage should be detected as violation")
    }
    
    func testSingleQueueRule_MainQueueUsage_ShouldFail() throws {
        let code = """
        final class TestClass: @unchecked Sendable {
            private var _data: String = ""
            
            public func updateData(_ value: String) {
                // ❌ Using main queue violates single queue rule
                DispatchQueue.main.sync {
                    _data = value
                }
            }
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertTrue(violations.contains { violation in
            violation.message.contains("Use dedicated class queue") &&
            violation.type == .error
        }, "Main queue usage should be detected as violation")
    }
    
    func testSingleQueueRule_ConsistentSingleQueue_ShouldPass() throws {
        let code = """
        final class TestClass: @unchecked Sendable {
            private let queue = DispatchQueue(label: "consistent.queue")
            private var _data1: String = ""
            private var _data2: Int = 0
            
            public func updateData1(_ value: String) {
                queue.sync {
                    _data1 = value  // ✅ Same queue for all access
                }
            }
            
            public func updateData2(_ value: Int) {
                queue.sync {
                    _data2 = value  // ✅ Same queue for all access
                }
            }
            
            public func combinedUpdate() {
                queue.sync {
                    _processData()  // ✅ Same queue for mutating method calls
                }
            }
            
            private func _processData() {
                _data1 = "processed"
                _data2 = 42
            }
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertFalse(violations.contains { violation in
            violation.message.contains("multiple queues") ||
            violation.message.contains("on-the-fly queue")
        }, "Consistent single queue usage should not trigger violations")
    }
    
    func testSingleQueueRule_NestedQueueWrapper_ShouldDetectInconsistency() throws {
        let code = """
        final class TestClass: @unchecked Sendable {
            private let queue1 = DispatchQueue(label: "queue1")
            private let queue2 = DispatchQueue(label: "queue2")
            private var _data: String = ""
            
            public func method1() {
                queue1.async {
                    _data = "from queue1"
                }
            }
            
            public func method2() {
                queue2.async {
                    _data = "from queue2"  // ❌ Different queue accessing same property
                }
            }
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertTrue(violations.contains { violation in
            violation.message.contains("multiple queues") &&
            violation.message.contains("_data")
        }, "Different queues accessing same property should be detected")
    }
    
    // MARK: - Complex Deadlock Scenarios
    
    func testComplexDeadlockScenario_NestedQueueOperations() throws {
        let code = """
        final class TestClass: @unchecked Sendable {
            private let queue = DispatchQueue(label: "test")
            private var _data: String = ""
            
            public func outerMethod() {
                queue.sync {
                    _innerProcessing()  // ✅ This should be fine
                }
            }
            
            private func _innerProcessing() {
                // ❌ This creates nested queue usage
                queue.sync {
                    _data = "nested"
                }
            }
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertTrue(violations.contains { violation in
            violation.message.contains("cannot use queue operations") &&
            violation.message.contains("deadlock")
        }, "Nested queue operations should be detected as deadlock risk")
    }
    
    func testComplexDeadlockScenario_IndirectPublicMethodCall() throws {
        let code = """
        final class TestClass: @unchecked Sendable {
            private let queue = DispatchQueue(label: "test")
            private var _data: String = ""
            
            public func publicAPI() {
                queue.sync { _updateData() }
            }
            
            private func _updateData() {
                _data = "updated"
                _notifyChange()  // ✅ Underscore to underscore is OK
            }
            
            private func _notifyChange() {
                // ❌ This indirectly calls public method, creating re-entry
                publicAPI()
            }
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertTrue(violations.contains { violation in
            violation.message.contains("cannot call non-underscore function") &&
            violation.message.contains("publicAPI")
        }, "Indirect public method calls should be detected as re-entry risk")
    }
    
    // MARK: - Configuration Tests
    
    func testCustomQueueWrapperMethods_ShouldRecognizeConfiguredMethods() throws {
        // Create checker with custom queue wrapper methods
        let customConfig = CheckerConfig(
            excludePatterns: ["Tests"],
            queueWrapperMethods: ["asyncUtility", "syncUtility", "customAsync"]
        )
        let customChecker = SafeJourneyChecker(config: customConfig)
        
        let code = """
        final class CustomUtilityClass: @unchecked Sendable {
            private var _data: String = ""
            
            // Custom queue wrapper methods should be recognized
            public func updateData() {
                asyncUtility {
                    self._data = "updated via asyncUtility"  // ✅ Should be valid - inside custom async block
                }
            }
            
            public func getData() -> String {
                syncUtility {
                    return _data  // ✅ Should be valid - inside custom sync block
                }
            }
            
            public func process() {
                customAsync {
                    _processData()  // ✅ Should be valid - inside custom async block
                }
            }
            
            private func _processData() {
                _data = "processed"
            }
        }
        """
        
        let testFile = tempDir.appendingPathComponent("CustomUtilityTest.swift")
        try code.write(to: testFile, atomically: true, encoding: .utf8)
        let violations = customChecker.checkSingleFile(testFile.path)
        
        // Should not report violations for custom queue wrapper methods
        XCTAssertFalse(violations.contains { violation in
            violation.message.contains("cannot directly access") &&
            (violation.message.contains("_data") || violation.message.contains("_processData"))
        }, "Custom queue wrapper methods should be recognized as queue protection")
    }
    
    func testCustomQueueWrapperMethods_ComparedToDefaultConfig() throws {
        // Test the same code with default config vs custom config to prove the difference
        let codeWithCustomMethods = """
        final class ComparisonTest: @unchecked Sendable {
            private var _data: String = ""
            
            public func updateWithCustomMethod() {
                asyncUtility {
                    self._data = "updated"  // Should fail with default, pass with custom
                }
            }
        }
        """
        
        let testFile = tempDir.appendingPathComponent("ComparisonTest.swift")
        try codeWithCustomMethods.write(to: testFile, atomically: true, encoding: .utf8)
        
        // Test with default config - should find violation
        let defaultChecker = SafeJourneyChecker()
        let defaultViolations = defaultChecker.checkSingleFile(testFile.path)
        
        XCTAssertTrue(defaultViolations.contains { violation in
            violation.message.contains("cannot directly access") && violation.message.contains("_data")
        }, "Default config should not recognize 'asyncUtility' as queue protection")
        
        // Test with custom config - should not find violation
        let customConfig = CheckerConfig(queueWrapperMethods: ["sync", "async", "asyncUtility"])
        let customChecker = SafeJourneyChecker(config: customConfig)
        let customViolations = customChecker.checkSingleFile(testFile.path)
        
        XCTAssertFalse(customViolations.contains { violation in
            violation.message.contains("cannot directly access") && violation.message.contains("_data")
        }, "Custom config should recognize 'asyncUtility' as queue protection")
    }
    
    func testConfigurationFileLoading_ShouldLoadQueueWrapperMethods() throws {
        // Create a configuration file with custom queue wrapper methods
        let configContent = """
        {
            "excludePatterns": ["Tests", "Mock"],
            "queueWrapperMethods": ["customSync", "customAsync", "utilityQueue"]
        }
        """
        
        let configFile = tempDir.appendingPathComponent("test-config.json")
        try configContent.write(to: configFile, atomically: true, encoding: .utf8)
        
        // Load configuration
        let loadedConfig = CheckerConfig.load(from: configFile.path)
        
        XCTAssertNotNil(loadedConfig)
        XCTAssertEqual(loadedConfig?.excludePatterns, ["Tests", "Mock"])
        XCTAssertEqual(loadedConfig?.queueWrapperMethods, ["customSync", "customAsync", "utilityQueue"])
    }
    
    func testConfigurationFileSaving_ShouldSaveQueueWrapperMethods() throws {
        let config = CheckerConfig(
            excludePatterns: ["TestFiles"],
            queueWrapperMethods: ["mySync", "myAsync"]
        )
        
        let configFile = tempDir.appendingPathComponent("save-test-config.json")
        try config.save(to: configFile.path)
        
        // Load it back and verify
        let loadedConfig = CheckerConfig.load(from: configFile.path)
        
        XCTAssertNotNil(loadedConfig)
        XCTAssertEqual(loadedConfig?.excludePatterns, ["TestFiles"])
        XCTAssertEqual(loadedConfig?.queueWrapperMethods, ["mySync", "myAsync"])
    }
    
    // MARK: - Edge Cases and Regression Tests
    
    func testEdgeCase_UnderscoreInStringLiterals_ShouldNotTriggerFalsePositives() throws {
        let code = """
        final class TestClass: @unchecked Sendable {
            private let queue = DispatchQueue(label: "test")
            private var _data: String = ""
            
            public func updateData() {
                queue.sync {
                    _data = "string_with_underscores_should_not_trigger"
                    let message = "another_underscore_string"
                }
            }
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertFalse(violations.contains { violation in
            violation.message.contains("string_with_underscores") ||
            violation.message.contains("another_underscore_string")
        }, "Underscores in string literals should not trigger false positives")
    }
    
    func testEdgeCase_UnderscoreInComments_ShouldNotTriggerFalsePositives() throws {
        let code = """
        final class TestClass: @unchecked Sendable {
            private let queue = DispatchQueue(label: "test")
            private var _data: String = ""
            
            public func updateData() {
                queue.sync {
                    // This comment mentions _someProperty but should not trigger
                    _data = "valid access"
                }
            }
        }
        """
        
        let violations = try checkCode(code)
        XCTAssertFalse(violations.contains { violation in
            violation.message.contains("_someProperty")
        }, "Underscores in comments should not trigger false positives")
    }

    // MARK: - Helper methods
    
    private func checkCode(_ code: String, file: String = "TestFile.swift") throws -> [Violation] {
        let testFile = tempDir.appendingPathComponent(file)
        try code.write(to: testFile, atomically: true, encoding: .utf8)
        return checker.checkSingleFile(testFile.path)
    }
}