import Foundation

extension NSRegularExpression {
    static func matches(pattern: String, in string: String) -> Bool {
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(location: 0, length: string.utf16.count)
            return regex.firstMatch(in: string, options: [], range: range) != nil
        } catch {
            return false
        }
    }
}

/// Configuration for the SafeJourney checker
public struct CheckerConfig: Sendable {
    public let excludePatterns: [String]
    public let queueWrapperMethods: [String]
    
    public init(
        excludePatterns: [String] = ["Tests", "test", "Test", "Mock", "mock", "scripts"],
        queueWrapperMethods: [String] = ["sync", "async"]
    ) {
        self.excludePatterns = excludePatterns
        self.queueWrapperMethods = queueWrapperMethods
    }
    
    public static let `default` = CheckerConfig()
}

/// Type of violation detected by the checker
public enum ViolationType: Sendable {
    case error
    case warning
    
    public var symbol: String {
        switch self {
        case .error: return "❌"
        case .warning: return "⚠️"
        }
    }
}

/// A violation of the SafeJourney pattern
public struct Violation: Sendable {
    public let file: String
    public let line: Int
    public let type: ViolationType
    public let message: String
    public let suggestion: String?
    
    public init(file: String, line: Int, type: ViolationType, message: String, suggestion: String? = nil) {
        self.file = file
        self.line = line
        self.type = type
        self.message = message
        self.suggestion = suggestion
    }
}

/// Internal structure for tracking code context during parsing
struct CodeContext {
    var className: String?
    var isUncheckdSendable = false
    var currentFunction: String?
    var isUnderscoreFunction = false
    var inQueueBlock = false
    var currentQueueName: String?
    var braceDepth = 0
    var functionStartDepth = 0
    var queueBlockDepth = 0
    var queueUsageMap: [String: String] = [:] // underscore_item -> queue_name
    var nextLineInQueue = false // Flag to indicate the next line is in a queue block
}

/// Main checker class for the SafeJourney pattern
public class SafeJourneyChecker {
    private var violations: [Violation] = []
    private let config: CheckerConfig
    
    public init(config: CheckerConfig = .default) {
        self.config = config
    }
    
    /// Check a directory for violations
    public func checkDirectory(_ path: String) -> [Violation] {
        violations.removeAll()
        let fileManager = FileManager.default
        
        guard let enumerator = fileManager.enumerator(atPath: path) else {
            return []
        }
        
        for case let file as String in enumerator {
            if shouldCheckFile(file) {
                let fullPath = "\(path)/\(file)"
                checkFile(fullPath)
            }
        }
        
        return violations
    }
    
    /// Check a single file for violations
    public func checkSingleFile(_ filePath: String) -> [Violation] {
        violations.removeAll()
        checkFile(filePath)
        return violations
    }
    
    private func shouldCheckFile(_ file: String) -> Bool {
        guard file.hasSuffix(".swift") else { return false }
        
        for pattern in config.excludePatterns {
            if file.contains(pattern) {
                return false
            }
        }
        
        return true
    }
    
    private func checkFile(_ filePath: String) {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return
        }
        
        let lines = content.components(separatedBy: .newlines)
        var context = CodeContext()
        var classQueueUsageMap: [String: String] = [:]  // Track queue usage at class level
        
