#!/bin/bash
# Production AWS Configuration Script for Stash Opus Player
# This script configures AWS credentials for production use

set -e

echo "🔧 Configuring AWS credentials for Stash Opus Player production build..."

# Get current AWS identity to verify credentials
echo "📋 Checking current AWS configuration..."
aws sts get-caller-identity

# Extract account ID and other info
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region || echo "us-east-1")
USER_ARN=$(aws sts get-caller-identity --query Arn --output text)

echo "   Account ID: $ACCOUNT_ID"
echo "   Region: $REGION"
echo "   User/Role: $USER_ARN"

# Create secure AWS properties file for the Android app
CONFIG_FILE="app/src/main/assets/aws-config.properties"
mkdir -p "$(dirname "$CONFIG_FILE")"

echo "📝 Creating AWS configuration file: $CONFIG_FILE"

cat > "$CONFIG_FILE" << EOF
# AWS Configuration for Stash Opus Player
# Generated on: $(date)
# Account: $ACCOUNT_ID
# Region: $REGION

aws.region=$REGION
aws.account.id=$ACCOUNT_ID

# DynamoDB Table Names
dynamodb.table.profiles=StashOpusUserAudioProfiles
dynamodb.table.analytics=StashOpusListeningAnalytics
dynamodb.table.sync=StashOpusDeviceSync

# Connection settings
connection.timeout=30000
read.timeout=30000
max.retry.attempts=3

# Debug settings (disable for production)
debug.enabled=false
logging.level=WARN
EOF

echo "✅ AWS configuration file created"

# Create local gradle properties for build-time configuration
GRADLE_PROPS="local.properties"
echo "📝 Updating $GRADLE_PROPS with AWS configuration..."

# Backup existing local.properties
if [ -f "$GRADLE_PROPS" ]; then
    cp "$GRADLE_PROPS" "$GRADLE_PROPS.backup"
    echo "   Backed up existing $GRADLE_PROPS"
fi

# Add AWS configuration to local.properties (used only for build)
grep -v "aws\." "$GRADLE_PROPS" 2>/dev/null > temp.properties || touch temp.properties
echo "" >> temp.properties
echo "# AWS Configuration (added $(date))" >> temp.properties
echo "aws.region=$REGION" >> temp.properties
echo "aws.account.id=$ACCOUNT_ID" >> temp.properties
mv temp.properties "$GRADLE_PROPS"

echo "✅ Updated $GRADLE_PROPS"

# Test DynamoDB connectivity
echo "🔍 Testing DynamoDB connectivity..."
python3 -c "
import boto3

try:
    dynamodb = boto3.resource('dynamodb', region_name='$REGION')
    
    # List our tables
    tables = ['StashOpusUserAudioProfiles', 'StashOpusListeningAnalytics', 'StashOpusDeviceSync']
    
    for table_name in tables:
        table = dynamodb.Table(table_name)
        status = table.table_status
        print(f'   ✅ {table_name}: {status}')
        
    print('🎉 All DynamoDB tables are accessible!')
    
except Exception as e:
    print(f'❌ DynamoDB connectivity test failed: {e}')
    exit(1)
"

echo ""
echo "🎉 AWS configuration completed successfully!"
echo ""
echo "📋 Summary:"
echo "   - AWS credentials: Using current AWS CLI configuration"
echo "   - Region: $REGION"
echo "   - Account: $ACCOUNT_ID"
echo "   - DynamoDB tables: 3 tables configured and accessible"
echo "   - Configuration file: $CONFIG_FILE"
echo ""
echo "💡 Next steps:"
echo "   1. Build the app: ./gradlew assembleDebug"
echo "   2. Test cloud sync in Settings"
echo "   3. Build production release: ./gradlew assembleRelease"
echo ""
echo "🔐 Security note:"
echo "   The app will use AWS credentials from the device's environment."
echo "   For production deployment, ensure proper IAM permissions are configured."