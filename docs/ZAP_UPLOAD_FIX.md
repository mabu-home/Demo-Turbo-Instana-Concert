# ZAP Upload Fix - Using Gitea Secrets

## Problem Solved
ZAP scan results were not being uploaded to Concert because:
1. The Kubernetes secret `concert-credentials` didn't exist
2. The workflow waited only 15 minutes but scans take 20-30 minutes
3. The uploader job was never deployed

## Solution Implemented

### Changes Made to Workflow

**1. Added Concert Credentials Secret Creation** (Before ZAP scan deployment)
```yaml
- name: Create Concert Credentials Secret
  if: secrets.CONCERT_URL != ''
  run: |
    # Delete existing secret if it exists
    kubectl delete secret concert-credentials \
      -n demo-turbo-instana-concert \
      --ignore-not-found=true
    
    # Create secret from Gitea secrets
    kubectl create secret generic concert-credentials \
      --from-literal=url='${{ secrets.CONCERT_URL }}' \
      --from-literal=api-key='${{ secrets.CONCERT_API_KEY }}' \
      --from-literal=instance-id='${{ secrets.CONCERT_INSTANCE_ID }}' \
      -n demo-turbo-instana-concert
    
    echo "✅ Concert credentials secret created"
```

**2. Added ZAP Uploader Job Deployment** (After ZAP scan deployment)
```yaml
- name: Deploy ZAP Uploader Job
  if: secrets.CONCERT_URL != ''
  run: |
    # Clean up any existing uploader jobs
    kubectl delete job zap-uploader -n demo-turbo-instana-concert --ignore-not-found=true
    
    # Deploy the uploader job (it will wait 30 min for scan completion)
    kubectl apply -f k8s/zap-uploader-job.yaml
    
    echo "✅ ZAP uploader job deployed"
```

**3. Simplified Scan Status Check**
- Removed 15-minute wait in workflow
- Added quick status check for monitoring
- Workflow no longer blocks on scan completion

## How It Works Now

### Workflow Flow
1. **Create Secret**: Gitea secrets → Kubernetes secret `concert-credentials`
2. **Deploy ZAP Scan**: Starts security scan (takes 20-30 min)
3. **Deploy Uploader**: Deploys job that waits 30 min then uploads
4. **Check Status**: Quick status check (non-blocking)
5. **Workflow Completes**: Doesn't wait for scan

### Uploader Job Flow
1. **Wait**: Sleeps for 30 minutes (initContainer)
2. **Check**: Verifies ZAP scan completed
3. **Retrieve**: Gets reports from ZAP pod
4. **Upload**: Sends to Concert API automatically

## Benefits

✅ **Uses Gitea Secrets**: No manual secret creation needed
✅ **Non-Blocking**: Workflow completes quickly (~5 min)
✅ **Automatic Upload**: Uploader handles everything
✅ **Reliable**: Waits long enough for scan completion
✅ **Reusable**: Works for every pipeline run

## Verification

### Check if Secret Was Created
```bash
kubectl get secret concert-credentials -n demo-turbo-instana-concert
```

### Monitor Uploader Job
```bash
# Check job status
kubectl get job zap-uploader -n demo-turbo-instana-concert

# View logs
kubectl logs -f job/zap-uploader -n demo-turbo-instana-concert
```

### Check ZAP Scan Status
```bash
# Check scan job
kubectl get job zap-full-scan -n demo-turbo-instana-concert

# View scan logs
kubectl logs -f job/zap-full-scan -n demo-turbo-instana-concert
```

## Manual Upload (If Needed)

If the uploader job fails, you can manually upload:

```bash
# Set environment variables from Gitea secrets
export CONCERT_URL="your-concert-url"
export CONCERT_API_KEY="your-api-key"
export CONCERT_INSTANCE_ID="your-instance-id"

# Run upload script
./scripts/upload-zap-to-concert.sh
```

## Troubleshooting

### Issue: Secret Not Created
**Symptom**: Uploader job fails with "secret not found"
**Solution**: Check Gitea secrets are configured:
- CONCERT_URL
- CONCERT_API_KEY
- CONCERT_INSTANCE_ID

### Issue: Uploader Job Not Deployed
**Symptom**: No uploader job exists
**Solution**: Check workflow logs for deployment step

### Issue: Upload Fails with 401
**Symptom**: Authentication error
**Solution**: Verify Concert API credentials in Gitea secrets

### Issue: Upload Fails with 404
**Symptom**: Application not found
**Solution**: Create application in Concert first

## Next Steps

1. **Commit Changes**: The workflow file has been updated
2. **Push to Trigger**: Push changes to trigger new pipeline
3. **Monitor**: Watch the uploader job logs
4. **Verify**: Check Concert for uploaded results

## Files Modified

- `.gitea/workflows/build-push-deploy-native-gitea-runner-needtobe-container.yaml`
  - Added secret creation step
  - Added uploader deployment step
  - Simplified scan status check

## Related Documentation

- [ZAP Security Scan Guide](./ZAP_SECURITY_SCAN_GUIDE.md)
- [Concert Integration Guide](./CONCERT_INTEGRATION.md)
- [ZAP Upload Troubleshooting](./ZAP_UPLOAD_TROUBLESHOOTING.md)
- [Upload Script](../scripts/upload-zap-to-concert.sh)
- [Uploader Job](../k8s/zap-uploader-job.yaml)