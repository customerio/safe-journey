# Git Hooks for SafeJourney

This directory contains git hooks that automatically enforce the SafeJourney pattern in your repository. These hooks help prevent thread safety violations from being committed or pushed to your codebase.

## 🚀 Quick Install

```bash
# Install both pre-commit and pre-push hooks
./git-hooks/install.sh

# Install only pre-commit hook
./git-hooks/install.sh --pre-commit-only

# Install only pre-push hook  
./git-hooks/install.sh --pre-push-only
```

## 📋 Available Hooks

### Pre-commit Hook
- **Purpose**: Checks staged Swift files before allowing a commit
- **Scope**: Only files that are staged for commit
- **Configuration**: Uses default or custom config if available
- **Failure behavior**: Blocks commit if critical errors found
- **Bypass**: `git commit --no-verify` (not recommended)

### Pre-push Hook
- **Purpose**: Comprehensive check of all Swift files before push
- **Scope**: All Swift files in the repository
- **Configuration**: Uses strict settings by default
- **Failure behavior**: Blocks push if critical errors found
- **Bypass**: `git push --no-verify` (not recommended)

## 🔧 Configuration

### Default Behavior
The hooks will work out-of-the-box with sensible defaults:
- Check `Sources/` directory
- Use strict configuration for pre-push
- Allow warnings but block on errors
- Download checker automatically if needed

### Custom Configuration
Create `safe-journey-config.json` in your repository root:

```json
{
  "checkMutableProperties": true,
  "checkUnderscoreAccess": true,
  "checkNestedQueues": true,
  "requireUnderscorePrivate": true,
  "excludePatterns": ["Tests", "Mock"],
  "onlyCheckSendable": true
}
```

### Environment Variables
You can customize hook behavior with environment variables:

```bash
# Custom source paths
export SAFE_JOURNEY_PATHS="Sources/ MyModule/"

# Custom checker URL
export SAFE_JOURNEY_CHECKER_URL="https://example.com/checker.swift"

# Skip download if checker exists
export SAFE_JOURNEY_SKIP_DOWNLOAD="true"
```

## 📖 How It Works

### Pre-commit Hook Flow
1. **Check staged files**: Only runs if Swift files are staged
2. **Download checker**: Automatically downloads if not present
3. **Run analysis**: Checks staged files for violations
4. **Report results**: Shows violations with helpful suggestions
5. **Block or allow**: Blocks commit if critical errors found

### Pre-push Hook Flow
1. **Analyze push**: Examines what's being pushed and where
2. **Comprehensive check**: Checks all Swift files in repository
3. **Strict validation**: Uses stricter rules than pre-commit
4. **Detailed reporting**: Shows complete violation summary
5. **Block or allow**: Blocks push if any errors found

## 🎯 Example Output

### Successful Check
```
🔍 Running SafeJourney pre-commit check...
📝 Staged Swift files: Sources/MyClass.swift
📋 Using default configuration
⚡ Running: ./safe-journey-checker.swift Sources/
✅ All SafeJourney checks passed!
🎉 Pre-commit check passed! Commit proceeding...
```

### Failed Check
```
❌ SafeJourney violations found:
❌ Sources/MyClass.swift:42: Function 'updateState' cannot directly access _data. Use queue protection
   💡 Suggestion: Wrap in queue.sync { } or queue.async { }

📊 Summary: 1 errors, 0 warnings
🚨 Commit blocked due to critical violations!
```

## 🛠️ Management Commands

### Install Hooks
```bash
./git-hooks/install.sh                 # Install both hooks
./git-hooks/install.sh --pre-commit-only  # Only pre-commit
./git-hooks/install.sh --pre-push-only    # Only pre-push
```

### Uninstall Hooks
```bash
./git-hooks/install.sh --uninstall
```

### Manual Installation
```bash
# Copy hooks manually
cp git-hooks/pre-commit .git/hooks/pre-commit
cp git-hooks/pre-push .git/hooks/pre-push
chmod +x .git/hooks/pre-commit .git/hooks/pre-push
```

## 🔧 Troubleshooting

### Hook Not Running
```bash
# Check if hooks are executable
ls -la .git/hooks/pre-*

# Re-install with correct permissions
./git-hooks/install.sh
```

### Checker Download Fails
```bash
# Manually download checker
curl -O https://raw.githubusercontent.com/customerio/safe-journey/main/src/safe-journey-checker.swift
chmod +x safe-journey-checker.swift

# Or set custom URL
export SAFE_JOURNEY_CHECKER_URL="https://your-mirror.com/checker.swift"
```

### False Positives
```bash
# Create custom config to adjust rules
cat > safe-journey-config.json << 'EOF'
{
  "checkMutableProperties": false,
  "checkUnderscoreAccess": true,
  "excludePatterns": ["Tests", "Mock", "Generated"]
}
EOF
```

### Bypass Hooks (Emergency)
```bash
# Bypass pre-commit (not recommended)
git commit --no-verify

# Bypass pre-push (not recommended)  
git push --no-verify
```

## 🔍 Hook Customization

### Modify Source Paths
Edit the hooks to check different directories:

```bash
# In pre-commit and pre-push files, change:
SOURCE_PATHS="Sources/ MyModule/ OtherCode/"
```

### Change Configuration
```bash
# Use different config files for different hooks
# In pre-commit:
CONFIG_PATH="./safe-journey-precommit.json"

# In pre-push:
CONFIG_PATH="./safe-journey-prepush.json"
```

### Add Custom Logic
The hooks are shell scripts that can be extended with custom logic:

```bash
# Example: Skip checks for certain branches
if [ "$(git branch --show-current)" = "experimental" ]; then
    echo "Skipping checks for experimental branch"
    exit 0
fi
```

## 📚 Integration Examples

### With CI/CD
The git hooks complement CI/CD checks:

```yaml
# .github/workflows/check.yml
- name: Run SafeJourney
  uses: customerio/safe-journey@v1
  with:
    path: Sources/
    fail-on-error: true
```

### With Pre-commit Framework
```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: safe-journey
        name: SafeJourney
        entry: ./git-hooks/pre-commit
        language: script
        files: '\.swift$'
```

### With IDE Integration
Configure your IDE to run the hooks on save or before commit.

## 🤝 Contributing

Found an issue with the hooks? Have an improvement idea?

1. Fork the repository
2. Create your feature branch
3. Test your changes
4. Submit a pull request

## 📄 License

These git hooks are part of the SafeJourney project and are licensed under the MIT License.