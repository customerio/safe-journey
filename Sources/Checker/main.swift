import Foundation
import SafeJourney

// MARK: - Main Execution

func printHelp() {
    print("""
    SafeJourney Pattern Checker - Basic Pattern Matcher
    
    A simple checker for SafeJourney naming conventions. Has limitations but provides
    useful guard rails for teams using the underscore prefix pattern.
    
    USAGE:
        sj [OPTIONS] [PATH]
    
    OPTIONS:
        --help                          Show this help message
        --version                       Show version information
        --config FILE                   Load configuration from JSON file
        --queue-methods METHOD1,METHOD2 Custom queue wrapper methods (comma-separated)
    
    ARGUMENTS:
        PATH            Directory or file to check (default: current directory)
    
    EXAMPLES:
        sj                                              # Check current directory
        sj Sources/                                     # Check Sources directory  
        sj MyClass.swift                                # Check single file
        sj --config safejourney.json Sources/          # Use custom configuration
        sj --queue-methods asyncUtility,customSync Sources/  # Custom queue methods
    
    LIMITATIONS:
        - Only analyzes functions within the same file
        - Does not analyze cross-file or external function calls
        - Basic pattern matching, not comprehensive static analysis
        
    For more info: https://github.com/customerio/safe-journey
    """)
}

func printVersion() {
    print("SafeJourney Checker v1.0.0")
    print("https://github.com/customerio/safe-journey")
}

func main() {
    let args = CommandLine.arguments
    var targetPath = "."
    var configFile: String?
    var customQueueMethods: [String]?
    
    // Parse arguments
    var i = 1
    while i < args.count {
        let arg = args[i]
        
        switch arg {
        case "--help", "-h":
            printHelp()
            exit(0)
        case "--version", "-v":
            printVersion()
            exit(0)
        case "--config":
            i += 1
            if i >= args.count {
                print("Error: --config requires a file path")
                exit(1)
            }
            configFile = args[i]
        case "--queue-methods":
            i += 1
            if i >= args.count {
                print("Error: --queue-methods requires comma-separated method names")
                exit(1)
            }
            customQueueMethods = args[i].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        default:
            if !arg.hasPrefix("--") {
                targetPath = arg
            } else {
                print("Error: Unknown option \(arg)")
                printHelp()
                exit(1)
            }
        }
        i += 1
    }
    
    // Initialize configuration
    var config: CheckerConfig
    
    if let configFile = configFile {
        // Load from config file
        if let loadedConfig = CheckerConfig.load(from: configFile) {
            config = loadedConfig
            print("📋 Loaded configuration from: \(configFile)")
        } else {
            print("Error: Could not load configuration from \(configFile)")
            exit(1)
        }
    } else {
        // Use default configuration
        config = CheckerConfig.default
    }
    
    // Override queue methods if specified via CLI
    if let customQueueMethods = customQueueMethods {
        let allMethods = Array(Set(config.queueWrapperMethods + customQueueMethods))
        config = CheckerConfig(
            excludePatterns: config.excludePatterns,
            queueWrapperMethods: allMethods
        )
        print("🔧 Using custom queue wrapper methods: \(allMethods.joined(separator: ", "))")
    }
    
    // Initialize checker with configuration (using simplified implementation)
    let checker = SimpleSafeJourneyChecker(config: config)
    
    print("🔍 SafeJourney Pattern Checker")
    print("🎯 Checking: \(targetPath)")
    print()
    
    // Check target
    let violations: [Violation]
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    
    if fileManager.fileExists(atPath: targetPath, isDirectory: &isDirectory) {
        if isDirectory.boolValue {
            violations = checker.checkDirectory(targetPath)
        } else {
            violations = checker.checkSingleFile(targetPath)
        }
    } else {
        print("Error: Path '\(targetPath)' does not exist")
        exit(1)
    }
    
    // Report results
    if violations.isEmpty {
        print("✅ Perfect! No SafeJourney violations found")
        exit(0)
    } else {
        print("Found \(violations.count) violations:")
        print()
        
        for violation in violations {
            print("\(violation.type.symbol) \(violation.file):\(violation.line): \(violation.message)")
            if let suggestion = violation.suggestion {
                print("   💡 Suggestion: \(suggestion)")
            }
            print()
        }
        
        let errorCount = violations.filter { $0.type == .error }.count
        let warningCount = violations.filter { $0.type == .warning }.count
        
        print("📊 Summary: \(errorCount) errors, \(warningCount) warnings")
        
        if errorCount > 0 {
            print("🚨 Critical violations found! Please fix errors before committing.")
            exit(1)
        } else {
            print("⚠️  Warnings found. Consider addressing for better thread safety.")
            exit(0)
        }
    }
}

main()