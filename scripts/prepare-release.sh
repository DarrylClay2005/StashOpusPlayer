#!/bin/bash

# Stash Audio Player - Release Preparation Script
# This script prepares the app for production release

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_TYPE="release"
KEYSTORE_PATH=""
KEYSTORE_PASSWORD=""
KEY_ALIAS=""
KEY_PASSWORD=""

echo -e "${BLUE}🚀 Stash Audio Player - Release Preparation${NC}"
echo "================================"

# Function to print colored messages
print_step() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if Android SDK is available
    if [ -z "$ANDROID_HOME" ]; then
        print_error "ANDROID_HOME environment variable is not set"
        exit 1
    fi
    
    # Check if Java is available
    if ! command -v java &> /dev/null; then
        print_error "Java is not installed or not in PATH"
        exit 1
    fi
    
    # Check Gradle
    if [ ! -f "$PROJECT_ROOT/gradlew" ]; then
        print_error "Gradle wrapper not found"
        exit 1
    fi
    
    print_step "Prerequisites check passed"
}

# Validate version and build configuration
validate_build_config() {
    print_info "Validating build configuration..."
    
    # Check if version has been updated
    VERSION_NAME=$(grep 'versionName' "$PROJECT_ROOT/app/build.gradle" | head -n1 | sed 's/.*"\(.*\)".*/\1/')
    VERSION_CODE=$(grep 'versionCode' "$PROJECT_ROOT/app/build.gradle" | head -n1 | sed 's/.*\([0-9]\+\).*/\1/')
    
    print_info "Version Name: $VERSION_NAME"
    print_info "Version Code: $VERSION_CODE"
    
    # Validate version format (should be semantic versioning)
    if ! [[ "$VERSION_NAME" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-.*)?$ ]]; then
        print_warning "Version name doesn't follow semantic versioning (x.y.z)"
    fi
    
    print_step "Build configuration validated"
}

# Check for signing configuration
check_signing_config() {
    print_info "Checking signing configuration..."
    
    # Look for keystore configuration in local.properties
    LOCAL_PROPS="$PROJECT_ROOT/local.properties"
    if [ -f "$LOCAL_PROPS" ]; then
        # Check for uncommented RELEASE_STORE_FILE
        if grep -q "^RELEASE_STORE_FILE" "$LOCAL_PROPS"; then
            KEYSTORE_PATH=$(grep "^RELEASE_STORE_FILE" "$LOCAL_PROPS" | cut -d'=' -f2)
            if [ -n "$KEYSTORE_PATH" ]; then
                print_step "Release keystore configured: $KEYSTORE_PATH"
                
                # Verify keystore exists
                if [ ! -f "$KEYSTORE_PATH" ]; then
                    print_error "Keystore file not found: $KEYSTORE_PATH"
                    exit 1
                fi
            else
                print_warning "RELEASE_STORE_FILE is empty. Using debug keystore."
            fi
        else
            print_warning "No release keystore configured. Using debug keystore."
        fi
    else
        print_warning "local.properties not found. Using debug keystore."
    fi
}

# Clean and prepare build environment
prepare_build_environment() {
    print_info "Preparing build environment..."
    
    cd "$PROJECT_ROOT"
    
    # Clean previous builds
    print_info "Cleaning previous builds..."
    ./gradlew clean --quiet
    
    # Clear Gradle cache if needed
    if [ "$1" == "--clear-cache" ]; then
        print_info "Clearing Gradle cache..."
        rm -rf ~/.gradle/caches/
        rm -rf .gradle/
    fi
    
    print_step "Build environment prepared"
}

# Run tests before building
run_tests() {
    print_info "Running tests..."
    
    cd "$PROJECT_ROOT"
    
    # Run unit tests
    if ./gradlew testReleaseUnitTest --quiet; then
        print_step "Unit tests passed"
    else
        print_error "Unit tests failed"
        exit 1
    fi
    
    # Run lint checks
    if ./gradlew lintRelease --quiet; then
        print_step "Lint checks passed"
    else
        print_warning "Lint checks failed (continuing anyway)"
    fi
}

