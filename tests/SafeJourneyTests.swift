import XCTest
@testable import SafeJourney

final class SafeJourneyTests: XCTestCase {
    
    func testDefaultConfiguration() {
        let config = CheckerConfig.default
        
        XCTAssertTrue(config.excludePatterns.contains("Tests"))
        XCTAssertTrue(config.excludePatterns.contains("Mock"))
    }
    
    func testSimplifiedConfiguration() {
        let config = CheckerConfig(excludePatterns: ["Custom", "Test"])
        
        XCTAssertTrue(config.excludePatterns.contains("Custom"))
        XCTAssertTrue(config.excludePatterns.contains("Test"))
    }
    
    func testCustomExcludePatterns() {
        let config = CheckerConfig(excludePatterns: ["Example", "Demo"])
        
        XCTAssertTrue(config.excludePatterns.contains("Example"))
        XCTAssertTrue(config.excludePatterns.contains("Demo"))
        XCTAssertFalse(config.excludePatterns.contains("Tests"))
    }
    
    func testViolationCreation() {
        let violation = Violation(
            file: "TestFile.swift",
            line: 42,
            type: .error,
            message: "Test violation",
            suggestion: "Fix this"
        )
        
        XCTAssertEqual(violation.file, "TestFile.swift")
        XCTAssertEqual(violation.line, 42)
        XCTAssertEqual(violation.type, .error)
        XCTAssertEqual(violation.message, "Test violation")
        XCTAssertEqual(violation.suggestion, "Fix this")
    }
    
    func testViolationTypeSymbols() {
        XCTAssertEqual(ViolationType.error.symbol, "❌")
        XCTAssertEqual(ViolationType.warning.symbol, "⚠️")
    }
    
    func testCheckerInitialization() {
        let defaultChecker = SafeJourneyChecker()
        XCTAssertNotNil(defaultChecker)
        
        let customConfig = CheckerConfig(excludePatterns: ["Custom"])
        let customChecker = SafeJourneyChecker(config: customConfig)
        XCTAssertNotNil(customChecker)
    }
    
    func testConfigurationSaveAndLoad() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-config.json")
        
        let originalConfig = CheckerConfig(
            excludePatterns: ["Custom", "Pattern"]
        )
        
        // Save configuration
        try originalConfig.save(to: tempURL.path)
        
        // Load configuration
        let loadedConfig = CheckerConfig.load(from: tempURL.path)
        
        XCTAssertNotNil(loadedConfig)
        XCTAssertEqual(loadedConfig?.excludePatterns, ["Custom", "Pattern"])
        
        // Clean up
        try FileManager.default.removeItem(at: tempURL)
    }
    
    func testConfigurationLoadInvalidPath() {
        let config = CheckerConfig.load(from: "/non/existent/path.json")
        XCTAssertNil(config)
    }
    
    func testCheckerWithValidSwiftCode() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("safe-journey-test")
        
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let swiftFile = tempDir.appendingPathComponent("TestFile.swift")
        
        let validCode = """
        import Foundation
        
        public final class TestClass: @unchecked Sendable {
            private let queue = DispatchQueue(label: "test.queue")
            private var _mutableProperty: String = ""
            
            public func updateProperty(_ value: String) {
                queue.sync {
                    _mutableProperty = value
                }
            }
            
            private func _internalMethod() {
                _mutableProperty = "updated"
            }
        }
        """
        
        try validCode.write(to: swiftFile, atomically: true, encoding: .utf8)
        
        let checker = SafeJourneyChecker()
        let violations = checker.checkDirectory(tempDir.path)
        
        XCTAssertTrue(violations.isEmpty, "Valid code should not produce violations")
        
        // Clean up
        try FileManager.default.removeItem(at: tempDir)
    }
    
    func testCheckerWithInvalidSwiftCode() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("safe-journey-checker-invalid")
        
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let swiftFile = tempDir.appendingPathComponent("MyClass.swift")
        
        let invalidCode = """
        import Foundation
        
        public final class TestClass: @unchecked Sendable {
            private let queue = DispatchQueue(label: "test.queue")
            private var mutableProperty: String = ""  // Missing underscore
            public var _publicUnderscore: String = "" // Should be private
            
            public func updateProperty(_ value: String) {
                _publicUnderscore = value  // Direct access violation
            }
            
            private func _internalMethod() {
                queue.sync {  // Nested queue violation
                    _publicUnderscore = "updated"
                }
            }
        }
        """
        
        try invalidCode.write(to: swiftFile, atomically: true, encoding: .utf8)
        
        let checker = SafeJourneyChecker()
        let violations = checker.checkDirectory(tempDir.path)
        
        XCTAssertFalse(violations.isEmpty, "Invalid code should produce violations")
        XCTAssertTrue(violations.contains { $0.type == .error }, "Should contain error violations")
        
        // Clean up
        try FileManager.default.removeItem(at: tempDir)
    }
    
    func testCheckerExcludesTestFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("safe-journey-exclude-test")
        
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let testFile = tempDir.appendingPathComponent("TestFile.swift")
        
        let testCode = """
        import XCTest
        
        class TestClass: @unchecked Sendable {
            var badProperty: String = ""  // Should normally trigger warning
        }
        """
        
        try testCode.write(to: testFile, atomically: true, encoding: .utf8)
        
        let checker = SafeJourneyChecker()
        let violations = checker.checkDirectory(tempDir.path)
        
        XCTAssertTrue(violations.isEmpty, "Test files should be excluded")
        
        // Clean up
        try FileManager.default.removeItem(at: tempDir)
    }
}