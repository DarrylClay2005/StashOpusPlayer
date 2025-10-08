# Release Scripts

This directory contains scripts for preparing and managing releases of the Stash Audio Player.

## prepare-release.sh

A comprehensive script that automates the production release preparation process.

### Features

- **Prerequisites Check**: Validates that all required tools (Java, Android SDK, Gradle) are available
- **Build Configuration Validation**: Checks version name and code formatting
- **Signing Configuration**: Verifies release keystore setup or falls back to debug keystore
- **Environment Preparation**: Cleans build artifacts and optionally clears Gradle cache
- **Testing**: Runs unit tests and lint checks before building
- **Release Building**: Creates both APK and AAB (Android App Bundle) artifacts
- **Integrity Verification**: Validates APK signature and structure
- **Build Reporting**: Generates detailed build reports with artifact information

### Usage

```bash
# Basic release preparation
./scripts/prepare-release.sh

# Clear Gradle cache before building (useful for clean builds)
./scripts/prepare-release.sh --clear-cache

# Skip tests for faster builds (not recommended for production)
./scripts/prepare-release.sh --skip-tests

# Help
./scripts/prepare-release.sh --help
```

### Prerequisites

1. **Android SDK**: Set `ANDROID_HOME` environment variable
2. **Java**: JDK 8 or higher
3. **Keystore** (optional): Configure in `local.properties`:
   ```
   RELEASE_STORE_FILE=path/to/keystore.jks
   RELEASE_STORE_PASSWORD=your_keystore_password
   RELEASE_KEY_ALIAS=your_key_alias
   RELEASE_KEY_PASSWORD=your_key_password
   ```

### Output

The script generates:
- Release APK: `app/build/outputs/apk/release/`
- Release AAB: `app/build/outputs/bundle/release/`
- Build Report: `build-report-YYYYMMDD-HHMMSS.txt`

### Next Steps After Running

1. **Test thoroughly**: Install and test the release APK on various devices
2. **Upload to Play Console**: Use the AAB file for Google Play Store
3. **Update documentation**: Update release notes and changelog
4. **Tag release**: Create a git tag for the release version

### Troubleshooting

**"ANDROID_HOME not set"**: Set the environment variable to your Android SDK path
```bash
export ANDROID_HOME=/path/to/Android/Sdk
```

**"Keystore not found"**: Either create a release keystore or remove keystore configuration to use debug signing

**"Tests failed"**: Fix failing tests or use `--skip-tests` flag (not recommended for production)

**"Build failed"**: Check the Gradle output for specific error messages and resolve build issues

### Security Notes

- Never commit keystore files to version control
- Keep keystore passwords secure and separate from the codebase
- Use environment variables or secure storage for sensitive build configurations