# Build the release APK/AAB
build_release() {
    print_info "Building release APK and AAB..."
    
    cd "$PROJECT_ROOT"
    
    # Build release APK
    print_info "Building release APK..."
    if ./gradlew assembleRelease; then
        print_step "Release APK built successfully"
        
        # Find the APK
        RELEASE_APK=$(find "$PROJECT_ROOT/app/build/outputs/apk/release" -name "*.apk" | head -n1)
        if [ -f "$RELEASE_APK" ]; then
            APK_SIZE=$(du -h "$RELEASE_APK" | cut -f1)
            print_info "Release APK: $RELEASE_APK ($APK_SIZE)"
        fi
    else
        print_error "Failed to build release APK"
        exit 1
    fi
    
    # Build release AAB (Android App Bundle)
    print_info "Building release AAB..."
    if ./gradlew bundleRelease; then
        print_step "Release AAB built successfully"
        
        # Find the AAB
        RELEASE_AAB=$(find "$PROJECT_ROOT/app/build/outputs/bundle/release" -name "*.aab" | head -n1)
        if [ -f "$RELEASE_AAB" ]; then
            AAB_SIZE=$(du -h "$RELEASE_AAB" | cut -f1)
            print_info "Release AAB: $RELEASE_AAB ($AAB_SIZE)"
        fi
    else
        print_error "Failed to build release AAB"
        exit 1
    fi
}

# Generate build report
generate_build_report() {
    print_info "Generating build report..."
    
    cd "$PROJECT_ROOT"
    
    REPORT_FILE="$PROJECT_ROOT/build-report-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "$REPORT_FILE" << EOF
Stash Audio Player - Build Report
Generated: $(date)
==================================

Build Configuration:
- Version Name: $VERSION_NAME
- Version Code: $VERSION_CODE
- Build Type: Release
- Minify Enabled: Yes
- Shrink Resources: Yes

Artifacts:
- Release APK: $RELEASE_APK ($APK_SIZE)
- Release AAB: $RELEASE_AAB ($AAB_SIZE)

Signing:
- Keystore: $([ -n "$KEYSTORE_PATH" ] && echo "Release keystore" || echo "Debug keystore")

Environment:
- Java Version: $(java -version 2>&1 | head -n1)
- Gradle Version: $(./gradlew --version | grep "Gradle" | head -n1)
- Android SDK: $ANDROID_HOME
- Build Host: $(hostname)

EOF
    
    print_step "Build report generated: $REPORT_FILE"
}

# Verify APK integrity
verify_apk() {
    print_info "Verifying APK integrity..."
    
    if [ -f "$RELEASE_APK" ]; then
        # Check if APK is properly signed
        if command -v jarsigner &> /dev/null; then
            if jarsigner -verify "$RELEASE_APK" > /dev/null 2>&1; then
                print_step "APK signature verified"
            else
                print_error "APK signature verification failed"
                exit 1
            fi
        fi
        
        # Basic APK structure check
        if unzip -t "$RELEASE_APK" > /dev/null 2>&1; then
            print_step "APK structure is valid"
        else
            print_error "APK structure is corrupted"
            exit 1
        fi
    fi
}

# Main execution
main() {
    print_info "Starting release preparation process..."
    
    # Parse command line arguments
    CLEAR_CACHE=false
    RUN_TESTS=true
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --clear-cache)
                CLEAR_CACHE=true
                shift
                ;;
            --skip-tests)
                RUN_TESTS=false
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [--clear-cache] [--skip-tests]"
                echo "  --clear-cache  Clear Gradle cache before building"
                echo "  --skip-tests   Skip running tests"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Execute preparation steps
    check_prerequisites
    validate_build_config
    check_signing_config
    
    if [ "$CLEAR_CACHE" = true ]; then
        prepare_build_environment --clear-cache
    else
        prepare_build_environment
    fi
    
    if [ "$RUN_TESTS" = true ]; then
        run_tests
    fi
    
    build_release
    verify_apk
    generate_build_report
    
    echo
    print_step "Release preparation completed successfully!"
    echo
    print_info "Next steps:"
    echo "  1. Test the release APK/AAB thoroughly"
    echo "  2. Upload to Google Play Console (AAB) or distribute APK"
    echo "  3. Update release notes and changelog"
    echo "  4. Tag the release in version control"
    echo
    print_info "Release artifacts:"
    echo "  APK: $RELEASE_APK"
    echo "  AAB: $RELEASE_AAB"
    echo "  Report: $REPORT_FILE"
}

# Run main function
main "$@"