# Automated ZAP Upload with Kubernetes Job

## Overview

This solution uses a Kubernetes Job that automatically uploads ZAP scan results to IBM Concert 30 minutes after the scan starts. No manual intervention required!

## How It Works

```
0:00 - ZAP scan job starts
0:00 - ZAP uploader job starts (waits 30 min)
...
10:00 - ZAP scan completes, generates reports
...
30:00 - Uploader wakes up
30:01 - Checks if scan completed
30:02 - Retrieves reports from ZAP pod
30:03 - Uploads to Concert
30:04 - Success! ✅
```

## Setup Instructions

### Step 1: Create Concert Credentials Secret

**Option A: Using kubectl command (Recommended)**

```bash
kubectl create secret generic concert-credentials \
  --from-literal=url="https://91431.us-south-8.concert.saas.ibm.com" \
  --from-literal=api-key="YOUR_CONCERT_API_KEY" \
  --from-literal=instance-id="YOUR_CONCERT_INSTANCE_ID" \
  -n demo-turbo-instana-concert
```

**Option B: Using YAML file**

1. Edit `k8s/concert-credentials-secret.yaml`
2. Replace placeholder values with your actual credentials
3. Apply:
```bash
kubectl apply -f k8s/concert-credentials-secret.yaml
```

**⚠️ Security Note**: Never commit actual credentials to git! Use Option A or ensure the secret file is in `.gitignore`.

### Step 2: Deploy the Uploader Job

```bash
kubectl apply -f k8s/zap-uploader-job.yaml
```

This creates:
- ✅ ServiceAccount for the uploader
- ✅ Role with permissions to access ZAP pods
- ✅ RoleBinding to connect them
- ✅ Job that waits 30 minutes then uploads

### Step 3: Deploy ZAP Scan

```bash
kubectl apply -f k8s/zaptest.yaml
```

### Step 4: Monitor Progress

**Check ZAP scan status:**
```bash
kubectl get job zap-full-scan -n demo-turbo-instana-concert
```

**Check uploader status:**
```bash
kubectl get job zap-uploader -n demo-turbo-instana-concert
```

**View uploader logs:**
```bash
kubectl logs -l app=zap-uploader -n demo-turbo-instana-concert -f
```

## Expected Output

### Uploader Job Logs

```
============================================
ZAP Scan Results Uploader
============================================
Time: Mon May 4 12:30:00 UTC 2026

✓ Concert credentials configured
  URL: https://91431.us-south-8.concert.saas.ibm.com
  Instance ID: 12345678...

Installing kubectl...
✓ kubectl installed

Checking ZAP scan status...
✓ ZAP scan completed successfully

Locating ZAP scan pod...
✓ Found pod: zap-full-scan-xxxxx

Retrieving ZAP scan reports...
✓ JSON report retrieved
  File: /tmp/reports/zap-report.json
  Size: 2.3M

Uploading to IBM Concert...
Endpoint: https://91431.us-south-8.concert.saas.ibm.com/ingestion/api/v1/upload_files

HTTP Response Code: 200

============================================
✅ SUCCESS!
============================================

ZAP scan results uploaded to Concert

View results in Concert:
  https://91431.us-south-8.concert.saas.ibm.com/applications/demo-turbo-instana-concert
```

## Integration with CI/CD Pipeline

### Add to Workflow

Add this step after deploying the ZAP scan:

```yaml
- name: Deploy ZAP Uploader Job
  run: |
    echo "Deploying automated ZAP uploader..."
    kubectl apply -f k8s/zap-uploader-job.yaml
    echo "✓ Uploader job deployed - will run in 30 minutes"
```

### Complete Workflow Sequence

```yaml
# 1. Deploy ZAP scan
- name: Deploy ZAP Security Scan
  run: kubectl apply -f k8s/zaptest.yaml

# 2. Deploy uploader (waits 30 min automatically)
- name: Deploy ZAP Uploader
  run: kubectl apply -f k8s/zap-uploader-job.yaml

# 3. Pipeline completes (fast!)
# 4. ZAP scan runs in background (10-15 min)
# 5. Uploader wakes up at 30 min mark
# 6. Uploader checks scan, retrieves reports, uploads to Concert
```

## Troubleshooting

### Issue: Uploader fails with "concert-credentials secret not found"

**Solution**: Create the secret first (see Step 1)

```bash
kubectl get secret concert-credentials -n demo-turbo-instana-concert
```

### Issue: Uploader fails with "401 Unauthorized"

**Solution**: Check your Concert credentials

```bash
# View current secret (base64 encoded)
kubectl get secret concert-credentials -n demo-turbo-instana-concert -o yaml

# Decode to verify
kubectl get secret concert-credentials -n demo-turbo-instana-concert \
  -o jsonpath='{.data.api-key}' | base64 -d
```

### Issue: Uploader can't find ZAP pod

**Solution**: Ensure ZAP scan was deployed first

```bash
kubectl get pods -n demo-turbo-instana-concert -l job-name=zap-full-scan
```

### Issue: Uploader completes but says "scan not complete"

**Solution**: ZAP scan may have failed or is still running

```bash
# Check ZAP scan status
kubectl get job zap-full-scan -n demo-turbo-instana-concert

# Check ZAP logs
kubectl logs -l job-name=zap-full-scan -n demo-turbo-instana-concert
```

## Cleanup

### Delete completed jobs

```bash
# Delete ZAP scan job
kubectl delete job zap-full-scan -n demo-turbo-instana-concert

# Delete uploader job
kubectl delete job zap-uploader -n demo-turbo-instana-concert
```

### Keep RBAC and secret for next run

The ServiceAccount, Role, RoleBinding, and Secret persist for future scans.

## Advanced Configuration

### Change Wait Time

Edit `k8s/zap-uploader-job.yaml`, line 24:

```yaml
sleep 1800  # 30 minutes (1800 seconds)
```

Change to:
- 15 minutes: `sleep 900`
- 20 minutes: `sleep 1200`
- 45 minutes: `sleep 2700`

### Add to CronJob

For recurring scans, convert to CronJob:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: zap-uploader-cron
  namespace: demo-turbo-instana-concert
spec:
  schedule: "0 */2 * * *"  # Every 2 hours
  jobTemplate:
    spec:
      # Copy job spec from zap-uploader-job.yaml
```

## Verification

### Check in Concert

1. Log into Concert: https://91431.us-south-8.concert.saas.ibm.com
2. Navigate to: Applications → demo-turbo-instana-concert
3. Go to: Vulnerability → DAST Results
4. Verify ZAP scan data is visible

### Check Kubernetes Events

```bash
kubectl get events -n demo-turbo-instana-concert --sort-by='.lastTimestamp'
```

## Benefits

✅ **Fully Automated** - No manual intervention
✅ **Non-Blocking** - Pipeline completes quickly
✅ **Reliable** - Waits for scan completion
✅ **Secure** - Uses Kubernetes secrets
✅ **Reusable** - Works for every scan
✅ **Observable** - Full logging and status

## Files Created

- `k8s/zap-uploader-job.yaml` - Main uploader job with RBAC
- `k8s/concert-credentials-secret.yaml` - Secret template
- `docs/AUTOMATED_ZAP_UPLOAD.md` - This guide

## Related Documentation

- [ZAP Upload Troubleshooting](./ZAP_UPLOAD_TROUBLESHOOTING.md)
- [ZAP Security Scan Guide](./ZAP_SECURITY_SCAN_GUIDE.md)
- [Concert Integration Guide](./CONCERT_INTEGRATION.md)
- [Pipeline Behavior](./PIPELINE_BEHAVIOR.md)