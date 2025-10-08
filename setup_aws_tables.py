#!/usr/bin/env python3
"""
AWS DynamoDB Table Setup Script for Stash Opus Player

This script creates the necessary DynamoDB tables for the cloud sync functionality.
Run this script once to set up your AWS environment before using the app.

Requirements:
- Python 3.6+
- boto3 library (pip install boto3)
- AWS credentials configured (via AWS CLI, environment variables, or IAM role)

Usage:
    python setup_aws_tables.py [--region us-east-1] [--dry-run]
"""

import boto3
import json
import argparse
import sys
from botocore.exceptions import ClientError


def create_user_audio_profiles_table(dynamodb, table_name="StashOpusUserAudioProfiles"):
    """Create the UserAudioProfiles table"""
    try:
        table = dynamodb.create_table(
            TableName=table_name,
            KeySchema=[
                {
                    'AttributeName': 'userId',
                    'KeyType': 'HASH'  # Partition key
                },
                {
                    'AttributeName': 'profileId', 
                    'KeyType': 'RANGE'  # Sort key
                }
            ],
            AttributeDefinitions=[
                {
                    'AttributeName': 'userId',
                    'AttributeType': 'S'
                },
                {
                    'AttributeName': 'profileId',
                    'AttributeType': 'S'
                },
                {
                    'AttributeName': 'deviceId',
                    'AttributeType': 'S'
                },
                {
                    'AttributeName': 'lastModified',
                    'AttributeType': 'N'
                }
            ],
            GlobalSecondaryIndexes=[
                {
                    'IndexName': 'DeviceIdIndex',
                    'KeySchema': [
                        {
                            'AttributeName': 'deviceId',
                            'KeyType': 'HASH'
                        }
                    ],
                    'Projection': {
                        'ProjectionType': 'ALL'
                    }
                },
                {
                    'IndexName': 'LastModifiedIndex',
                    'KeySchema': [
                        {
                            'AttributeName': 'userId',
                            'KeyType': 'HASH'
                        },
                        {
                            'AttributeName': 'lastModified',
                            'KeyType': 'RANGE'
                        }
                    ],
                    'Projection': {
                        'ProjectionType': 'ALL'
                    }
                }
            ],
            BillingMode='PAY_PER_REQUEST',
            Tags=[
                {
                    'Key': 'Application',
                    'Value': 'StashOpusPlayer'
                },
                {
                    'Key': 'Environment',
                    'Value': 'Production'
                }
            ]
        )
        
        # Wait until the table exists
        table.wait_until_exists()
        print(f"✅ Created table: {table_name}")
        return True
        
    except ClientError as e:
        if e.response['Error']['Code'] == 'ResourceInUseException':
            print(f"⚠️  Table {table_name} already exists")
            return True
        else:
            print(f"❌ Error creating table {table_name}: {e}")
            return False


def create_listening_analytics_table(dynamodb, table_name="StashOpusListeningAnalytics"):
    """Create the ListeningAnalytics table"""
    try:
        table = dynamodb.create_table(
            TableName=table_name,
            KeySchema=[
                {
                    'AttributeName': 'userId',
                    'KeyType': 'HASH'  # Partition key
                },
                {
                    'AttributeName': 'sessionId',
                    'KeyType': 'RANGE'  # Sort key
                }
            ],
            AttributeDefinitions=[
                {
                    'AttributeName': 'userId',
                    'AttributeType': 'S'
                },
                {
                    'AttributeName': 'sessionId',
                    'AttributeType': 'S'
                },
                {
                    'AttributeName': 'deviceId',
                    'AttributeType': 'S'
                },
                {
                    'AttributeName': 'timestamp',
                    'AttributeType': 'N'
                }
            ],
            GlobalSecondaryIndexes=[
                {
                    'IndexName': 'DeviceIdIndex',
                    'KeySchema': [
                        {
                            'AttributeName': 'deviceId',
                            'KeyType': 'HASH'
                        },
                        {
                            'AttributeName': 'timestamp',
                            'KeyType': 'RANGE'
                        }
                    ],
                    'Projection': {
                        'ProjectionType': 'ALL'
                    }
                },
                {
                    'IndexName': 'TimestampIndex',
                    'KeySchema': [
                        {
                            'AttributeName': 'userId',
                            'KeyType': 'HASH'
                        },
                        {
                            'AttributeName': 'timestamp',
                            'KeyType': 'RANGE'
                        }
                    ],
                    'Projection': {
                        'ProjectionType': 'ALL'
                    }
                }
            ],
            BillingMode='PAY_PER_REQUEST',
            Tags=[
                {
                    'Key': 'Application',
                    'Value': 'StashOpusPlayer'
                },
                {
                    'Key': 'Environment',
                    'Value': 'Production'
                }
            ]
        )
        
        # Wait until the table exists
        table.wait_until_exists()
        print(f"✅ Created table: {table_name}")
        return True
        
    except ClientError as e:
        if e.response['Error']['Code'] == 'ResourceInUseException':
            print(f"⚠️  Table {table_name} already exists")
            return True
        else:
            print(f"❌ Error creating table {table_name}: {e}")
            return False


