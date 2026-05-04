# ZAP Scan Retry Logic & Resilience Improvements

**Last Updated:** 2026-05-04  
**Version:** 2.0

---

## Overview

This document describes the enhanced retry logic and resilience improvements implemented for the ZAP security scanning and report collection system. These improvements ensure reliable scan execution and report upload even when scans take longer than expected.

---

## Problem Statement

### Original Issues

1. **CronJob Timing Mismatch**
   - ZAP scans typically take 10-15 minutes to complete
   - CronJob runs every 15 minutes but doesn't wait for scan completion
   - Reports not available when collector runs
   - Result: "No ZAP scan job found" or "Reports not available"

2. **No Retry Logic**
   - Single attempt to retrieve reports
   - Fails if scan is still generating reports
   - No fallback or retry mechanism

3. **Race Conditions**
   - Pod may not be ready when collector runs
   - Reports may not be fully written to disk
   - Network issues during file copy

---

## Solution Architecture

### 1. Enhanced CronJob with Wait Logic

**File:** [`k8s/zap-report-collector-cronjob.yaml`](../k8s/zap-report-collector-cronjob.yaml)

#### Key Improvements

**Wait Loop with Timeout:**
```bash
MAX_WAIT_TIME=1800  # 30 minutes max wait
CHECK_INTERVAL=60   # Check every 60 seconds
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT_TIME ]; do
  # Check job status
  # Wait if still running
  # Break if completed
  sleep $CHECK_INTERVAL
  ELAPSED=$((ELAPSED + CHECK_INTERVAL))
done
```

**Benefits:**
- ✅ Waits up to 30 minutes for scan completion
- ✅ Checks status every 60 seconds
- ✅ Gracefully handles long-running scans
- ✅ Provides progress updates
- ✅ Times out safely if scan hangs

#### Status Checking Logic

```bash
# Check if completed
JOB_STATUS=$(kubectl get job zap-full-scan -n demo-turbo-instana-concert \
  -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')

# Check if still running
ACTIVE=$(kubectl get job zap-full-scan -n demo-turbo-instana-concert \
  -o jsonpath='{.status.active}')

# Check if failed
FAILED=$(kubectl get job zap-full-scan -n demo-turbo-instana-concert \
  -o jsonpath='{.status.failed}')
```

---

### 2. Upload Script with Retry Logic

**File:** [`scripts/upload-zap-to-concert.sh`](../scripts/upload-zap-to-concert.sh)

#### Key Improvements

**Multi-Stage Retry:**
```bash
MAX_RETRIES=3

# Stage 1: Wait for scan completion (3 retries × 15 min = 45 min max)
# Stage 2: Locate pod (3 retries × 30 sec = 90 sec max)
# Stage 3: Retrieve reports (3 retries × 60 sec = 180 sec max)
```

**Report Retrieval with Fallback:**
```bash
# Try JSON first
if kubectl cp $POD_NAME:/zap/wrk/full-scan-report.json "$JSON_REPORT"; then
  REPORT_RETRIEVED=true
fi

# Fallback to HTML if JSON fails
if [ "$REPORT_RETRIEVED" = "false" ]; then
  if kubectl cp $POD_NAME:/zap/wrk/full-scan-report.html "$HTML_REPORT"; then
    REPORT_RETRIEVED=true
  fi
fi
```

**Benefits:**
- ✅ Multiple retry attempts at each stage
- ✅ Automatic fallback to HTML if JSON unavailable
- ✅ File size validation (non-empty check)
- ✅ Detailed error messages with troubleshooting steps
- ✅ Exponential backoff between retries

---

## Configuration Parameters

### CronJob Configuration

| Parameter | Value | Description |
|-----------|-------|-------------|
| `schedule` | `*/15 * * * *` | Run every 15 minutes |
| `MAX_WAIT_TIME` | `1800` seconds | 30 minutes max wait for scan |
| `CHECK_INTERVAL` | `60` seconds | Check status every minute |
| `backoffLimit` | `2` | Retry failed jobs twice |
| `ttlSecondsAfterFinished` | `3600` | Clean up after 1 hour |

### Upload Script Configuration

| Parameter | Value | Description |
|-----------|-------|-------------|
| `MAX_RETRIES` | `3` | Maximum retry attempts per stage |
| `WAIT_TIMEOUT` | `900` seconds | 15 minutes per wait attempt |
| `RETRY_DELAY` | `30-60` seconds | Delay between retries |

---

## Workflow Diagrams

### CronJob Execution Flow

