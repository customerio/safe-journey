import Foundation
import SwiftSyntax
import SwiftParser

/// SwiftSyntax-based implementation of SafeJourney pattern checker
public class SafeJourneySyntaxChecker {
    private var violations: [Violation] = []
    private let config: CheckerConfig
    
    public init(config: CheckerConfig = .default) {
        self.config = config
    }
    
    /// Check a directory for violations using SwiftSyntax
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
    
    /// Check a single file for violations using SwiftSyntax
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
        
        // Parse the Swift source code into an AST
        let sourceFile = Parser.parse(source: content)
        
        // Create a visitor to traverse the AST and check for violations
        let visitor = SafeJourneyVisitor(
            config: config,
            filePath: filePath,
            sourceLocationConverter: SourceLocationConverter(fileName: filePath, tree: sourceFile)
        )
        
        visitor.walk(sourceFile)
        violations.append(contentsOf: visitor.violations)
    }
}

/// AST visitor that implements SafeJourney pattern rules using SwiftSyntax
class SafeJourneyVisitor: SyntaxVisitor {
    private let config: CheckerConfig
    private let filePath: String
    private let sourceLocationConverter: SourceLocationConverter
    
    // Context tracking
    private var currentClass: ClassDeclSyntax?
    private var isInSendableClass = false
    private var currentFunction: FunctionDeclSyntax?
    private var isInUnderscoreFunction = false
    private var queueProtectionStack: [Bool] = []
    private var queueUsageMap: [String: String] = [:]
    
    // Queue consistency tracking
    private var queueDeclarations: [String] = []  // Track queue property names
    private var detectedQueueWrappers: Set<String> = []  // Auto-detected queue wrapper methods
    
    var violations: [Violation] = []
    
    init(config: CheckerConfig, filePath: String, sourceLocationConverter: SourceLocationConverter) {
        self.config = config
        self.filePath = filePath
        self.sourceLocationConverter = sourceLocationConverter
        super.init(viewMode: .sourceAccurate)
    }
    
    // MARK: - Class Declaration Handling
    
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let previousClass = currentClass
        let previousSendable = isInSendableClass
        
        currentClass = node
        isInSendableClass = isClassSendable(node)
        queueDeclarations.removeAll()  // Reset queue tracking for each class
        detectedQueueWrappers.removeAll()  // Reset queue wrapper detection

        // First pass: Analyze functions to detect queue wrapper methods
        if isInSendableClass {
            analyzeQueueWrapperMethods(node)
        }

        // Second pass: Visit children with updated context
        for child in node.children(viewMode: .sourceAccurate) {
            walk(child)
        }
        
        currentClass = previousClass
        isInSendableClass = previousSendable
        
