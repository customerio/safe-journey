import Foundation
import SwiftSyntax
import SwiftParser

/// Simplified SafeJourney checker - basic pattern matcher for thread safety conventions
public class SimpleSafeJourneyChecker {
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
            if file.hasSuffix(".swift") && !shouldSkipFile(file) {
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
    
    private func shouldSkipFile(_ file: String) -> Bool {
        for pattern in config.excludePatterns {
            if file.contains(pattern) {
                return false
            }
        }
        return false
    }
    
    private func checkFile(_ filePath: String) {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return
        }
        
        // Parse the Swift source code into an AST
        let sourceFile = Parser.parse(source: content)
        
        // Create a visitor to traverse the AST and check for violations
        let visitor = SimpleSafeJourneyVisitor(
            config: config,
            filePath: filePath,
            sourceLocationConverter: SourceLocationConverter(fileName: filePath, tree: sourceFile)
        )
        
        visitor.walk(sourceFile)
        violations.append(contentsOf: visitor.violations)
    }
}

/// Simple AST visitor that implements basic SafeJourney pattern rules
class SimpleSafeJourneyVisitor: SyntaxVisitor {
    private let config: CheckerConfig
    private let filePath: String
    private let sourceLocationConverter: SourceLocationConverter
    
    // Simple context tracking
    private var currentClass: ClassDeclSyntax?
    private var isInSendableClass = false
    private var currentFunction: FunctionDeclSyntax?
    private var isInUnderscoreFunction = false
    private var isInQueueWrapper = false
    
    // Track functions declared in this file for same-file analysis
    private var functionsInFile: Set<String> = []
    
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
        
        // First pass: collect all function names in this class
        if isInSendableClass {
            collectFunctionNames(node)
        }
        
        // Second pass: check rules
        for child in node.children(viewMode: .sourceAccurate) {
            walk(child)
        }
        
        currentClass = previousClass
        isInSendableClass = previousSendable
        
        return .skipChildren
    }
    
    private func collectFunctionNames(_ classDecl: ClassDeclSyntax) {
        for member in classDecl.memberBlock.members {
            if let functionDecl = member.decl.as(FunctionDeclSyntax.self) {
                functionsInFile.insert(functionDecl.name.text)
            }
        }
    }
    
    private func isClassSendable(_ classDecl: ClassDeclSyntax) -> Bool {
        // Check inheritance clause for Sendable
        if let inheritanceClause = classDecl.inheritanceClause {
            for inheritance in inheritanceClause.inheritedTypes {
                let typeText = inheritance.type.description.trimmingCharacters(in: .whitespaces)
                if typeText.contains("Sendable") {
                    return true
                }
            }
        }
        
        // Check for @unchecked attribute
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
        
        // Rule 2: Underscore functions must be private
        if isInUnderscoreFunction && isInSendableClass {
            checkUnderscoreFunctionPrivacy(node)
        }
        
        // Visit children
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
                message: "Underscore functions must be private",
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
                
                // Rule 1: Mutable properties must use underscore prefix
                if variableDecl.bindingSpecifier.text == "var" && !variableName.hasPrefix("_") {
                    let location = sourceLocationConverter.location(for: variableDecl.positionAfterSkippingLeadingTrivia)
                    addViolation(
                        line: location.line,
                        message: "Mutable property must use underscore prefix for thread safety",
                        suggestion: "Change 'var \(variableName)' to 'private var _\(variableName)'"
                    )
                }
                
                // Rule 2: Underscore variables must be private
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
            }
        }
    }
    
    // MARK: - Simple Underscore Access Checking
    
    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        if isInSendableClass {
            checkUnderscoreAccess(node.baseName.text, at: node.positionAfterSkippingLeadingTrivia)
        }
        return super.visit(node)
    }
    
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        if isInSendableClass {
            let memberName = node.declName.baseName.text
            if memberName.hasPrefix("_") {
                checkUnderscoreAccess(memberName, at: node.positionAfterSkippingLeadingTrivia)
            }
        }
        return super.visit(node)
    }
    
    private func checkUnderscoreAccess(_ name: String, at position: AbsolutePosition) {
        guard name.hasPrefix("_") else { return }
        guard let currentFunction = currentFunction else { return }
        guard !isInUnderscoreFunction else { return } // Underscore functions can access underscore properties
        guard !isInQueueWrapper else { return } // Queue protected access is fine
        
        let location = sourceLocationConverter.location(for: position)
        addViolation(
            line: location.line,
            message: "Function '\(currentFunction.name.text)' cannot directly access \(name). Use queue protection",
            suggestion: "Wrap in queue wrapper method"
        )
    }
    
    // MARK: - Simple Queue Wrapper Detection
    
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if isInSendableClass {
            // Check if this is a configured queue wrapper method
            var methodName: String?
            
            if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) {
                methodName = memberAccess.declName.baseName.text
            } else if let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self) {
                methodName = declRef.baseName.text
            }
            
            if let method = methodName, config.queueWrapperMethods.contains(method) {
                // Simple: set queue wrapper flag for children
                let previousWrapper = isInQueueWrapper
                isInQueueWrapper = true
                
                for child in node.children(viewMode: .sourceAccurate) {
                    walk(child)
                }
                
                isInQueueWrapper = previousWrapper
                return .skipChildren
            }
            
            // Simple same-file function call checking
            if isInUnderscoreFunction {
                checkUnderscoreFunctionCalls(node)
            }
        }
        
        return super.visit(node)
    }
    
    // MARK: - Simple Same-File Function Call Checking
    
    private func checkUnderscoreFunctionCalls(_ functionCall: FunctionCallExprSyntax) {
        var functionName: String?
        
        if let identifierExpr = functionCall.calledExpression.as(DeclReferenceExprSyntax.self) {
            functionName = identifierExpr.baseName.text
        } else if let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self) {
            functionName = memberAccess.declName.baseName.text
        }
        
        guard let funcName = functionName else { return }
        guard !funcName.hasPrefix("_") else { return } // Underscore calling underscore is fine
        
        // Simple rule: If function exists in same file, it's a violation
        // If it doesn't exist in same file, we can't analyze it (tool limitation)
        if functionsInFile.contains(funcName) {
            let location = sourceLocationConverter.location(for: functionCall.positionAfterSkippingLeadingTrivia)
            addViolation(
                line: location.line,
                message: "Underscore function '\(currentFunction?.name.text ?? "")' cannot call non-underscore function '\(funcName)'. This can cause deadlocks",
                suggestion: "Only call other underscore functions from underscore functions"
            )
        }
        // If function not in same file: tool limitation, no violation reported
    }
    
    // MARK: - Helper Methods
    
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