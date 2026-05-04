# CI/CD Pipeline Behavior for ZAP Scans

## Current Pipeline Behavior

### Why Pipeline Doesn't Wait 15 Minutes

The workflow step "Retrieve ZAP Scan Results" has:
```yaml
continue-on-error: true
```

This means:
- ✅ The `kubectl wait --timeout=900s` command IS executed
- ✅ It WILL wait up to 15 minutes IF the job is running normally
- ❌ BUT if `kubectl wait` fails for ANY reason, the pipeline continues immediately
- ❌ The workflow won't block deployments waiting for security scans

### Why This Design?

**Non-Blocking Security Scans**: The pipeline is designed to NOT block deployments:
- Deployments complete quickly (< 5 minutes)
- ZAP scans take 10-15 minutes
- Security scans run in background
- Results uploaded separately

### What Actually Happens

```
Timeline:
0:00 - Deploy ZAP scan job
0:30 - Try kubectl wait (may fail if job not ready)
0:30 - Pipeline continues (continue-on-error: true)
0:30 - Try to retrieve reports → FAIL (not ready yet)
0:30 - Skip upload → NO DATA UPLOADED
0:30 - Pipeline completes ✅
...
10:00 - ZAP scan actually completes
10:00 - Reports generated
10:00 - Nobody uploads them ❌
```

## Solutions

### Option 1: Use Manual Upload Script (RECOMMENDED)

After pipeline completes, run:
```bash
# Wait for scan to finish
kubectl get job zap-full-scan -n demo-turbo-instana-concert -w

# When complete, upload results
export CONCERT_URL="https://91431.us-south-8.concert.saas.ibm.com"
export CONCERT_API_KEY="your-key"
export CONCERT_INSTANCE_ID="your-id"
./scripts/upload-zap-to-concert.sh
```

### Option 2: Remove continue-on-error (BLOCKS PIPELINE)

**⚠️ WARNING**: This will make deployments wait 15 minutes!

Change line 1571 in workflow:
```yaml
# FROM:
continue-on-error: true

# TO:
continue-on-error: false
```

**Impact**:
- ✅ Pipeline WILL wait for scan completion
- ✅ Results uploaded automatically
- ❌ Every deployment takes 15+ minutes
- ❌ Failed scans block deployments
- ❌ Slower development cycle

### Option 3: Separate Upload Workflow

Create a scheduled workflow that runs every 15 minutes:

```yaml
# .gitea/workflows/upload-zap-results.yaml
name: Upload ZAP Results

on:
  schedule:
    - cron: '*/15 * * * *'  # Every 15 minutes
  workflow_dispatch:

jobs:
  upload:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Upload ZAP Results
        run: ./scripts/upload-zap-to-concert.sh
```

### Option 4: CronJob in Kubernetes

Deploy a CronJob that automatically uploads completed scans:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: zap-uploader
  namespace: demo-turbo-instana-concert
spec:
  schedule: "*/10 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: uploader
            image: bitnami/kubectl:latest
            env:
            - name: CONCERT_URL
              valueFrom:
                secretKeyRef:
                  name: concert-secrets
                  key: url
            command: ["/scripts/upload-zap-to-concert.sh"]
```

## Recommended Approach

**For Development**: Use Option 1 (manual script)
- Fast deployments
- Upload when needed
- No pipeline changes

**For Production**: Use Option 3 or 4 (automated)
- Automatic uploads
- No manual intervention
- Separate from deployment pipeline

## Verification

Check if scan completed:
```bash
kubectl get job zap-full-scan -n demo-turbo-instana-concert
```

Check scan logs:
```bash
kubectl logs -l job-name=zap-full-scan -n demo-turbo-instana-concert
```

Check if reports exist:
```bash
POD_NAME=$(kubectl get pods -n demo-turbo-instana-concert -l job-name=zap-full-scan -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n demo-turbo-instana-concert $POD_NAME -- ls -lh /zap/wrk/
```

## Summary

The pipeline DOES have the 15-minute wait, but it's non-blocking by design. Use the manual upload script after scans complete, or implement automated upload via separate workflow/CronJob.