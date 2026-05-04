# ZAP Scan Upload Troubleshooting Guide

## Problem: ZAP Scan Results Not Uploading to Concert

### Root Cause
The ZAP security scan takes 5-15 minutes to complete, but the CI/CD pipeline only waits 30 seconds before attempting to retrieve and upload results. This causes the upload step to skip because no reports are available yet.

### Current Workflow Behavior
```
1. Deploy ZAP scan job (k8s Job)
2. Wait 30 seconds
3. Try to retrieve reports → FAIL (scan still running)
4. Skip upload to Concert → NO DATA UPLOADED
5. Scan continues running in background
6. Reports generated after workflow completes
```

## Solutions

### Option 1: Increase Wait Time in CI/CD Pipeline (Recommended)

Modify the workflow to wait longer for scan completion:

**File**: `.gitea/workflows/build-push-deploy-native-gitea-runner-needtobe-container.yaml`

**Change line 1495** from:
```yaml
sleep 30
```

To:
```yaml
sleep 300  # Wait 5 minutes for scan to complete
```

**Or use kubectl wait** (better approach):
```yaml
- name: Retrieve ZAP Scan Results (if available)
  run: |
    echo "Waiting for ZAP scan to complete..."
    
    # Wait up to 15 minutes for job completion
    kubectl wait --for=condition=complete job/zap-full-scan \
      -n demo-turbo-instana-concert \
      --timeout=900s || {
      echo "⚠️  Scan did not complete within 15 minutes"
      echo "Checking if reports are available anyway..."
    }
    
    # Get pod name
    POD_NAME=$(kubectl get pods -n demo-turbo-instana-concert \
      -l job-name=zap-full-scan \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$POD_NAME" ]; then
      echo "⚠️  ZAP scan pod not found. Skipping report retrieval."
      exit 0
    fi
    
    # Rest of the retrieval logic...
```

### Option 2: Use CronJob for Periodic Report Collection

Deploy a Kubernetes CronJob that periodically checks for completed scans and uploads results:

**File**: `k8s/zap-report-collector-cronjob.yaml` (already exists!)

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: zap-report-collector
  namespace: demo-turbo-instana-concert
spec:
  schedule: "*/10 * * * *"  # Every 10 minutes
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: collector
            image: bitnami/kubectl:latest
            command: ["/bin/bash", "-c"]
            args:
              - |
                # Check for completed ZAP scans
                # Retrieve reports
                # Upload to Concert
          restartPolicy: OnFailure
```

### Option 3: Manual Upload After Scan Completes

**Step 1**: Wait for scan to complete (check job status):
```bash
kubectl get job zap-full-scan -n demo-turbo-instana-concert
```

**Step 2**: Retrieve reports manually:
```bash
# Get pod name
POD_NAME=$(kubectl get pods -n demo-turbo-instana-concert \
  -l job-name=zap-full-scan \
  -o jsonpath='{.items[0].metadata.name}')

# Copy reports
kubectl -n demo-turbo-instana-concert cp \
  $POD_NAME:/zap/wrk/full-scan-report.json \
  ./concert-security-scan.json

kubectl -n demo-turbo-instana-concert cp \
  $POD_NAME:/zap/wrk/full-scan-report.html \
  ./concert-security-scan.html
```

**Step 3**: Upload to Concert via API:
```bash
# Set environment variables
export CONCERT_URL="https://91431.us-south-8.concert.saas.ibm.com"
export CONCERT_API_KEY="your-api-key"
export CONCERT_INSTANCE_ID="your-instance-id"

# Upload JSON report
curl -X POST "${CONCERT_URL}/ingestion/api/v1/upload_files" \
  -H "accept: application/json" \
  -H "Content-Type: multipart/form-data" \
  -H "InstanceID: ${CONCERT_INSTANCE_ID}" \
  -H "Authorization: C_API_KEY ${CONCERT_API_KEY}" \
  -F "data_type=dynamic_code_scan" \
  -F "filename=@./concert-security-scan.json" \
  -F 'metadata={"env_name":"prod","tool":"zap","scan_type":"dast","access_point":"concert.lab.allwaysbeginner.com"}'
```

**Step 4**: Or upload via Concert UI:
1. Navigate to Concert → Vulnerability/Exposures → Upload exposure
2. Scan Source: **ZAP**
3. Environment: **kubernetes_demo-turbo-instana-concert_production**
4. Access Point: **concert.lab.allwaysbeginner.com**
5. Upload file: `concert-security-scan.json` or `.html`

### Option 4: Separate Upload Job

Create a separate workflow or job that runs after the main deployment:

```yaml
# .gitea/workflows/upload-zap-results.yaml
name: Upload ZAP Results to Concert