        for (lineIndex, line) in lines.enumerated() {
            let lineNumber = lineIndex + 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Update context BEFORE checking violations
            updateContext(&context, with: trimmed, line: lineNumber)
            
            // Check only Sendable classes for SafeJourney pattern violations
            if context.className != nil && context.isUncheckdSendable {
                checkForViolations(trimmed, context: &context, file: filePath, line: lineNumber, classQueueUsageMap: &classQueueUsageMap)
            }
        }
    }
    
    private func updateContext(_ context: inout CodeContext, with line: String, line lineNumber: Int) {
        // Track Sendable classes only - SafeJourney pattern applies only to classes
        if line.contains("class") &&
           (line.contains("@unchecked Sendable") || line.contains(": @unchecked Sendable") || 
            line.contains(": Sendable")) {
            context.isUncheckdSendable = true
        }
        
        // Track class boundaries
        if let className = extractClassName(from: line) {
            context.className = className
            // Don't reset isUncheckdSendable here - it was set on this same line
            return
        }
        
        // Reset class context when we exit a class (simplified detection)
        if context.className != nil && line.trimmingCharacters(in: .whitespaces) == "}" && context.braceDepth == 0 {
            context.className = nil
            context.isUncheckdSendable = false
        }
        
        // Track brace depth BEFORE other processing
        let openBraces = line.filter { $0 == "{" }.count
        let closeBraces = line.filter { $0 == "}" }.count
        context.braceDepth += openBraces - closeBraces
        
        // Track function boundaries
        if let funcName = extractFunctionName(from: line) {
            context.currentFunction = funcName
            context.isUnderscoreFunction = funcName.hasPrefix("_")
            context.functionStartDepth = context.braceDepth
            context.inQueueBlock = false
            context.queueBlockDepth = 0
            return
        }
        
        // Check if we've exited the current function
        if context.currentFunction != nil && context.braceDepth < context.functionStartDepth {
            context.currentFunction = nil
            context.isUnderscoreFunction = false
            context.inQueueBlock = false
        }
        
        // Enhanced queue block detection using configurable wrapper methods
        let hasQueueBlock = config.queueWrapperMethods.contains { method in
            line.contains(".\(method) {") || line.contains("\(method) {")
        }
        
        if hasQueueBlock {
            context.inQueueBlock = true
            // We exit the queue block when we return to this brace depth (before the opening brace)
            context.queueBlockDepth = context.braceDepth - 1
            context.currentQueueName = extractQueueName(from: line)
        }
        
        // Check if we've exited the queue block
        if context.inQueueBlock && context.braceDepth <= context.queueBlockDepth {
            context.inQueueBlock = false
            context.currentQueueName = nil
        }
    }
    
    private func checkForViolations(_ line: String, context: inout CodeContext, file: String, line lineNumber: Int, classQueueUsageMap: inout [String: String]) {
        // Rule 1: Mutable properties should use underscore prefix
        checkMutablePropertyRule(line, context: context, file: file, line: lineNumber)
        
        // Rule 2: Underscore items must be private
        checkUnderscorePrivateRule(line, context: context, file: file, line: lineNumber)
        
        // Rule 3: Context-aware underscore access checking
        checkUnderscoreAccessRule(line, context: context, file: file, line: lineNumber, classQueueUsageMap: &classQueueUsageMap)
        
        // Rule 4: Underscore functions using queue operations (deadlock risk)
        checkNestedQueueRule(line, context: context, file: file, line: lineNumber)
        
        // Rule 5: Single queue consistency - check for on-the-fly queue creation
        if context.currentFunction != nil && !context.isUnderscoreFunction {
            checkOnTheFlyQueueCreation(line, context: context, file: file, line: lineNumber)
            checkGlobalQueueUsage(line, context: context, file: file, line: lineNumber)
        }
    }
    
    private func checkMutablePropertyRule(_ line: String, context: CodeContext, file: String, line lineNumber: Int) {
        if line.contains("var ") && !line.contains("_") && !line.contains("static") {
            // Check if it's a property declaration (has = or :)
            if line.contains(" = ") || (line.contains(": ") && !line.contains("func")) {
                addViolation(
                    file: file, line: lineNumber, type: .error,
                    message: "Mutable property must use underscore prefix for thread safety",
                    suggestion: "Change 'var property' to 'private var _property'"
                )
            }
        }
    }
    
    private func checkUnderscorePrivateRule(_ line: String, context: CodeContext, file: String, line lineNumber: Int) {
        if (line.contains("func _") || line.contains("var _")) && !line.contains("private") {
            addViolation(
                file: file, line: lineNumber, type: .error,
                message: "Underscore items must be private",
                suggestion: "Add 'private' modifier"
            )
        }
    }
    
    private func checkUnderscoreAccessRule(_ line: String, context: CodeContext, file: String, line lineNumber: Int, classQueueUsageMap: inout [String: String]) {
        if let function = context.currentFunction {
            if !context.isUnderscoreFunction {
                // Non-underscore functions: must use queue for underscore access
                if line.contains("_") && !context.inQueueBlock {
                    let underscoreItems = extractUnderscoreAccess(from: line)
                    if !underscoreItems.isEmpty {
                        // Filter out underscore items in comments or strings
                        let filteredItems = underscoreItems.filter { item in
                            !isInStringLiteral(item, in: line) && !isInComment(item, in: line)
                        }
                        if !filteredItems.isEmpty {
                            addViolation(
                                file: file, line: lineNumber, type: .error,
                                message: "Function '\(function)' cannot directly access \(filteredItems). Use queue protection",
                                suggestion: "Wrap in queue.sync { } or queue.async { }"
                            )
                        }
                    }
                } else if context.inQueueBlock, let queueName = context.currentQueueName {
                    // Check for on-the-fly queue creation first
                    checkOnTheFlyQueueCreation(line, context: context, file: file, line: lineNumber)
                    
                    // Check for global/main queue usage
                    checkGlobalQueueUsage(line, context: context, file: file, line: lineNumber)
                    
                    // Track queue usage for multiple queue detection
                    let underscoreItems = extractUnderscoreAccess(from: line)
                    checkMultipleQueueUsage(underscoreItems, queueName: queueName, classQueueUsageMap: &classQueueUsageMap, file: file, line: lineNumber)
                }
            } else {
                // Underscore functions: check for non-underscore function calls
                if line.contains("(") && !line.contains("_") {
                    let functionCalls = extractFunctionCalls(from: line)
                    for call in functionCalls {
                        if !call.hasPrefix("_") && !isSystemFunction(call) {
                            addViolation(
                                file: file, line: lineNumber, type: .error,
                                message: "Underscore function '\(function)' cannot call non-underscore function '\(call)'. This can cause deadlocks",
                                suggestion: "Only call other underscore functions from underscore functions"
                            )
                        }
                    }
                }
            }
        }
    }
    
    private func checkOnTheFlyQueueCreation(_ line: String, context: CodeContext, file: String, line lineNumber: Int) {
        // Detect on-the-fly queue creation patterns
        let onTheFlyPatterns = [
            "DispatchQueue(label:",
            "DispatchQueue("
        ]
        
        for pattern in onTheFlyPatterns {
            if line.contains(pattern) {
                addViolation(
                    file: file, line: lineNumber, type: .error,
                    message: "SafeJourney pattern violation: on-the-fly queue creation detected. Use a single dedicated class queue",
                    suggestion: "Declare a private let queue = DispatchQueue(label: ...) property and use it consistently"
                )
                break
            }
        }
    }
    
    private func checkGlobalQueueUsage(_ line: String, context: CodeContext, file: String, line lineNumber: Int) {
        // Detect global queue usage patterns
        let globalQueuePatterns = [
            "DispatchQueue.global()",
            "DispatchQueue.main"
        ]
        
        for pattern in globalQueuePatterns {
            if line.contains(pattern) {
                addViolation(
                    file: file, line: lineNumber, type: .error,
                    message: "SafeJourney pattern violation: global/main queue usage detected. Use dedicated class queue",
                    suggestion: "Use a private dedicated queue instead of global or main queue"
                )
                break
            }
        }
    }
    
    private func checkMultipleQueueUsage(_ underscoreItems: [String], queueName: String, classQueueUsageMap: inout [String: String], file: String, line lineNumber: Int) {
        for item in underscoreItems {
            // Filter out false positives from comments and strings
            if isInStringLiteral(item, in: "dummy line") || isInComment(item, in: "dummy line") {
                continue
            }
            
            if let existingQueue = classQueueUsageMap[item] {
                if existingQueue != queueName {
                    addViolation(
                        file: file, line: lineNumber, type: .error,
                        message: "SafeJourney pattern violation: underscore item '\(item)' is accessed by multiple queues ('\(existingQueue)' and '\(queueName)'). Use a single queue for thread safety",
                        suggestion: "Consolidate all access to '\(item)' through a single queue"
                    )
                }
            } else {
                classQueueUsageMap[item] = queueName
            }
        }
    }
    
    private func checkNestedQueueRule(_ line: String, context: CodeContext, file: String, line lineNumber: Int) {
        if context.isUnderscoreFunction {
            // Flag sync operations (always dangerous in underscore functions)
            if line.contains(".sync") {
                addViolation(
                    file: file, line: lineNumber, type: .error,
                    message: "Underscore function cannot use queue operations - will cause deadlock",
                    suggestion: "Move queue operations to non-underscore function"
                )
            }
            
            // Flag async operations on instance queues (but allow external queue dispatch)
            if line.contains(".async") && !line.contains("DispatchQueue.global") && !line.contains("DispatchQueue.main") {
                addViolation(
                    file: file, line: lineNumber, type: .error,
                    message: "Underscore function cannot use queue operations - will cause deadlock",
                    suggestion: "Move queue operations to non-underscore function"
                )
            }
            
            // Check for on-the-fly queue creation (dangerous)
            if line.contains("DispatchQueue(label:") || line.contains("DispatchQueue(") {
                // Skip if it's a global or main queue access
                if !line.contains("DispatchQueue.global") && !line.contains("DispatchQueue.main") {
                    addViolation(
                        file: file, line: lineNumber, type: .error,
                        message: "Underscore function cannot use queue operations - will cause deadlock",
                        suggestion: "Move queue operations to non-underscore function"
                    )
                }
            }
        }
    }
    
    // MARK: - Utility Methods
    
    private func extractClassName(from line: String) -> String? {
        // Only extract class names - SafeJourney pattern applies only to classes
        let pattern = "class\\s+(\\w+)"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
            if let range = Range(match.range(at: 1), in: line) {
                return String(line[range])
            }
        }
        return nil
    }
    
    private func extractFunctionName(from line: String) -> String? {
        let pattern = "func\\s+(\\w+)"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
            if let range = Range(match.range(at: 1), in: line) {
                return String(line[range])
            }
        }
        return nil
    }
    
    private func extractUnderscoreAccess(from line: String) -> [String] {
        let pattern = "\\b_\\w+"
        var matches: [String] = []
        
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsLine = line as NSString
            let results = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            
            for result in results {
                let match = nsLine.substring(with: result.range)
                matches.append(match)
            }
        }
        
        return matches
    }
    
    private func extractQueueName(from line: String) -> String? {
        // Extract queue name from patterns like "queueName.sync" or "queueName.async"
        let patterns = [
            "(\\w+)\\.sync\\s*\\{",
            "(\\w+)\\.async\\s*\\{",
            "DispatchQueue\\(label:\\s*\"([^\"]+)\""
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                if let range = Range(match.range(at: 1), in: line) {
                    return String(line[range])
                }
            }
        }
        
        return "unknown_queue"
    }
    
    private func extractFunctionCalls(from line: String) -> [String] {
        let pattern = "\\b(\\w+)\\s*\\("
        var matches: [String] = []
        
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsLine = line as NSString
            let results = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            
            for result in results {
                if let range = Range(result.range(at: 1), in: line) {
                    let match = String(line[range])
                    matches.append(match)
                }
            }
        }
        
        return matches
    }
    
    private func isSystemFunction(_ functionName: String) -> Bool {
        let systemFunctions = [
            "print", "debugPrint", "assert", "precondition", "fatalError",
            "guard", "return", "break", "continue", "exit",
            "append", "removeAll", "insert", "remove", "count", "isEmpty",
            "String", "Int", "Bool", "Double", "Float", "Array", "Dictionary",
            "Date", "UUID", "URL", "Data", "NSString", "NSArray", "NSDictionary",
            // DispatchQueue system functions
            "global", "main", "async", "sync"
        ]
        
        // Check exact matches for system functions
        if systemFunctions.contains(functionName) {
            return true
        }
        
        // Allow completion/callback parameters (common pattern)
        if functionName == "completion" || functionName.hasSuffix("Completion") || 
           functionName.hasSuffix("Callback") || functionName.hasSuffix("Handler") {
            return true
        }
        
        return false
    }
    
    private func isInStringLiteral(_ item: String, in line: String) -> Bool {
        // Simple check for string literals - could be improved
        let stringPattern = "\"[^\"]*\\Q\(item)\\E[^\"]*\""
        return NSRegularExpression.matches(pattern: stringPattern, in: line)
    }
    
    private func isInComment(_ item: String, in line: String) -> Bool {
        // Check if the item appears after // in a comment
        if let commentIndex = line.firstIndex(of: "/"),
           line.index(after: commentIndex) < line.endIndex,
           line[line.index(after: commentIndex)] == "/" {
            let commentPart = String(line[commentIndex...])
            return commentPart.contains(item)
        }
        return false
    }
    
    private func addViolation(file: String, line: Int, type: ViolationType, message: String, suggestion: String? = nil) {
        violations.append(Violation(file: file, line: line, type: type, message: message, suggestion: suggestion))
    }
}

// MARK: - Configuration Loading

extension CheckerConfig {
    /// Load configuration from a JSON file
    public static func load(from path: String) -> CheckerConfig? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        return CheckerConfig(
            excludePatterns: json["excludePatterns"] as? [String] ?? CheckerConfig.default.excludePatterns,
            queueWrapperMethods: json["queueWrapperMethods"] as? [String] ?? CheckerConfig.default.queueWrapperMethods
        )
    }
    
    /// Save configuration to a JSON file
    public func save(to path: String) throws {
        let json: [String: Any] = [
            "excludePatterns": excludePatterns,
            "queueWrapperMethods": queueWrapperMethods
        ]
        
        let data = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
        try data.write(to: URL(fileURLWithPath: path))
    }
}