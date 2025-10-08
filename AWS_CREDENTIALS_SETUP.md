# AWS Credentials Setup Guide for Stash Opus Player

This guide explains how to configure AWS credentials for the DynamoDB cloud sync functionality.

## Prerequisites

1. AWS Account with DynamoDB access
2. IAM User with appropriate permissions
3. Access Key ID and Secret Access Key

## Setup Methods (in order of priority)

### Method 1: In-App Configuration (Recommended for End Users)
The app provides a settings interface to enter AWS credentials directly:

1. Open Stash Opus Player
2. Go to Settings → Cloud Sync
3. Enter your AWS Access Key ID and Secret Access Key
4. Test the connection

### Method 2: Environment Variables (Development)
Set environment variables on your development machine:

```bash
export AWS_ACCESS_KEY_ID="your_access_key_here"
export AWS_SECRET_ACCESS_KEY="your_secret_key_here"
export AWS_DEFAULT_REGION="us-east-1"
```

### Method 3: Assets File (Testing)
Create a file at `app/src/main/assets/aws_credentials.properties`:

```properties
aws.accessKey=your_access_key_here
aws.secretKey=your_secret_key_here
aws.region=us-east-1
```

**Note:** Never commit this file to version control!

## Required AWS IAM Permissions

Your AWS user needs the following permissions for DynamoDB:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:UpdateItem",
                "dynamodb:DeleteItem",
                "dynamodb:Query",
                "dynamodb:Scan",
                "dynamodb:BatchGetItem",
                "dynamodb:BatchWriteItem"
            ],
            "Resource": [
                "arn:aws:dynamodb:*:*:table/StashOpusUserAudioProfiles",
                "arn:aws:dynamodb:*:*:table/StashOpusListeningAnalytics",
                "arn:aws:dynamodb:*:*:table/StashOpusDeviceSync"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:ListTables",
                "dynamodb:DescribeTable"
            ],
            "Resource": "*"
        }
    ]
}
```

## DynamoDB Table Setup

The following tables will be automatically created when the app first runs:

### 1. StashOpusUserAudioProfiles
- **Partition Key:** userId (String)
- **Sort Key:** profileName (String)

### 2. StashOpusListeningAnalytics
- **Partition Key:** userId (String)
- **Sort Key:** sessionId (String)

### 3. StashOpusDeviceSync
- **Partition Key:** userId (String)
- **Sort Key:** deviceId (String)

## Security Best Practices

1. **Use IAM User:** Create a dedicated IAM user for the app, don't use root credentials
2. **Minimum Permissions:** Only grant the minimum required DynamoDB permissions
3. **Rotate Keys:** Regularly rotate access keys
4. **Monitor Usage:** Use AWS CloudTrail to monitor API usage
5. **Secure Storage:** The app encrypts stored credentials using Android's security features

## Testing the Setup

1. Launch the app with credentials configured
2. Go to Settings → Cloud Sync → Test Connection
3. Check the logs for connection status:
   ```
   adb logcat | grep AWSConfig
   ```

## Troubleshooting

### Common Issues:

1. **"Invalid credentials" error:**
   - Verify Access Key ID and Secret Access Key are correct
   - Check that the IAM user has the required permissions

2. **"Region not accessible" error:**
   - Ensure your AWS region is correct (default: us-east-1)
   - Verify DynamoDB is available in your region

3. **"Network timeout" error:**
   - Check internet connectivity
   - Verify AWS endpoints are not blocked by firewall

4. **"Table not found" error:**
   - Tables are created automatically on first use
   - Check IAM permissions for CreateTable action

### Debug Commands:

```bash
# Check AWS credential source
adb logcat | grep "Credential source"

# Monitor DynamoDB operations
adb logcat | grep "DynamoDB"

# Check sync status
adb logcat | grep "CloudSync"
```

## Production Deployment

For production apps:

1. **Code Obfuscation:** Enable ProGuard/R8 obfuscation
2. **Certificate Pinning:** Consider implementing certificate pinning
3. **Analytics:** Monitor AWS usage costs and patterns
4. **Backup Strategy:** Implement data backup and recovery procedures
5. **User Education:** Provide clear documentation on AWS costs and usage

## Cost Considerations

DynamoDB pricing factors:
- **On-Demand:** Pay per request (recommended for most users)
- **Provisioned:** Fixed capacity with potential cost savings for high usage
- **Storage:** $0.25 per GB-month
- **Network:** Data transfer costs apply for cross-region operations

Expected costs for typical usage:
- Light user (sync once daily): ~$0.01-0.05/month
- Heavy user (frequent sync): ~$0.10-0.50/month

## Support

For AWS-related issues:
1. Check AWS Documentation: https://docs.aws.amazon.com/dynamodb/
2. AWS Support: https://aws.amazon.com/support/
3. App-specific issues: Check the app's GitHub repository