```
┌─────────────────────────────────────────────────────────────┐
│ CronJob Triggered (every 15 minutes)                        │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
         ┌────────────────────────┐
         │ Check if ZAP job exists│
         └────────┬───────────────┘
                  │
         ┌────────▼────────┐
         │ Job exists?     │
         └────┬────────┬───┘
              │        │
         No   │        │ Yes
              │        │
              ▼        ▼
         ┌────────┐  ┌──────────────────────┐
         │ Exit 0 │  │ Start wait loop      │
         └────────┘  │ (max 30 min)         │
                     └──────┬───────────────┘
                            │
                     ┌──────▼──────────┐
                     │ Check every 60s │
                     └──────┬──────────┘
                            │
              ┌─────────────┼─────────────┐
              │             │             │
         ┌────▼────┐   ┌───▼────┐   ┌───▼────┐
         │Complete │   │Running │   │Failed  │
         └────┬────┘   └───┬────┘   └───┬────┘
              │            │             │
              │            │             │
              ▼            ▼             ▼
         ┌────────┐   ┌────────┐   ┌────────┐
         │Collect │   │Wait &  │   │Exit 1  │
         │Reports │   │Retry   │   │        │
         └────┬───┘   └────────┘   └────────┘
              │
              ▼
         ┌────────────┐
         │Upload to   │
         │Concert     │
         └────────────┘
```

### Upload Script Flow

```
┌─────────────────────────────────────────────────────────────┐
│ Upload Script Executed                                       │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
         ┌────────────────────────┐
         │ Validate Concert creds │
         └────────┬───────────────┘
                  │
                  ▼
         ┌────────────────────────┐
         │ Wait for scan complete │
         │ (3 retries × 15 min)   │
         └────────┬───────────────┘
                  │
                  ▼
         ┌────────────────────────┐
         │ Locate pod             │
         │ (3 retries × 30 sec)   │
         └────────┬───────────────┘
                  │
                  ▼
         ┌────────────────────────┐
         │ Retrieve reports       │
         │ (3 retries × 60 sec)   │
         └────────┬───────────────┘
                  │
         ┌────────▼────────┐
         │ Report found?   │
         └────┬────────┬───┘
              │        │
         No   │        │ Yes
              │        │
              ▼        ▼
         ┌────────┐  ┌──────────────┐
         │ Exit 1 │  │ Validate JSON│
         └────────┘  └──────┬───────┘
                            │
                            ▼
                     ┌──────────────┐
                     │ Upload to    │
                     │ Concert API  │
                     └──────┬───────┘
                            │
              ┌─────────────┼─────────────┐
              │             │             │
         ┌────▼────┐   ┌───▼────┐   ┌───▼────┐
         │Success  │   │Auth    │   │Other   │
         │200-202  │   │Error   │   │Error   │
         └────┬────┘   │401     │   │4xx/5xx │
              │        └───┬────┘   └───┬────┘
              │            │             │
              ▼            ▼             ▼
         ┌────────┐   ┌────────┐   ┌────────┐
         │Exit 0  │   │Exit 1  │   │Exit 1  │
         └────────┘   └────────┘   └────────┘
```

---

## Monitoring & Troubleshooting

### Check CronJob Status

```bash
# List all CronJob executions
kubectl get jobs -n demo-turbo-instana-concert | grep zap-report-collector

# View latest execution logs
LATEST_JOB=$(kubectl get jobs -n demo-turbo-instana-concert \
  -l app=zap-report-collector \
  --sort-by=.metadata.creationTimestamp \
  -o name | tail -1)

kubectl logs -n demo-turbo-instana-concert $LATEST_JOB
```

### Check ZAP Scan Status

```bash
# Check if scan is running
kubectl get job zap-full-scan -n demo-turbo-instana-concert

# View scan progress
kubectl logs -f job/zap-full-scan -n demo-turbo-instana-concert

# Check pod status
kubectl get pods -n demo-turbo-instana-concert -l job-name=zap-full-scan
```

### Common Issues & Solutions

#### Issue 1: "No ZAP scan job found"

**Cause:** Scan job hasn't been created yet or was cleaned up

**Solution:**
```bash
# Deploy new scan
kubectl apply -f k8s/zaptest.yaml

# Or use automated script
./scripts/run-zap-scan.sh
```

#### Issue 2: "Timeout waiting for scan completion"

**Cause:** Scan taking longer than 30 minutes

**Solution:**
```bash
# Check if scan is still running
kubectl get job zap-full-scan -n demo-turbo-instana-concert

# Increase MAX_WAIT_TIME in CronJob if needed
# Edit k8s/zap-report-collector-cronjob.yaml
# Change: MAX_WAIT_TIME=3600  # 60 minutes
```

#### Issue 3: "Reports not available after 3 retries"

**Cause:** Reports not generated or pod terminated

**Solution:**
```bash
# Check if reports exist in pod
POD_NAME=$(kubectl get pods -n demo-turbo-instana-concert \
  -l job-name=zap-full-scan -o jsonpath='{.items[0].metadata.name}')

kubectl exec $POD_NAME -n demo-turbo-instana-concert -- ls -la /zap/wrk/

# If pod is gone, check job logs
kubectl logs job/zap-full-scan -n demo-turbo-instana-concert --tail=100
```

