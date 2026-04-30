# Concert Secrets Setup Guide

## Quick Setup

Add these secrets in Gitea: **Repository → Settings → Secrets → Actions**

## Required Secrets

### 1. CONCERT_URL
- **Description**: Your IBM Concert instance URL
- **Example**: `https://91431.us-south-8.concert.saas.ibm.com`
- **How to get**: Provided by IBM when you sign up for Concert
- **Format**: Full HTTPS URL without trailing slash

### 2. CONCERT_API_KEY
- **Description**: API key for authenticating with Concert
- **How to get**:
  1. Log into IBM Concert
  2. Navigate to **Settings** → **API Keys**
  3. Click **Generate New API Key**
  4. Copy the key (you won't see it again!)
  5. Ensure it has permissions for:
     - Upload SAST results
     - Upload SBOM data
     - Read/Write application data

### 3. CONCERT_INSTANCE_ID
- **Description**: Your Concert instance identifier
- **How to get**:
  1. Log into IBM Concert
  2. Navigate to **Settings** → **Instance Information**
  3. Copy the Instance ID
  - OR -
  1. Look at your Concert URL
  2. The instance ID is typically the first part: `https://[INSTANCE_ID].region.concert.saas.ibm.com`

## Step-by-Step Configuration in Gitea

### 1. Navigate to Repository Settings
```
Your Repository → Settings (gear icon) → Secrets → Actions
```

### 2. Add Each Secret

For each secret:
1. Click **"New Secret"** or **"Add Secret"**
2. Enter the **Name** (exactly as shown above)
3. Enter the **Value** (your actual credential)
4. Click **"Add Secret"** or **"Save"**

### 3. Verify Secrets

After adding all three secrets, you should see:
```
✓ CONCERT_URL
✓ CONCERT_API_KEY
✓ CONCERT_INSTANCE_ID
```

## Testing the Configuration

### Option 1: Run the Workflow
1. Push a commit or manually trigger the workflow
2. Check the "Validate Required Secrets" step
3. Look for:
   ```
   ✓ CONCERT_URL is set (Concert integration enabled)
   ```

### Option 2: Manual API Test
```bash
# Replace with your actual values
CONCERT_URL="https://your-instance.concert.saas.ibm.com"
CONCERT_API_KEY="your-api-key"
CONCERT_INSTANCE_ID="your-instance-id"

# Test API connectivity
curl -X GET "${CONCERT_URL}/core/api/v1/applications" \
  -H "C_API_KEY: ${CONCERT_API_KEY}" \
  -H "InstanceID: ${CONCERT_INSTANCE_ID}"
```

Expected response: JSON list of applications (or empty array if none exist)

## Security Best Practices

### ✅ DO:
- Store secrets in Gitea Secrets (encrypted at rest)
- Rotate API keys regularly (every 90 days recommended)
- Use separate API keys for different environments (dev/prod)
- Limit API key permissions to only what's needed
- Document who has access to secrets

### ❌ DON'T:
- Commit secrets to Git repository
- Share API keys via email or chat
- Use the same API key across multiple projects
- Give API keys more permissions than needed
- Store secrets in plain text files

## Troubleshooting

### Secret Not Found
**Symptom**: Workflow shows "CONCERT_URL not set"
**Solution**: 
- Verify secret name is exactly `CONCERT_URL` (case-sensitive)
- Check secret is added to the correct repository
- Ensure secret is in "Actions" section, not "Repository" section

### Invalid API Key
**Symptom**: HTTP 401 Unauthorized errors
**Solution**:
- Regenerate API key in Concert
- Update `CONCERT_API_KEY` secret in Gitea
- Verify no extra spaces in the secret value

### Wrong Instance ID
**Symptom**: HTTP 404 Not Found errors
**Solution**:
- Verify Instance ID in Concert Settings
- Update `CONCERT_INSTANCE_ID` secret
- Ensure no trailing spaces or newlines

### Application Not Found
**Symptom**: "Application demo-turbo-instana-concert not found"
**Solution**:
- Create the application in Concert first
- Ensure application name is exactly: `demo-turbo-instana-concert`
- Check application is in the correct Concert instance

## Optional: Disable Concert Integration

If you want to run the pipeline without Concert integration:

1. **Option A**: Don't add Concert secrets
   - Pipeline will skip Concert upload steps
   - Everything else works normally

2. **Option B**: Remove Concert secrets
   - Go to Repository → Settings → Secrets → Actions
   - Delete `CONCERT_URL`, `CONCERT_API_KEY`, `CONCERT_INSTANCE_ID`

The workflow will automatically detect missing secrets and skip Concert uploads.

## Example Secret Values

```bash
# Example (DO NOT use these actual values!)
CONCERT_URL=https://91431.us-south-8.concert.saas.ibm.com
CONCERT_API_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
CONCERT_INSTANCE_ID=91431
```

## Getting Help

### Concert Support
- IBM Concert Documentation: https://www.ibm.com/docs/en/concert
- IBM Support Portal: https://www.ibm.com/mysupport
- Contact your IBM representative

### Pipeline Issues
- Check Gitea Actions logs
- Review `docs/CONCERT_INTEGRATION.md` for detailed troubleshooting
- Verify all required secrets are configured

## Next Steps

After configuring secrets:
1. ✅ Push a commit to trigger the workflow
2. ✅ Verify SAST scan runs successfully
3. ✅ Check SBOM generation completes
4. ✅ Confirm uploads to Concert succeed
5. ✅ View results in Concert dashboard

## Checklist

- [ ] Added `CONCERT_URL` secret
- [ ] Added `CONCERT_API_KEY` secret
- [ ] Added `CONCERT_INSTANCE_ID` secret
- [ ] Verified secrets in Gitea UI
- [ ] Tested API connectivity
- [ ] Created `demo-turbo-instana-concert` application in Concert
- [ ] Triggered workflow to test integration
- [ ] Verified SAST results in Concert
- [ ] Verified SBOM data in Concert

---

**Last Updated**: 2026-04-30
**Application**: demo-turbo-instana-concert
**Pipeline**: .gitea/workflows/build-push-deploy-native-gitea-runner-needtobe-container.yaml