def create_device_sync_table(dynamodb, table_name="StashOpusDeviceSync"):
    """Create the DeviceSync table"""
    try:
        table = dynamodb.create_table(
            TableName=table_name,
            KeySchema=[
                {
                    'AttributeName': 'userId',
                    'KeyType': 'HASH'  # Partition key
                },
                {
                    'AttributeName': 'deviceId',
                    'KeyType': 'RANGE'  # Sort key
                }
            ],
            AttributeDefinitions=[
                {
                    'AttributeName': 'userId',
                    'AttributeType': 'S'
                },
                {
                    'AttributeName': 'deviceId',
                    'AttributeType': 'S'
                },
                {
                    'AttributeName': 'lastSyncTime',
                    'AttributeType': 'N'
                }
            ],
            GlobalSecondaryIndexes=[
                {
                    'IndexName': 'LastSyncTimeIndex',
                    'KeySchema': [
                        {
                            'AttributeName': 'userId',
                            'KeyType': 'HASH'
                        },
                        {
                            'AttributeName': 'lastSyncTime',
                            'KeyType': 'RANGE'
                        }
                    ],
                    'Projection': {
                        'ProjectionType': 'ALL'
                    }
                }
            ],
            BillingMode='PAY_PER_REQUEST',
            Tags=[
                {
                    'Key': 'Application',
                    'Value': 'StashOpusPlayer'
                },
                {
                    'Key': 'Environment',
                    'Value': 'Production'
                }
            ]
        )
        
        # Wait until the table exists
        table.wait_until_exists()
        print(f"✅ Created table: {table_name}")
        return True
        
    except ClientError as e:
        if e.response['Error']['Code'] == 'ResourceInUseException':
            print(f"⚠️  Table {table_name} already exists")
            return True
        else:
            print(f"❌ Error creating table {table_name}: {e}")
            return False


def test_table_access(dynamodb, table_names):
    """Test that we can access the created tables"""
    print("\n🔍 Testing table access...")
    
    for table_name in table_names:
        try:
            table = dynamodb.Table(table_name)
            table.load()
            print(f"✅ Can access table: {table_name}")
            
            # Print table info
            print(f"   - Item count: {table.item_count}")
            print(f"   - Table size: {table.table_size_bytes} bytes")
            print(f"   - Status: {table.table_status}")
            
        except ClientError as e:
            print(f"❌ Cannot access table {table_name}: {e}")


def insert_test_data(dynamodb):
    """Insert test data to verify tables work correctly"""
    print("\n📝 Inserting test data...")
    
    try:
        # Test user profile
        profiles_table = dynamodb.Table('StashOpusUserAudioProfiles')
        test_profile = {
            'userId': 'test-user-123',
            'profileId': 'default',
            'profileName': 'Test Profile',
            'deviceId': 'test-device-456',
            'isDefault': True,
            'version': '11.1.0',
            'lastModified': 1699123456789,
            'audioSettings': {
                'professional_processor_enabled': True,
                'compression_enabled': False,
                'compression_threshold': -12.0,
                'stereo_width': 1.0
            }
        }
        
        profiles_table.put_item(Item=test_profile)
        print("✅ Inserted test audio profile")
        
        # Test analytics data
        analytics_table = dynamodb.Table('StashOpusListeningAnalytics')
        test_analytics = {
            'userId': 'test-user-123',
            'sessionId': 'session-789',
            'deviceId': 'test-device-456',
            'timestamp': 1699123456789,
            'playbackData': {
                'trackName': 'Test Track',
                'artist': 'Test Artist',
                'duration': 180000,
                'playCount': 1
            },
            'audioSettings': {
                'eq_preset': 'rock',
                'volume_level': 0.8
            }
        }
        
        analytics_table.put_item(Item=test_analytics)
        print("✅ Inserted test analytics data")
        
        # Test device sync
        sync_table = dynamodb.Table('StashOpusDeviceSync')
        test_sync = {
            'userId': 'test-user-123',
            'deviceId': 'test-device-456',
            'deviceName': 'Test Android Device',
            'appVersion': '11.1.0',
            'lastSyncTime': 1699123456789,
            'syncEnabled': True,
            'syncStatus': 'SUCCESS'
        }
        
        sync_table.put_item(Item=test_sync)
        print("✅ Inserted test device sync data")
        
        return True
        
    except ClientError as e:
        print(f"❌ Error inserting test data: {e}")
        return False


