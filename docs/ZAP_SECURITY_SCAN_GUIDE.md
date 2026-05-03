# OWASP ZAP Security Scan Guide for IBM Concert Integration

## Overview

This guide provides step-by-step instructions for running OWASP ZAP (Zed Attack Proxy) security scans on the Demo Turbo Instana Concert application and uploading the results to IBM Concert for vulnerability management.

**✨ NEW: Automatic Scan Execution** - ZAP security scans are now automatically triggered after every deployment via the CI/CD pipeline!

**✨ NEW: Automatic Concert Upload** - ZAP scan results are now automatically uploaded to IBM Concert for vulnerability management!

## Table of Contents

1. [Automatic Execution (CI/CD)](#automatic-execution-cicd)
2. [Manual Execution](#manual-execution)
3. [Retrieving Scan Results](#retrieving-scan-results)
4. [Uploading to IBM Concert](#uploading-to-ibm-concert)
5. [Troubleshooting](#troubleshooting)
6. [Advanced Configuration](#advanced-configuration)

---

## Automatic Execution (CI/CD)

### How It Works

The ZAP security scan is **automatically triggered** after every successful deployment through the Gitea CI/CD workflow:

1. **Trigger**: Push to `main` or `master` branch
2. **Build & Deploy**: Applications are built and deployed to Kubernetes
3. **ZAP Scan**: Security scan is automatically initiated
4. **Report Generation**: HTML and JSON reports are generated
5. **Artifact Upload**: Reports are available as workflow artifacts (if scan completes quickly)

### Workflow Steps

The CI/CD pipeline includes these automatic ZAP scan steps:

```yaml
# Step 1: Deploy ZAP Security Scan
- Cleans up any existing ZAP scan jobs
- Deploys new ZAP scan job to Kubernetes
- Targets: http://load-test-service.demo-turbo-instana-concert.svc.cluster.local

# Step 2: Wait for ZAP Scan Completion
- Monitors scan progress
- Shows initial scan logs
- Continues in background (non-blocking)

# Step 3: Retrieve ZAP Scan Results
- Attempts to retrieve reports if scan completes quickly
- Provides manual retrieval instructions if still running

# Step 4: Upload ZAP Results to Concert (NEW!)
- Automatically uploads scan results to IBM Concert
- Uses Concert Ingestion API
- Supports both JSON and HTML formats
- Non-blocking (continues even if upload fails)

# Step 5: Upload ZAP Reports as Artifacts
- Makes reports available for download from workflow
```

### Viewing Scan Progress

**In Gitea Workflow:**
```bash
# Navigate to: Repository > Actions > Latest Workflow Run
# Look for steps:
#   - "Deploy ZAP Security Scan"
#   - "Wait for ZAP Scan Completion"
#   - "Retrieve ZAP Scan Results"
```

**In Kubernetes:**
```bash
# Check scan job status
kubectl get jobs -n demo-turbo-instana-concert

# View scan logs
kubectl logs -f job/zap-full-scan -n demo-turbo-instana-concert

# Check pod status
kubectl get pods -n demo-turbo-instana-concert -l job-name=zap-full-scan
```

### Scan Duration

- **Typical Duration**: 5-15 minutes
- **Workflow Behavior**: Non-blocking (workflow completes, scan continues)
- **Report Availability**: 
  - If scan completes within ~2 minutes: Available as workflow artifacts
  - If scan takes longer: Retrieve manually using provided commands

### Retrieving Reports After Automatic Scan

If the scan is still running when the workflow completes:

```bash
# Wait for scan to complete
kubectl wait --for=condition=complete job/zap-full-scan -n demo-turbo-instana-concert --timeout=600s

# Get pod name
POD_NAME=$(kubectl get pods -n demo-turbo-instana-concert -l job-name=zap-full-scan -o jsonpath='{.items[0].metadata.name}')

# Copy reports
mkdir -p security-reports
kubectl -n demo-turbo-instana-concert cp $POD_NAME:/zap/wrk/full-scan-report.html ./security-reports/concert-security-scan.html
kubectl -n demo-turbo-instana-concert cp $POD_NAME:/zap/wrk/full-scan-report.json ./security-reports/concert-security-scan.json
```

---

## Manual Execution

### Quick Start (Automated Script)

For on-demand scans or when you need immediate results:

```bash
# Run the automated ZAP scan script
./scripts/run-zap-scan.sh
```

This script provides:
- ✅ Automatic cleanup of old scan jobs
- ✅ Real-time progress monitoring
- ✅ Automatic report retrieval
- ✅ Timestamped report files
- ✅ Symlinks to latest reports
- ✅ Detailed status information

**Output Location:**
```
./security-reports/
├── concert-security-scan-20260501_143022.html
├── concert-security-scan-20260501_143022.json
├── concert-security-scan-latest.html -> concert-security-scan-20260501_143022.html
└── concert-security-scan-latest.json -> concert-security-scan-20260501_143022.json
```

### Manual Deployment Steps

If you prefer manual control:

#### Step 1: Deploy the ZAP Scan Job

```bash
# Clean up any existing scan
kubectl delete job zap-full-scan -n demo-turbo-instana-concert --ignore-not-found=true

# Deploy new scan
kubectl apply -f k8s/zaptest.yaml
```

#### Step 2: Monitor Progress

```bash
# Get pod name
POD_NAME=$(kubectl get pods -n demo-turbo-instana-concert -l job-name=zap-full-scan -o jsonpath='{.items[0].metadata.name}')

# Follow logs
kubectl logs -f pod/$POD_NAME -n demo-turbo-instana-concert
```

#### Step 3: Wait for Completion

```bash
# Wait for job to complete (timeout: 10 minutes)
kubectl wait --for=condition=complete job/zap-full-scan -n demo-turbo-instana-concert --timeout=600s
```

---

## Retrieving Scan Results

### Automatic Retrieval (via script)

```bash
./scripts/run-zap-scan.sh
# Reports automatically saved to ./security-reports/
```

### Manual Retrieval

```bash
# Get pod name
POD_NAME=$(kubectl get pods -n demo-turbo-instana-concert -l job-name=zap-full-scan -o jsonpath='{.items[0].metadata.name}')

# Create output directory
mkdir -p ./security-reports

# Copy HTML report
kubectl -n demo-turbo-instana-concert cp $POD_NAME:/zap/wrk/full-scan-report.html ./security-reports/concert-security-scan.html

# Copy JSON report
kubectl -n demo-turbo-instana-concert cp $POD_NAME:/zap/wrk/full-scan-report.json ./security-reports/concert-security-scan.json

# Verify files
ls -lh ./security-reports/
```

### Report Formats

| Format | Use Case | Recommended For |
|--------|----------|-----------------|
| **HTML** | Human-readable, detailed descriptions, color-coded | Manual review, presentations |
| **JSON** | Machine-readable, structured data | Concert upload, automation, parsing |

---

## Uploading to IBM Concert

### Automatic Upload (CI/CD) - RECOMMENDED

**✨ NEW: ZAP scan results are now automatically uploaded to Concert!**

The CI/CD pipeline automatically uploads ZAP scan results to IBM Concert after each scan completes. This happens in the "Upload ZAP Results to Concert" step.

**How It Works:**
1. ZAP scan completes and generates reports
2. Pipeline retrieves JSON or HTML report
3. Report is automatically uploaded to Concert Ingestion API
4. Results appear in Concert dashboard within minutes

**Requirements:**
- Concert secrets must be configured in Gitea:
  - `CONCERT_URL`: Your Concert instance URL
  - `CONCERT_API_KEY`: Concert API key
  - `CONCERT_INSTANCE_ID`: Concert instance ID
- See [CONCERT_SECRETS_SETUP.md](./CONCERT_SECRETS_SETUP.md) for setup instructions

**Viewing Results:**
1. Log in to IBM Concert: `https://91431.us-south-8.concert.saas.ibm.com`
2. Navigate to Applications → `demo-turbo-instana-concert`
3. Go to Security → DAST Results or Vulnerabilities
4. View ZAP scan findings with severity ratings

**Upload Status:**
Check the workflow logs for upload confirmation:
```
✅ SUCCESS: ZAP scan results uploaded to Concert
View results in Concert:
  https://91431.us-south-8.concert.saas.ibm.com/applications/demo-turbo-instana-concert
```

---

### Manual Upload (Alternative Method)

If automatic upload fails or you need to upload manually:

#### Prerequisites

- IBM Concert account with upload permissions
- ZAP scan report (HTML or JSON format)
- Access to Concert UI or API

#### Step 1: Access IBM Concert Upload Interface

1. Log in to IBM Concert: `https://91431.us-south-8.concert.saas.ibm.com`
2. Navigate to **Vulnerability** or **Exposures** section
3. Click **"Upload exposure"** or **"Upload an exposure scan"**

#### Step 2: Configure Upload Settings

Fill in the upload form:

| Field | Value | Notes |
|-------|-------|-------|
| **Scan Source** | `ZAP` | Select from dropdown |
| **Environment** | `kubernetes_demo-turbo-instana-concert_production` | Your K8s environment |
| **Access Point Name** | `concert.lab.allwaysbeginner.com` | The ingress hostname |
| **Scan Date** | Current date | Format: MM/DD/YYYY (e.g., 05/01/2026) |
| **Scan Time** | Scan execution time | Format: HH:MM (e.g., 14:30) |
| **File** | Select report | Choose JSON (preferred) or HTML |

#### Step 3: Upload the Report

**Recommended: Use JSON format**
```bash
# Upload this file:
./security-reports/concert-security-scan-latest.json
```

**Alternative: Use HTML format**
```bash
# Upload this file:
./security-reports/concert-security-scan-latest.html
```

**Upload Constraints:**
- Maximum file size: 10 MB
- Maximum number of files: 10
- Supported formats: JSON, HTML, XML

#### Step 4: Verify Upload

1. Click **"Upload"** to submit
2. Wait for processing (1-2 minutes)
3. Verify scan appears in Concert dashboard
4. Check vulnerability categorization

#### Step 5: Review Results in Concert

Concert will automatically:
- ✅ Parse ZAP scan results
- ✅ Categorize vulnerabilities by severity (CRITICAL, HIGH, MEDIUM, LOW)
- ✅ Map findings to affected applications
- ✅ Generate risk scores and priorities
- ✅ Create remediation recommendations
- ✅ Track vulnerability trends over time

---

## Troubleshooting

### Common Issues

#### 1. Automatic Scan Not Triggered

**Symptoms:**
- No ZAP scan steps in workflow logs
- Scan job not created after deployment

**Solutions:**
```bash
# Verify workflow file is updated
cat .gitea/workflows/build-push-deploy-native-gitea-runner-needtobe-container.yaml | grep -A 5 "ZAP Security Scan"

# Manually trigger scan
./scripts/run-zap-scan.sh

# Check if zaptest.yaml exists
ls -la k8s/zaptest.yaml
```

#### 2. Scan Pod Fails to Start

**Symptoms:**
```
Error: ImagePullBackOff or CrashLoopBackOff
```

**Solutions:**
```bash
# Check pod status
kubectl describe pod $POD_NAME -n demo-turbo-instana-concert

# Check events
kubectl get events -n demo-turbo-instana-concert --sort-by='.lastTimestamp'

# Verify ZAP image availability
kubectl run test-zap --image=ghcr.io/zaproxy/zaproxy:stable --rm -it --restart=Never -- zap.sh -version
```

#### 3. Scan Takes Too Long

**Symptoms:**
- Scan runs for more than 30 minutes
- Pod appears stuck

**Solutions:**
```bash
# Check pod logs for progress
kubectl logs pod/$POD_NAME -n demo-turbo-instana-concert

# Check resource usage
kubectl top pod $POD_NAME -n demo-turbo-instana-concert

# Restart scan with more resources (edit k8s/zaptest.yaml)
```

#### 4. Cannot Retrieve Reports

**Symptoms:**
```
Error: file not found or connection refused
```

**Solutions:**
```bash
# Verify pod is still running
kubectl get pod $POD_NAME -n demo-turbo-instana-concert

# Check if reports were generated
kubectl exec $POD_NAME -n demo-turbo-instana-concert -- ls -la /zap/wrk/

# Manually extract report content
kubectl exec $POD_NAME -n demo-turbo-instana-concert -- cat /zap/wrk/full-scan-report.json > ./security-reports/manual-report.json
```

#### 5. Upload Fails in Concert

**Symptoms:**
- Upload rejected or fails validation
- Error messages in Concert UI

**Solutions:**

**Check file size:**
```bash
ls -lh ./security-reports/concert-security-scan-latest.json
# Must be under 10 MB
```

**Validate JSON format:**
```bash
jq . ./security-reports/concert-security-scan-latest.json > /dev/null && echo "Valid JSON" || echo "Invalid JSON"
```

**Verify date/time format:**
- Date: MM/DD/YYYY (e.g., 05/01/2026)
- Time: HH:MM (e.g., 14:30)

**Check environment name:**
- Must match existing Concert environment
- Use exact name: `kubernetes_demo-turbo-instana-concert_production`

#### 6. Automatic Concert Upload Fails

**Symptoms:**
```
❌ FAILED: Authentication error (401 Unauthorized)
❌ FAILED: Application not found (404 Not Found)
⚠️  WARNING: Unexpected response code
```

**Solutions:**

**Check Concert Secrets:**
```bash
# Verify secrets are set in Gitea
# Repository → Settings → Secrets → Actions
# Required secrets:
#   - CONCERT_URL
#   - CONCERT_API_KEY
#   - CONCERT_INSTANCE_ID
```

**Test Concert API Connection:**
```bash
# Test authentication
curl -X GET "${CONCERT_URL}/ingestion/api/v1/health" \
  -H "InstanceID: ${CONCERT_INSTANCE_ID}" \
  -H "Authorization: C_API_KEY ${CONCERT_API_KEY}"
```

**Verify Application Exists:**
```bash
# Check if application exists in Concert
curl -X GET "${CONCERT_URL}/core/api/v1/applications" \
  -H "C_API_KEY: ${CONCERT_API_KEY}" \
  -H "InstanceID: ${CONCERT_INSTANCE_ID}" | jq '.applications[] | select(.name=="demo-turbo-instana-concert")'
```

**Check Workflow Logs:**
```bash
# In Gitea, navigate to:
# Repository → Actions → Latest Workflow Run → "Upload ZAP Results to Concert"
# Look for detailed error messages and HTTP response codes
```

**Common Error Codes:**
- `401`: Invalid API key or Instance ID
- `404`: Application doesn't exist in Concert
- `413`: File too large (>10 MB)
- `500`: Concert server error (retry later)


#### 6. Services Not Accessible

**Symptoms:**
```
ZAP logs show connection refused or timeout errors
```

**Solutions:**
```bash
# Verify services are running
kubectl get svc -n demo-turbo-instana-concert

# Test service connectivity
kubectl run test-curl --image=curlimages/curl --rm -it --restart=Never -- curl -v http://load-test-service.demo-turbo-instana-concert.svc.cluster.local

# Check service endpoints
kubectl get endpoints -n demo-turbo-instana-concert
```

---

## Advanced Configuration

### Customizing Scan Targets

Edit `k8s/zaptest.yaml` to modify scan behavior:

#### Scan External Ingress

```yaml
args:
  - |
    # Scan via external ingress (requires DNS/hosts file setup)
    zap-full-scan.py -t https://concert.lab.allwaysbeginner.com -I -J full-scan-report.json -r full-scan-report.html
```

#### Scan Multiple Services

```yaml
args:
  - |
    # Scan multiple internal services
    zap-full-scan.py -t http://load-test-service.demo-turbo-instana-concert.svc.cluster.local -I -J load-test-report.json
    zap-full-scan.py -t http://vulnerable-echo-service.demo-turbo-instana-concert.svc.cluster.local:8085 -I -J echo-service-report.json
```

### Adjusting Resource Limits

```yaml
resources:
  requests:
    memory: "1Gi"      # Increase for larger apps
    cpu: "1000m"       # Increase for faster scans
  limits:
    memory: "4Gi"      # Maximum memory
    cpu: "4000m"       # Maximum CPU
```

### Additional ZAP Options

```yaml
args:
  - |
    # Advanced ZAP options:
    # -l INFO: Set minimum log level
    # -j: Use Ajax spider for JavaScript-heavy apps
    # -d: Show debug messages
    zap-full-scan.py -t http://target -I -J report.json -l INFO -j -d
```

### Scheduling Regular Scans

Create a CronJob for automated periodic scans:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: zap-scheduled-scan
  namespace: demo-turbo-instana-concert
spec:
  schedule: "0 2 * * 0"  # Every Sunday at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: zap
            image: ghcr.io/zaproxy/zaproxy:stable
            # Same configuration as zaptest.yaml
```

Apply the CronJob:
```bash
kubectl apply -f k8s/zap-cronjob.yaml
```

---

## Best Practices

### 1. Scan Frequency

**Automatic Scans (CI/CD):**
- ✅ Triggered on every deployment
- ✅ Ensures new code is scanned immediately
- ✅ Catches vulnerabilities early in development

**Manual Scans:**
- Run weekly for comprehensive coverage
- Schedule during low-traffic periods
- Perform after major configuration changes

**Scheduled Scans (CronJob):**
- Weekly or bi-weekly for production environments
- Monthly for stable applications
- After security updates or patches

### 2. Report Management

```bash
# Archive old reports with timestamps
mkdir -p security-reports/archive
mv security-reports/concert-security-scan-*.{html,json} security-reports/archive/

# Keep last 3 months of reports
find security-reports/archive -name "*.json" -mtime +90 -delete
find security-reports/archive -name "*.html" -mtime +90 -delete

# Compare results across scans
diff security-reports/archive/concert-security-scan-20260401_*.json security-reports/concert-security-scan-latest.json
```

### 3. Vulnerability Remediation Workflow

1. **Review Scan Results**
   - Prioritize CRITICAL and HIGH severity findings
   - Identify false positives
   - Group related vulnerabilities

2. **Create Tickets in Concert**
   - One ticket per vulnerability or group
   - Include CVE IDs and CVSS scores
   - Assign to appropriate teams

3. **Track Progress**
   - Monitor remediation status in Concert
   - Update ticket status as fixes are deployed
   - Document remediation steps

4. **Verify Fixes**
   - Re-run ZAP scan after fixes
   - Confirm vulnerabilities are resolved
   - Update Concert with verification results

### 4. Resource Management

```bash
# Clean up completed scan jobs regularly
kubectl delete job zap-full-scan -n demo-turbo-instana-concert

# Monitor cluster resources during scans
kubectl top nodes
kubectl top pods -n demo-turbo-instana-concert

# Adjust resource limits based on usage
kubectl describe pod $POD_NAME -n demo-turbo-instana-concert | grep -A 5 "Limits:"
```

### 5. Security Considerations

- ✅ Run scans in isolated namespaces
- ✅ Use read-only service accounts for ZAP pods
- ✅ Restrict network policies to necessary services
- ✅ Encrypt scan reports at rest and in transit
- ✅ Limit access to scan results (sensitive data)
- ✅ Rotate Concert API keys regularly
- ✅ Audit scan execution and report access

---

## Integration Examples

### CI/CD Pipeline Integration

The ZAP scan is already integrated into the Gitea workflow. For other CI/CD systems:

**GitHub Actions:**
```yaml
- name: Run ZAP Scan
  run: |
    kubectl apply -f k8s/zaptest.yaml
    kubectl wait --for=condition=complete job/zap-full-scan -n demo-turbo-instana-concert --timeout=600s
    POD_NAME=$(kubectl get pods -n demo-turbo-instana-concert -l job-name=zap-full-scan -o jsonpath='{.items[0].metadata.name}')
    kubectl cp demo-turbo-instana-concert/$POD_NAME:/zap/wrk/full-scan-report.json ./zap-report.json

- name: Upload to Concert
  run: |
    curl -X POST https://concert-api/upload \
      -H "Authorization: Bearer ${{ secrets.CONCERT_TOKEN }}" \
      -F "file=@./zap-report.json" \
      -F "scan_source=ZAP"
```

**Jenkins Pipeline:**
```groovy
stage('ZAP Security Scan') {
    steps {
        sh './scripts/run-zap-scan.sh'
        archiveArtifacts artifacts: 'security-reports/*.json', fingerprint: true
    }
}
```

### Slack Notifications

Add to workflow or script:
```bash
# Send notification when scan completes
curl -X POST $SLACK_WEBHOOK_URL \
  -H 'Content-Type: application/json' \
  -d '{
    "text": "🔒 ZAP Security Scan Complete",
    "attachments": [{
      "color": "good",
      "fields": [
        {"title": "Environment", "value": "demo-turbo-instana-concert", "short": true},
        {"title": "Status", "value": "Completed", "short": true},
        {"title": "Report", "value": "Available in security-reports/", "short": false}
      ]
    }]
  }'
```

---

## Cleanup

### Remove Scan Job

```bash
# Delete the ZAP scan job
kubectl delete job zap-full-scan -n demo-turbo-instana-concert

# Verify deletion
kubectl get jobs -n demo-turbo-instana-concert
```

### Clean Up Old Reports

```bash
# Remove reports older than 30 days
find ./security-reports -name "concert-security-scan-*.json" -mtime +30 -delete
find ./security-reports -name "concert-security-scan-*.html" -mtime +30 -delete

# Keep only latest 10 reports
cd security-reports
ls -t concert-security-scan-*.json | tail -n +11 | xargs rm -f
ls -t concert-security-scan-*.html | tail -n +11 | xargs rm -f
```

---

## Quick Reference

### Common Commands

```bash
# Run automated scan
./scripts/run-zap-scan.sh

# Check scan status
kubectl get jobs -n demo-turbo-instana-concert
kubectl get pods -n demo-turbo-instana-concert -l job-name=zap-full-scan

# View scan logs
kubectl logs -f job/zap-full-scan -n demo-turbo-instana-concert

# Retrieve reports manually
POD_NAME=$(kubectl get pods -n demo-turbo-instana-concert -l job-name=zap-full-scan -o jsonpath='{.items[0].metadata.name}')
kubectl cp demo-turbo-instana-concert/$POD_NAME:/zap/wrk/full-scan-report.json ./security-reports/report.json

# Clean up
kubectl delete job zap-full-scan -n demo-turbo-instana-concert
```

### File Locations

```
Project Structure:
├── k8s/
│   └── zaptest.yaml                    # ZAP scan job configuration
├── scripts/
│   └── run-zap-scan.sh                 # Automated scan script
├── security-reports/                   # Scan reports directory
│   ├── concert-security-scan-*.html    # HTML reports
│   ├── concert-security-scan-*.json    # JSON reports
│   ├── concert-security-scan-latest.html  # Symlink to latest HTML
│   └── concert-security-scan-latest.json  # Symlink to latest JSON
└── .gitea/workflows/
    └── build-push-deploy-native-gitea-runner-needtobe-container.yaml  # CI/CD with auto-scan
```

---

## Additional Resources

### OWASP ZAP Documentation
- Official Documentation: https://www.zaproxy.org/docs/
- Docker Images: https://github.com/zaproxy/zaproxy/wiki/Docker
- Automation Framework: https://www.zaproxy.org/docs/docker/automation-framework/
- ZAP API: https://www.zaproxy.org/docs/api/

### IBM Concert Documentation
- Concert User Guide: https://www.ibm.com/docs/concert
- API Reference: https://concert-api-docs.ibm.com
- Vulnerability Management: https://www.ibm.com/docs/concert/vulnerability
- Upload Specifications: https://www.ibm.com/docs/concert/upload

### Related Project Guides
- [CONCERT_INTEGRATION.md](./CONCERT_INTEGRATION.md) - Concert setup and configuration
- [CONCERT_SECRETS_SETUP.md](./CONCERT_SECRETS_SETUP.md) - Managing Concert credentials
- [SBOM_TROUBLESHOOTING.md](./SBOM_TROUBLESHOOTING.md) - SBOM generation and upload
- [K3S_REGISTRY_FIX.md](./K3S_REGISTRY_FIX.md) - Registry troubleshooting

---

## Support

For issues or questions:

1. **Check Documentation**
   - Review [Troubleshooting](#troubleshooting) section
   - Check [Common Issues](#common-issues)

2. **Review Logs**
   ```bash
   kubectl logs pod/$POD_NAME -n demo-turbo-instana-concert
   kubectl describe pod $POD_NAME -n demo-turbo-instana-concert
   ```

3. **Check Concert Status**
   - Verify upload in Concert UI
   - Check Concert API status
   - Review Concert documentation

4. **Contact Support**
   - IBM Concert administrator
   - Kubernetes cluster administrator
   - Security team

---

## Changelog

### Version 1.1 (2026-05-01)
- ✨ Added automatic ZAP scan execution in CI/CD pipeline
- ✨ Integrated scan into Gitea workflow
- 📝 Updated documentation with automatic execution details
- 🔧 Fixed ingress hostname to concert.lab.allwaysbeginner.com

### Version 1.0 (2026-05-01)
- 🎉 Initial release
- 📝 Complete ZAP scan guide
- 🔧 Manual scan script
- 📋 Concert upload instructions

---

**Last Updated:** 2026-05-01  
**Version:** 1.1  
**Maintainer:** Demo Turbo Instana Concert Team