#### Issue 4: "Concert upload fails with 401"

**Cause:** Invalid or expired API credentials

**Solution:**
```bash
# Verify Concert secrets
kubectl get secret concert-credentials -n demo-turbo-instana-concert -o yaml

# Test API connection
curl -X GET "${CONCERT_URL}/ingestion/api/v1/health" \
  -H "InstanceID: ${CONCERT_INSTANCE_ID}" \
  -H "Authorization: C_API_KEY ${CONCERT_API_KEY}"
```

---

## Performance Metrics

### Expected Timings

| Operation | Duration | Notes |
|-----------|----------|-------|
| ZAP Full Scan | 10-15 min | Depends on target complexity |
| Report Generation | 30-60 sec | After scan completes |
| Report Retrieval | 5-10 sec | Network dependent |
| Concert Upload | 10-30 sec | File size dependent |
| **Total End-to-End** | **12-18 min** | From scan start to upload |

### Resource Usage

| Component | CPU | Memory | Notes |
|-----------|-----|--------|-------|
| ZAP Scan Pod | 750m-1500m | 1.5-3 GB | Peak during scan |
| Collector Job | 100m-200m | 128-256 MB | During execution |
| Upload Script | 50m-100m | 64-128 MB | Minimal overhead |

---

## Best Practices

### 1. Scan Scheduling

✅ **DO:**
- Run scans during low-traffic periods
- Allow 30-minute buffer between scans
- Monitor scan duration trends
- Adjust CronJob schedule based on scan duration

❌ **DON'T:**
- Run multiple scans simultaneously
- Schedule scans too frequently (< 15 min apart)
- Ignore failed scan notifications

### 2. Report Management

✅ **DO:**
- Archive reports after successful upload
- Keep last 3-5 reports for comparison
- Monitor report file sizes
- Validate JSON before upload

❌ **DON'T:**
- Delete reports immediately after upload
- Store unlimited reports (disk space)
- Upload corrupted or incomplete reports

### 3. Error Handling

✅ **DO:**
- Check logs after each execution
- Set up alerts for repeated failures
- Document custom retry configurations
- Test retry logic in staging

❌ **DON'T:**
- Ignore timeout warnings
- Disable retry logic
- Skip validation steps
- Assume success without verification

---

## Testing & Validation

### Test Retry Logic

```bash
# 1. Deploy scan
kubectl apply -f k8s/zaptest.yaml

# 2. Immediately trigger collector (should wait)
kubectl create job --from=cronjob/zap-report-collector manual-test-1 \
  -n demo-turbo-instana-concert

# 3. Monitor logs
kubectl logs -f job/manual-test-1 -n demo-turbo-instana-concert

# 4. Verify it waits and retries
# Expected output: "⏳ ZAP scan is still running... (waited Xs / 1800s)"
```

### Test Upload Retry

```bash
# 1. Run upload script manually
./scripts/upload-zap-to-concert.sh

# 2. Observe retry behavior
# Expected: 3 attempts with 60s delays

# 3. Verify fallback to HTML
# If JSON fails, should try HTML automatically
```

---

## Maintenance

### Regular Tasks

**Weekly:**
- Review CronJob execution logs
- Check for failed uploads
- Verify Concert integration
- Clean up old ConfigMaps

**Monthly:**
- Analyze scan duration trends
- Adjust retry timeouts if needed
- Update Concert credentials
- Review and archive old reports

**Quarterly:**
- Update ZAP image version
- Review and optimize scan configuration
- Test disaster recovery procedures
- Update documentation

---

## Related Documentation

- [ZAP Security Scan Guide](./ZAP_SECURITY_SCAN_GUIDE.md) - Complete scanning guide
- [Concert Integration](./CONCERT_INTEGRATION.md) - Concert setup and configuration
- [Upload Troubleshooting](./ZAP_UPLOAD_TROUBLESHOOTING.md) - Detailed troubleshooting
- [Pipeline Behavior](./PIPELINE_BEHAVIOR.md) - CI/CD integration

---

## Changelog

### Version 2.0 (2026-05-04)
- ✨ Added 30-minute wait loop in CronJob
- ✨ Implemented 3-stage retry logic in upload script
- ✨ Added automatic HTML fallback
- ✨ Enhanced error messages with troubleshooting steps
- 📝 Created comprehensive documentation
- 🔧 Improved status checking logic

### Version 1.0 (2026-05-01)
- 🎉 Initial CronJob implementation
- 📝 Basic upload script
- 🔧 Simple retry logic

---

**Maintainer:** Demo Turbo Instana Concert Team  
**Support:** See [ZAP_UPLOAD_TROUBLESHOOTING.md](./ZAP_UPLOAD_TROUBLESHOOTING.md)