        return .skipChildren
    }
    
    private func analyzeQueueWrapperMethods(_ classDecl: ClassDeclSyntax) {
        // Find all function declarations in the class
        for member in classDecl.memberBlock.members {
            if let functionDecl = member.decl.as(FunctionDeclSyntax.self) {
                let functionName = functionDecl.name.text
                
                // Skip underscore functions only
                if functionName.hasPrefix("_") {
                    continue
                }
                
                // Check if this function contains queue operations
                if containsQueueOperations(functionDecl) {
                    detectedQueueWrappers.insert(functionName)
                }
            }
        }
    }
    
    private func containsQueueOperations(_ functionDecl: FunctionDeclSyntax) -> Bool {
        // Use a simple visitor to check if the function contains queue.sync or queue.async calls
        class QueueDetector: SyntaxVisitor {
            var containsQueue = false
            
            override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
                if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) {
                    let methodName = memberAccess.declName.baseName.text
                    if methodName == "sync" || methodName == "async" {
                        containsQueue = true
                        return .skipChildren
                    }
                }
                return super.visit(node)
            }
        }
        
        let detector = QueueDetector(viewMode: .sourceAccurate)
        detector.walk(functionDecl)
        return detector.containsQueue
    }

    private func isClassSendable(_ classDecl: ClassDeclSyntax) -> Bool {
        // Check inheritance clause for Sendable first (most common pattern)
        if let inheritanceClause = classDecl.inheritanceClause {
            for inheritance in inheritanceClause.inheritedTypes {
                let typeText = inheritance.type.description.trimmingCharacters(in: .whitespaces)
                
                // Handle various Sendable patterns
                if typeText == "Sendable" || 
                   typeText == "@unchecked Sendable" ||
                   typeText.contains("Sendable") {
                    return true
                }
            }
        }
        
        // Check for @unchecked attribute before class declaration
        for attribute in classDecl.attributes {
            let attrText = attribute.description.trimmingCharacters(in: .whitespaces)
            
            if attrText.contains("unchecked") || attrText.contains("Sendable") {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Function Declaration Handling
    
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let previousFunction = currentFunction
        let previousUnderscore = isInUnderscoreFunction
        
        currentFunction = node
        isInUnderscoreFunction = node.name.text.hasPrefix("_")
        
        // Check Rule 2: Underscore functions must be private
        if isInUnderscoreFunction && isInSendableClass {
            checkUnderscoreFunctionPrivacy(node)
        }
        
        // Visit children with updated context
        for child in node.children(viewMode: .sourceAccurate) {
            walk(child)
        }
        
        currentFunction = previousFunction
        isInUnderscoreFunction = previousUnderscore
        
        return .skipChildren
    }
    
    private func checkUnderscoreFunctionPrivacy(_ functionDecl: FunctionDeclSyntax) {
        let isPrivate = functionDecl.modifiers.contains { modifier in
            modifier.name.text == "private"
        }
        
        if !isPrivate {
            let location = sourceLocationConverter.location(for: functionDecl.positionAfterSkippingLeadingTrivia)
            addViolation(
                line: location.line,
                message: "Underscore items must be private",
                suggestion: "Add 'private' modifier"
            )
        }
    }
    
    // MARK: - Variable Declaration Handling
    
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        if isInSendableClass {
            checkVariableDeclaration(node)
        }
        return super.visit(node)
    }
    
    private func checkVariableDeclaration(_ variableDecl: VariableDeclSyntax) {
        // Skip static variables
        if variableDecl.modifiers.contains(where: { $0.name.text == "static" }) {
            return
        }
        
        for binding in variableDecl.bindings {
            if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                let variableName = pattern.identifier.text
                
                // Rule 1: Mutable properties must use underscore prefix (only for var)
                if variableDecl.bindingSpecifier.text == "var" && !variableName.hasPrefix("_") {
                    let location = sourceLocationConverter.location(for: variableDecl.positionAfterSkippingLeadingTrivia)
                    addViolation(
                        line: location.line,
                        message: "Mutable property must use underscore prefix for thread safety",
                        suggestion: "Change 'var \(variableName)' to 'private var _\(variableName)'"
                    )
                }
                
                // Rule 2: Underscore variables must be private (for both var and let)
                if variableName.hasPrefix("_") {
                    let isPrivate = variableDecl.modifiers.contains { modifier in
                        modifier.name.text == "private"
                    }
                    
                    if !isPrivate {
                        let location = sourceLocationConverter.location(for: variableDecl.positionAfterSkippingLeadingTrivia)
                        addViolation(
                            line: location.line,
                            message: "Underscore items must be private",
                            suggestion: "Add 'private' modifier"
                        )
                    }
                }
                
                // Rule 6: Track DispatchQueue declarations for consistency checking (for both var and let)
                if let initializer = binding.initializer,
                   let functionCall = initializer.value.as(FunctionCallExprSyntax.self),
                   let declRef = functionCall.calledExpression.as(DeclReferenceExprSyntax.self),
                   declRef.baseName.text == "DispatchQueue" {
                    queueDeclarations.append(variableName)
                    
                    // Check for multiple queue declarations
                    if queueDeclarations.count > 1 {
                        let location = sourceLocationConverter.location(for: variableDecl.positionAfterSkippingLeadingTrivia)
                        addViolation(
                            line: location.line,
                            message: "Multiple queues detected (\(queueDeclarations.joined(separator: ", "))). SafeJourney pattern requires single queue per class",
                            suggestion: "Use a single DispatchQueue for all operations in this class"
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Function Call and Member Access Handling
    
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        if isInSendableClass {
            checkMemberAccess(node)
        }
        return super.visit(node)
    }
    
    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        if isInSendableClass {
            checkDeclReference(node)
        }
        return super.visit(node)
    }
    
    private func checkMemberAccess(_ memberAccess: MemberAccessExprSyntax) {
        let memberName = memberAccess.declName.baseName.text
        
        // Check if accessing underscore member
        if memberName.hasPrefix("_") {
            // Rule 3: Non-underscore functions must use queue protection for underscore access
            if let currentFunction = currentFunction, !isInUnderscoreFunction {
                let isQueueProtected = isCurrentlyInQueueProtection()
                if !isQueueProtected {
                    let location = sourceLocationConverter.location(for: memberAccess.positionAfterSkippingLeadingTrivia)
                    addViolation(
                        line: location.line,
                        message: "Function '\(currentFunction.name.text)' cannot directly access \(memberName). Use queue protection",
                        suggestion: "Wrap in queue.sync { } or queue.async { }"
                    )
                }
            }
        }
    }
    
    private func checkDeclReference(_ declRef: DeclReferenceExprSyntax) {
        let variableName = declRef.baseName.text
        
        // Check if accessing underscore property
        if variableName.hasPrefix("_") {
            // Skip if this is part of a member access expression (handled by checkMemberAccess)
            if isDeclReferencePartOfMemberAccess(declRef) {
                return
            }
            
            // Rule 3: Non-underscore functions must use queue protection for underscore access
            if let currentFunction = currentFunction, !isInUnderscoreFunction {
                let isQueueProtected = isCurrentlyInQueueProtection()
                if !isQueueProtected {
                    let location = sourceLocationConverter.location(for: declRef.positionAfterSkippingLeadingTrivia)
                    addViolation(
                        line: location.line,
                        message: "Function '\(currentFunction.name.text)' cannot directly access \(variableName). Use queue protection",
                        suggestion: "Wrap in queue.sync { } or queue.async { }"
                    )
                }
            }
        }
    }
    
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if isInSendableClass {
            var methodName: String?
            
            // Check for both member access (queue.sync) and direct calls (customSync)
            if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) {
                methodName = memberAccess.declName.baseName.text
            } else if let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self) {
                methodName = declRef.baseName.text
            }
            
            if let method = methodName {
                // Rule 4: Check for queue operations in underscore functions FIRST
                // This must come before queue wrapper handling to detect violations
                if isInUnderscoreFunction && (method == "sync" || method == "async") {
                    let location = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
                    addViolation(
                        line: location.line,
                        message: "Underscore function cannot use queue operations - will cause deadlock",
                        suggestion: "Move queue operations to non-underscore function"
                    )
                }
                
                // Check if this is a queue wrapper method (configured or auto-detected)
                if config.queueWrapperMethods.contains(method) || detectedQueueWrappers.contains(method) {
                    queueProtectionStack.append(true)
                    // Visit children under queue protection
                    for child in node.children(viewMode: .sourceAccurate) {
                        walk(child)
                    }
                    queueProtectionStack.removeLast()
                    return .skipChildren
                }
            }
            
            // Check for function calls from underscore functions
            if isInUnderscoreFunction {
                checkUnderscoreFunctionCalls(node)
            }
        }
        
        return super.visit(node)
    }
    
    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        if isInSendableClass {
            // Check if this closure is passed to an async operation that breaks queue protection
            let createsNewAsyncContext = isClosureCreatingNewAsyncContext(node)
            
            if createsNewAsyncContext {
                // This closure creates a new asynchronous context - reset queue protection
                let previousProtectionStack = queueProtectionStack
                queueProtectionStack = []
                
                // Visit closure children with reset protection context
                for child in node.children(viewMode: .sourceAccurate) {
                    walk(child)
                }
                
                // Restore previous protection context
                queueProtectionStack = previousProtectionStack
                return .skipChildren
            } else {
                // Check if this closure is directly inside a queue wrapper method call
                // If so, it inherits queue protection. Otherwise, it creates a new context.
                let shouldInheritQueueProtection = isCurrentlyInQueueProtection()
                
                if !shouldInheritQueueProtection {
                    // This closure is not directly protected by a queue wrapper
                    // Reset queue protection context for independent closures
                    let previousProtectionStack = queueProtectionStack
                    queueProtectionStack = []
                    
                    // Visit closure children with reset protection context
                    for child in node.children(viewMode: .sourceAccurate) {
                        walk(child)
                    }
                    
                    // Restore previous protection context
                    queueProtectionStack = previousProtectionStack
                    return .skipChildren
                }
            }
        }
        
        return super.visit(node)
    }
    
    private func checkUnderscoreFunctionCalls(_ functionCall: FunctionCallExprSyntax) {
        // Get function name being called
        var functionName: String?
        
        if let identifierExpr = functionCall.calledExpression.as(DeclReferenceExprSyntax.self) {
            functionName = identifierExpr.baseName.text
        } else if let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self) {
            functionName = memberAccess.declName.baseName.text
        }
        
        if let funcName = functionName,
           !funcName.hasPrefix("_") && !isSystemFunction(funcName) {
            let location = sourceLocationConverter.location(for: functionCall.positionAfterSkippingLeadingTrivia)
            addViolation(
                line: location.line,
                message: "Underscore function '\(currentFunction?.name.text ?? "")' cannot call non-underscore function '\(funcName)'. This can cause deadlocks",
                suggestion: "Only call other underscore functions from underscore functions"
            )
        }
    }
    
    // MARK: - Helper Methods
    
    private func isCurrentlyInQueueProtection() -> Bool {
        return queueProtectionStack.contains(true)
    }
    
    private func isDeclReferencePartOfMemberAccess(_ declRef: DeclReferenceExprSyntax) -> Bool {
        // Check if this DeclReference is the base of a member access (like `_items` in `_items.append`)
        // If so, we should NOT skip it - it should be checked for violations
        // We only skip if it's the member name part of member access (like `_member` in `obj._member`)
        
        var current: Syntax? = Syntax(declRef)
        
        while let parent = current?.parent {
            if let memberAccess = parent.as(MemberAccessExprSyntax.self) {
                // Check if this declRef is the base of the member access
                if memberAccess.base?.description.trimmingCharacters(in: .whitespaces) == declRef.description.trimmingCharacters(in: .whitespaces) {
                    // This is the base of member access (like `_items` in `_items.append`), don't skip
                    return false
                } else {
                    // This is the member name part, skip it to avoid duplicate violations
                    return true
                }
            }
            // Stop at certain boundary nodes to avoid false positives
            if parent.is(FunctionCallExprSyntax.self) || parent.is(VariableDeclSyntax.self) {
                break
            }
            current = parent
        }
        
        return false
    }
    
    private func isClosureCreatingNewAsyncContext(_ closureNode: ClosureExprSyntax) -> Bool {
        // Walk up the parent hierarchy to find if this closure is an argument to an async function
        var current: Syntax? = Syntax(closureNode)
        
        while let parent = current?.parent {
            // Check if the parent is a function call expression
            if let functionCall = parent.as(FunctionCallExprSyntax.self) {
                // Check if this is an async operation that creates a new context
                if isAsyncFunctionCall(functionCall) {
                    return true
                }
            }
            
            // Move up the hierarchy
            current = parent
        }
        
        return false
    }
    
    private func isAsyncFunctionCall(_ functionCall: FunctionCallExprSyntax) -> Bool {
        // First check if this is a known queue wrapper - if so, it doesn't create new async context
        var methodName: String?
        if let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self) {
            methodName = memberAccess.declName.baseName.text
        } else if let declRef = functionCall.calledExpression.as(DeclReferenceExprSyntax.self) {
            methodName = declRef.baseName.text
        }
        
        if let method = methodName {
            // If this is a detected queue wrapper, it doesn't create new async context
            if config.queueWrapperMethods.contains(method) || detectedQueueWrappers.contains(method) {
                return false
            }
        }
        
        // Check for DispatchQueue.async patterns
        if let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self) {
            let methodName = memberAccess.declName.baseName.text
            
            // Check for DispatchQueue async methods
            if methodName == "async" {
                // Check if the base expression involves DispatchQueue
                let baseText = memberAccess.base?.description.trimmingCharacters(in: .whitespaces) ?? ""
                if baseText.contains("DispatchQueue") {
                    return true
                }
            }
            
            // Check for other common async patterns
            if methodName == "asyncAfter" || methodName == "asyncAndWait" {
                return true
            }
        }
        
        // Check for other async patterns like Task.init, but NOT our custom methods
        if let declRef = functionCall.calledExpression.as(DeclReferenceExprSyntax.self) {
            let functionName = declRef.baseName.text
            // Only treat as async if it's a system function, not our custom wrappers
            if functionName == "Task" {
                return true
            }
        }
        
        return false
    }
    
    private func isSystemFunction(_ functionName: String) -> Bool {
        let systemFunctions = [
            "print", "debugPrint", "assert", "precondition", "fatalError",
            "append", "removeAll", "insert", "remove", "count", "isEmpty",
            "String", "Int", "Bool", "Double", "Float", "Array", "Dictionary"
        ]
        
        return systemFunctions.contains(functionName) ||
               functionName == "completion" ||
               functionName.hasSuffix("Completion") ||
               functionName.hasSuffix("Callback") ||
               functionName.hasSuffix("Handler")
    }
    
    private func addViolation(line: Int, message: String, suggestion: String? = nil) {
        violations.append(Violation(
            file: filePath,
            line: line,
            type: .error,
            message: message,
            suggestion: suggestion
        ))
    }
}