on:
  workflow_dispatch:  # Manual trigger
  schedule:
    - cron: '*/15 * * * *'  # Every 15 minutes

jobs:
  upload-zap:
    runs-on: ubuntu-latest
    steps:
      - name: Check for ZAP Reports
        run: |
          # Check if ZAP scan completed
          # Retrieve reports
          # Upload to Concert
```

## Recommended Implementation

**Best Practice**: Modify the existing workflow to wait for scan completion:

1. **Increase timeout** in "Retrieve ZAP Scan Results" step
2. **Use kubectl wait** with 15-minute timeout
3. **Add retry logic** if initial retrieval fails
4. **Keep continue-on-error: true** to not block deployments

## Verification Steps

After implementing the fix:

1. **Trigger a new build**:
   ```bash
   git commit --allow-empty -m "Test ZAP upload fix"
   git push
   ```

2. **Monitor the workflow**:
   - Check Gitea Actions logs
   - Look for "✅ SUCCESS: ZAP scan results uploaded to Concert"

3. **Verify in Concert**:
   - Navigate to Applications → demo-turbo-instana-concert
   - Check Vulnerability → DAST Results
   - Confirm ZAP scan data is visible

4. **Check scan completion**:
   ```bash
   kubectl get job zap-full-scan -n demo-turbo-instana-concert
   kubectl logs -l job-name=zap-full-scan -n demo-turbo-instana-concert
   ```

## Common Issues

### Issue 1: Scan Times Out
**Symptom**: Job never completes
**Solution**: 
- Check ZAP pod logs for errors
- Increase memory/CPU limits in zaptest.yaml
- Reduce scan scope with `-z` options

### Issue 2: Reports Not Generated
**Symptom**: Pod completes but no files in /zap/wrk/
**Solution**:
- Check ZAP container logs
- Verify target URLs are accessible
- Check for OOM (Out of Memory) errors

### Issue 3: Upload Fails with 401
**Symptom**: Authentication error
**Solution**:
- Verify CONCERT_API_KEY secret
- Verify CONCERT_INSTANCE_ID secret
- Check API key hasn't expired

### Issue 4: Upload Fails with 404
**Symptom**: Application not found
**Solution**:
- Create application in Concert first
- Ensure name matches: `demo-turbo-instana-concert`
- Check Concert URL is correct

## Monitoring Commands

```bash
# Check ZAP scan status
kubectl get job zap-full-scan -n demo-turbo-instana-concert

# View ZAP scan logs
kubectl logs -l job-name=zap-full-scan -n demo-turbo-instana-concert -f

# Check if reports exist in pod
POD_NAME=$(kubectl get pods -n demo-turbo-instana-concert \
  -l job-name=zap-full-scan -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n demo-turbo-instana-concert $POD_NAME -- ls -lh /zap/wrk/

# Delete old scan job
kubectl delete job zap-full-scan -n demo-turbo-instana-concert
```

## Quick Fix Script

Create `scripts/upload-zap-to-concert.sh`:

```bash
#!/bin/bash
# Quick script to manually upload ZAP results to Concert

set -e

NAMESPACE="demo-turbo-instana-concert"
JOB_NAME="zap-full-scan"

# Wait for scan completion
echo "Waiting for ZAP scan to complete..."
kubectl wait --for=condition=complete job/$JOB_NAME -n $NAMESPACE --timeout=900s

# Get pod name
POD_NAME=$(kubectl get pods -n $NAMESPACE -l job-name=$JOB_NAME \
  -o jsonpath='{.items[0].metadata.name}')

# Retrieve reports
mkdir -p ./security-reports
kubectl -n $NAMESPACE cp $POD_NAME:/zap/wrk/full-scan-report.json \
  ./security-reports/concert-security-scan.json

# Upload to Concert
curl -X POST "${CONCERT_URL}/ingestion/api/v1/upload_files" \
  -H "InstanceID: ${CONCERT_INSTANCE_ID}" \
  -H "Authorization: C_API_KEY ${CONCERT_API_KEY}" \
  -F "data_type=dynamic_code_scan" \
  -F "filename=@./security-reports/concert-security-scan.json"

echo "✅ Upload complete!"
```

## References

- [ZAP Security Scan Guide](./ZAP_SECURITY_SCAN_GUIDE.md)
- [Concert Integration Guide](./CONCERT_INTEGRATION.md)
- [OWASP ZAP Documentation](https://www.zaproxy.org/docs/)
- [Concert API Documentation](https://www.ibm.com/docs/en/concert)