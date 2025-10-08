#!/usr/bin/env python3
"""
DynamoDB Integration Test Client for Stash Opus Player

This script tests the DynamoDB integration by simulating the operations
that the Android app would perform. Use this to verify your AWS setup
works correctly before testing on the actual device.

Requirements:
- Python 3.6+
- boto3 library (pip install boto3) 
- AWS credentials configured
- DynamoDB tables already set up (run setup_aws_tables.py first)

Usage:
    python test_dynamodb_integration.py [--region us-east-1]
"""

import boto3
import json
import argparse
import time
import uuid
from decimal import Decimal
from botocore.exceptions import ClientError


class StashOpusDynamoDBTester:
    def __init__(self, region='us-east-1'):
        self.dynamodb = boto3.resource('dynamodb', region_name=region)
        self.region = region
        self.test_user_id = f"test-user-{uuid.uuid4().hex[:8]}"
        self.test_device_id = f"test-device-{uuid.uuid4().hex[:8]}"
        
        # Table references
        self.profiles_table = self.dynamodb.Table('StashOpusUserAudioProfiles')
        self.analytics_table = self.dynamodb.Table('StashOpusListeningAnalytics')
        self.sync_table = self.dynamodb.Table('StashOpusDeviceSync')
    
    def test_user_audio_profiles(self):
        """Test UserAudioProfiles table operations"""
        print("🎵 Testing UserAudioProfiles operations...")
        
        try:
            # Create a test audio profile
            test_profile = {
                'userId': self.test_user_id,
                'profileId': 'default',
                'profileName': 'Test Default Profile',
                'deviceId': self.test_device_id,
                'isDefault': True,
                'version': '11.1.0',
                'lastModified': int(time.time() * 1000),
                'audioSettings': {
                    'professional_processor_enabled': True,
                    'compression_enabled': False,
                    'compression_threshold': Decimal('-12.0'),
                    'compression_ratio': Decimal('4.0'),
                    'compression_attack': Decimal('5.0'),
                    'compression_release': Decimal('50.0'),
                    'stereo_width': Decimal('1.0'),
                    'auto_gain_enabled': False,
                    'target_lufs': Decimal('-16.0'),
                    'crossfeed_enabled': False,
                    'tube_warmth': Decimal('0.0'),
                    'current_audio_profile': 'BALANCED',
                    'spectrum_analyzer_enabled': True,
                    'spectrum_sensitivity': Decimal('1.0'),
                    'spectrum_smoothing': Decimal('0.8'),
                    'enhanced_eq_enabled': False,
                    'enhanced_eq_preset': 'NORMAL',
                    'enhanced_band_levels': ''
                }
            }
            
            # Test CREATE operation
            print("  📝 Creating audio profile...")
            self.profiles_table.put_item(Item=test_profile)
            print("  ✅ Audio profile created successfully")
            
            # Test READ operation  
            print("  📖 Reading audio profile...")
            response = self.profiles_table.get_item(
                Key={'userId': self.test_user_id, 'profileId': 'default'}
            )
            
            if 'Item' in response:
                profile = response['Item']
                print(f"  ✅ Audio profile retrieved: {profile['profileName']}")
                print(f"     Settings count: {len(profile.get('audioSettings', {}))}")
            else:
                print("  ❌ Audio profile not found")
                return False
            
            # Test UPDATE operation
            print("  🔄 Updating audio profile...")
            self.profiles_table.update_item(
                Key={'userId': self.test_user_id, 'profileId': 'default'},
                UpdateExpression='SET profileName = :name, lastModified = :time',
                ExpressionAttributeValues={
                    ':name': 'Updated Test Profile',
                    ':time': int(time.time() * 1000)
                }
            )
            print("  ✅ Audio profile updated successfully")
            
            # Test QUERY operation (get all profiles for user)
            print("  🔍 Querying user profiles...")
            response = self.profiles_table.query(
                KeyConditionExpression=boto3.dynamodb.conditions.Key('userId').eq(self.test_user_id)
            )
            
            profiles = response['Items']
            print(f"  ✅ Found {len(profiles)} profile(s) for user")
            
            return True
            
        except ClientError as e:
            print(f"  ❌ Error testing audio profiles: {e}")
            return False
    
    def test_listening_analytics(self):
        """Test ListeningAnalytics table operations"""
        print("\n📊 Testing ListeningAnalytics operations...")
        
        try:
            # Create test analytics data
            session_id = f"session-{uuid.uuid4().hex[:8]}"
            test_analytics = {
                'userId': self.test_user_id,
                'sessionId': session_id,
                'deviceId': self.test_device_id,
                'timestamp': int(time.time() * 1000),
                'appVersion': '11.1.0',
                'sessionDuration': 180000,  # 3 minutes
                'playbackData': {
                    'trackName': 'Test Track Name',
                    'artist': 'Test Artist',
                    'album': 'Test Album',
                    'genre': 'Rock',
                    'duration': 240000,  # 4 minutes
                    'playCount': 1,
                    'skipCount': 0,
                    'completionPercentage': Decimal('95.5')
                },
                'audioSettings': {
                    'eq_preset': 'rock',
                    'volume_level': Decimal('0.8'),
                    'pitch_adjustment': Decimal('0.0'),
                    'speed_adjustment': Decimal('1.0'),
                    'professional_processor_enabled': True
                },
                'deviceInfo': {
                    'deviceModel': 'Pixel 7',
                    'osVersion': 'Android 14',
                    'appVersion': '11.1.0'
                }
            }
            
            # Test CREATE operation
            print("  📝 Creating analytics entry...")
            self.analytics_table.put_item(Item=test_analytics)
            print("  ✅ Analytics entry created successfully")
            
            # Test READ operation
            print("  📖 Reading analytics entry...")
            response = self.analytics_table.get_item(
                Key={'userId': self.test_user_id, 'sessionId': session_id}
            )
            
            if 'Item' in response:
                analytics = response['Item']
                print(f"  ✅ Analytics retrieved: Session {analytics['sessionId']}")
                print(f"     Track: {analytics['playbackData']['trackName']}")
            else:
                print("  ❌ Analytics entry not found")
                return False
            
            # Test QUERY operation (get analytics for user by timestamp)
            print("  🔍 Querying user analytics...")
            response = self.analytics_table.query(
                KeyConditionExpression=boto3.dynamodb.conditions.Key('userId').eq(self.test_user_id)
            )
            
            entries = response['Items']
            print(f"  ✅ Found {len(entries)} analytics entry(ies) for user")
            
            # Test GSI query by device
            print("  🔍 Querying analytics by device...")
            response = self.analytics_table.query(
                IndexName='DeviceIdIndex',
                KeyConditionExpression=boto3.dynamodb.conditions.Key('deviceId').eq(self.test_device_id)
            )
            
            device_entries = response['Items']
            print(f"  ✅ Found {len(device_entries)} entry(ies) for device")
            
            return True
            
        except ClientError as e:
            print(f"  ❌ Error testing analytics: {e}")
            return False
    
    def test_device_sync(self):
        """Test DeviceSync table operations"""
        print("\n📱 Testing DeviceSync operations...")
        
        try:
            # Create test device sync data
            test_sync = {
                'userId': self.test_user_id,
                'deviceId': self.test_device_id,
                'deviceName': 'Test Android Device',
                'deviceModel': 'Pixel 7',
                'osVersion': 'Android 14',
                'appVersion': '11.1.0',
                'lastSyncTime': int(time.time() * 1000),
                'syncEnabled': True,
                'syncStatus': 'SUCCESS',
                'lastSyncedProfilesCount': 1,
                'totalSyncOperations': 5,
                'lastErrorMessage': '',
                'syncSettings': {
                    'autoSyncEnabled': True,
                    'syncFrequency': 'DAILY',
                    'wifiOnlySync': True
                }
            }
            
            # Test CREATE/UPDATE operation (upsert)
            print("  📝 Creating device sync entry...")
            self.sync_table.put_item(Item=test_sync)
            print("  ✅ Device sync entry created successfully")
            
            # Test READ operation
            print("  📖 Reading device sync entry...")
            response = self.sync_table.get_item(
                Key={'userId': self.test_user_id, 'deviceId': self.test_device_id}
            )
            
            if 'Item' in response:
                sync_data = response['Item']
                print(f"  ✅ Device sync retrieved: {sync_data['deviceName']}")
                print(f"     Status: {sync_data['syncStatus']}")
                print(f"     Last sync: {sync_data['lastSyncTime']}")
            else:
                print("  ❌ Device sync entry not found")
                return False
            
            # Test UPDATE operation (mark sync in progress)
            print("  🔄 Updating sync status...")
            self.sync_table.update_item(
                Key={'userId': self.test_user_id, 'deviceId': self.test_device_id},
                UpdateExpression='SET syncStatus = :status, lastSyncTime = :time',
                ExpressionAttributeValues={
                    ':status': 'IN_PROGRESS',
                    ':time': int(time.time() * 1000)
                }
            )
            print("  ✅ Sync status updated to IN_PROGRESS")
            
            # Simulate completing sync
            time.sleep(1)
            self.sync_table.update_item(
                Key={'userId': self.test_user_id, 'deviceId': self.test_device_id},
                UpdateExpression='SET syncStatus = :status, lastSyncTime = :time, lastSyncedProfilesCount = :count',
                ExpressionAttributeValues={
                    ':status': 'SUCCESS',
                    ':time': int(time.time() * 1000),
                    ':count': 2
                }
            )
            print("  ✅ Sync completed successfully")
            
            # Test QUERY operation (get all devices for user)
            print("  🔍 Querying user devices...")
            response = self.sync_table.query(
                KeyConditionExpression=boto3.dynamodb.conditions.Key('userId').eq(self.test_user_id)
            )
            
            devices = response['Items']
            print(f"  ✅ Found {len(devices)} device(s) for user")
            
            return True
            
        except ClientError as e:
            print(f"  ❌ Error testing device sync: {e}")
            return False
    
    def test_cross_table_operations(self):
        """Test operations that span multiple tables"""
        print("\n🔗 Testing cross-table operations...")
        
        try:
            # Simulate a complete sync operation across all tables
            print("  🔄 Simulating complete sync operation...")
            
            # 1. Update device sync to mark sync start
            sync_start_time = int(time.time() * 1000)
            self.sync_table.update_item(
                Key={'userId': self.test_user_id, 'deviceId': self.test_device_id},
                UpdateExpression='SET syncStatus = :status, lastSyncTime = :time',
                ExpressionAttributeValues={
                    ':status': 'IN_PROGRESS',
                    ':time': sync_start_time
                }
            )
            
            # 2. Update audio profile (simulate settings change)
            self.profiles_table.update_item(
                Key={'userId': self.test_user_id, 'profileId': 'default'},
                UpdateExpression='SET lastModified = :time, #settings.#key = :value',
                ExpressionAttributeNames={
                    '#settings': 'audioSettings',
                    '#key': 'compression_enabled'
                },
                ExpressionAttributeValues={
                    ':time': sync_start_time,
                    ':value': True
                }
            )
            
            # 3. Log analytics for sync operation
            sync_analytics = {
                'userId': self.test_user_id,
                'sessionId': f"sync-{uuid.uuid4().hex[:8]}",
                'deviceId': self.test_device_id,
                'timestamp': sync_start_time,
                'sessionDuration': 2000,  # 2 seconds
                'playbackData': {
                    'trackName': 'SYNC_OPERATION',
                    'artist': 'SYSTEM',
                    'album': 'CLOUD_SYNC',
                    'genre': 'System',
                    'duration': 0,
                    'playCount': 0,
                    'skipCount': 0,
                    'completionPercentage': Decimal('100.0')
                },
                'audioSettings': {},
                'syncOperation': {
                    'profilesUpdated': 1,
                    'operation': 'FULL_SYNC',
                    'success': True
                }
            }
            
            self.analytics_table.put_item(Item=sync_analytics)
            
            # 4. Mark sync as completed
            sync_end_time = int(time.time() * 1000)
            self.sync_table.update_item(
                Key={'userId': self.test_user_id, 'deviceId': self.test_device_id},
                UpdateExpression='SET syncStatus = :status, lastSyncTime = :time, lastSyncedProfilesCount = :count',
                ExpressionAttributeValues={
                    ':status': 'SUCCESS',
                    ':time': sync_end_time,
                    ':count': 1
                }
            )
            
            print(f"  ✅ Complete sync operation simulated successfully")
            print(f"     Duration: {sync_end_time - sync_start_time}ms")
            
            return True
            
        except ClientError as e:
            print(f"  ❌ Error testing cross-table operations: {e}")
            return False
    
    def cleanup_test_data(self):
        """Clean up all test data created during testing"""
        print("\n🧹 Cleaning up test data...")
        
        try:
            # Delete audio profiles
            profiles_response = self.profiles_table.query(
                KeyConditionExpression=boto3.dynamodb.conditions.Key('userId').eq(self.test_user_id)
            )
            for profile in profiles_response['Items']:
                self.profiles_table.delete_item(
                    Key={'userId': profile['userId'], 'profileId': profile['profileId']}
                )
            print(f"  🗑️  Deleted {len(profiles_response['Items'])} audio profile(s)")
            
            # Delete analytics entries
            analytics_response = self.analytics_table.query(
                KeyConditionExpression=boto3.dynamodb.conditions.Key('userId').eq(self.test_user_id)
            )
            for entry in analytics_response['Items']:
                self.analytics_table.delete_item(
                    Key={'userId': entry['userId'], 'sessionId': entry['sessionId']}
                )
            print(f"  🗑️  Deleted {len(analytics_response['Items'])} analytics entry(ies)")
            
            # Delete device sync entries
            sync_response = self.sync_table.query(
                KeyConditionExpression=boto3.dynamodb.conditions.Key('userId').eq(self.test_user_id)
            )
            for device in sync_response['Items']:
                self.sync_table.delete_item(
                    Key={'userId': device['userId'], 'deviceId': device['deviceId']}
                )
            print(f"  🗑️  Deleted {len(sync_response['Items'])} device sync entry(ies)")
            
            print("  ✅ Test data cleanup completed")
            return True
            
        except ClientError as e:
            print(f"  ❌ Error cleaning up test data: {e}")
            return False
    
    def run_all_tests(self):
        """Run all tests and return overall result"""
        print(f"🚀 Starting DynamoDB integration tests...")
        print(f"   Region: {self.region}")
        print(f"   Test User ID: {self.test_user_id}")
        print(f"   Test Device ID: {self.test_device_id}")
        
        tests = [
            ('User Audio Profiles', self.test_user_audio_profiles),
            ('Listening Analytics', self.test_listening_analytics),
            ('Device Sync', self.test_device_sync),
            ('Cross-table Operations', self.test_cross_table_operations)
        ]
        
        passed = 0
        total = len(tests)
        
        for test_name, test_func in tests:
            try:
                if test_func():
                    passed += 1
                    print(f"✅ {test_name} test passed")
                else:
                    print(f"❌ {test_name} test failed")
            except Exception as e:
                print(f"❌ {test_name} test failed with exception: {e}")
        
        print(f"\n📊 Test Results: {passed}/{total} tests passed")
        
        # Always try to clean up
        self.cleanup_test_data()
        
        if passed == total:
            print("🎉 All tests passed! DynamoDB integration is working correctly.")
            print("💡 You can now configure your Android app to use these tables.")
            return True
        else:
            print("❌ Some tests failed. Check the errors above and verify your AWS setup.")
            return False


def main():
    parser = argparse.ArgumentParser(description='Test DynamoDB integration for Stash Opus Player')
    parser.add_argument('--region', default='us-east-1', help='AWS region (default: us-east-1)')
    
    args = parser.parse_args()
    
    try:
        tester = StashOpusDynamoDBTester(args.region)
        success = tester.run_all_tests()
        
        if success:
            print(f"\n🔧 Next steps:")
            print(f"   1. Configure AWS credentials in your Android app")
            print(f"   2. Update the region in AWSConfig.kt if not using us-east-1")
            print(f"   3. Test the connection from app Settings → Cloud Sync")
            exit(0)
        else:
            exit(1)
            
    except Exception as e:
        print(f"❌ Test failed with error: {e}")
        print(f"\n🔧 Troubleshooting:")
        print(f"   1. Check AWS credentials: aws sts get-caller-identity")
        print(f"   2. Verify tables exist: run setup_aws_tables.py")
        print(f"   3. Check permissions: ensure DynamoDB read/write access")
        exit(1)


if __name__ == "__main__":
    main()