def cleanup_test_data(dynamodb):
    """Clean up test data"""
    print("\n🧹 Cleaning up test data...")
    
    try:
        # Delete test profile
        profiles_table = dynamodb.Table('StashOpusUserAudioProfiles')
        profiles_table.delete_item(Key={'userId': 'test-user-123', 'profileId': 'default'})
        
        # Delete test analytics
        analytics_table = dynamodb.Table('StashOpusListeningAnalytics')
        analytics_table.delete_item(Key={'userId': 'test-user-123', 'sessionId': 'session-789'})
        
        # Delete test sync data
        sync_table = dynamodb.Table('StashOpusDeviceSync')
        sync_table.delete_item(Key={'userId': 'test-user-123', 'deviceId': 'test-device-456'})
        
        print("✅ Test data cleaned up")
        return True
        
    except ClientError as e:
        print(f"❌ Error cleaning up test data: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(description='Set up AWS DynamoDB tables for Stash Opus Player')
    parser.add_argument('--region', default='us-east-1', help='AWS region (default: us-east-1)')
    parser.add_argument('--dry-run', action='store_true', help='Show what would be created without actually creating')
    parser.add_argument('--test-data', action='store_true', help='Insert and clean up test data')
    parser.add_argument('--cleanup-only', action='store_true', help='Only clean up test data')
    
    args = parser.parse_args()
    
    print(f"🚀 Setting up AWS DynamoDB tables for Stash Opus Player")
    print(f"   Region: {args.region}")
    print(f"   Dry run: {args.dry_run}")
    print()
    
    if args.dry_run:
        print("🔍 DRY RUN MODE - No actual changes will be made")
        print("Tables that would be created:")
        print("  - StashOpusUserAudioProfiles")
        print("  - StashOpusListeningAnalytics") 
        print("  - StashOpusDeviceSync")
        return
    
    try:
        # Initialize DynamoDB resource
        dynamodb = boto3.resource('dynamodb', region_name=args.region)
        
        table_names = [
            'StashOpusUserAudioProfiles',
            'StashOpusListeningAnalytics', 
            'StashOpusDeviceSync'
        ]
        
        if args.cleanup_only:
            cleanup_test_data(dynamodb)
            return
        
        print("📋 Creating DynamoDB tables...")
        
        # Create tables
        success_count = 0
        if create_user_audio_profiles_table(dynamodb):
            success_count += 1
        if create_listening_analytics_table(dynamodb):
            success_count += 1
        if create_device_sync_table(dynamodb):
            success_count += 1
        
        print(f"\n📊 Created {success_count}/3 tables successfully")
        
        # Test table access
        test_table_access(dynamodb, table_names)
        
        # Insert test data if requested
        if args.test_data:
            if insert_test_data(dynamodb):
                print("\n⏱️  Waiting 5 seconds before cleanup...")
                import time
                time.sleep(5)
                cleanup_test_data(dynamodb)
        
        print(f"\n🎉 Setup complete!")
        print(f"💡 Next steps:")
        print(f"   1. Configure AWS credentials in your app")
        print(f"   2. Test the connection from Settings → Cloud Sync → Test Connection")
        print(f"   3. Enable cloud sync and sync your audio profiles")
        print(f"\n💰 Cost estimate:")
        print(f"   - Light usage (1 sync/day): ~$0.01-0.05/month")
        print(f"   - Heavy usage (frequent sync): ~$0.10-0.50/month")
        
    except Exception as e:
        print(f"❌ Setup failed: {e}")
        print(f"\n🔧 Troubleshooting:")
        print(f"   1. Check AWS credentials: aws sts get-caller-identity")
        print(f"   2. Verify permissions: DynamoDB Create/Describe/List permissions")
        print(f"   3. Check region: {args.region}")
        sys.exit(1)


if __name__ == "__main__":
    main()