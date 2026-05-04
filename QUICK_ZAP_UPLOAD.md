# Quick Guide: Upload ZAP Scan Results to Concert

## The Upload Script Location

```
scripts/upload-zap-to-concert.sh
```

## How to Run It

### Step 1: Set Environment Variables

```bash
export CONCERT_URL="https://91431.us-south-8.concert.saas.ibm.com"
export CONCERT_API_KEY="your-api-key-here"
export CONCERT_INSTANCE_ID="your-instance-id-here"
```

### Step 2: Run the Script

```bash
./scripts/upload-zap-to-concert.sh
```

## What the Script Does

1. ✅ Waits for ZAP scan to complete (up to 15 minutes)
2. ✅ Retrieves scan reports from Kubernetes pod
3. ✅ Validates JSON format
4. ✅ Uploads to IBM Concert
5. ✅ Shows detailed success/error messages

## Expected Output

```
========================================
Upload ZAP Results to IBM Concert
========================================

✓ Concert credentials configured
  URL: https://91431.us-south-8.concert.saas.ibm.com
  Instance ID: 12345678...

Step 1: Waiting for ZAP scan to complete...
✅ ZAP scan completed successfully!

Step 2: Locating ZAP scan pod...
✓ Found pod: zap-full-scan-xxxxx

Step 3: Retrieving scan reports...
✓ JSON report retrieved
  File: ./security-reports/concert-security-scan.json
  Size: 2.3M

Step 4: Validating JSON format...
✓ JSON file is valid

Step 5: Uploading to IBM Concert...
HTTP Response Code: 200

========================================
✅ SUCCESS!
========================================

View results in Concert:
  https://91431.us-south-8.concert.saas.ibm.com/applications/demo-turbo-instana-concert
```

## If You Get Errors

### Error: "CONCERT_URL environment variable not set"
**Solution**: Set the environment variables first (see Step 1)

### Error: "ZAP scan pod not found"
**Solution**: Deploy the ZAP scan first:
```bash
kubectl apply -f k8s/zaptest.yaml
```

### Error: "401 Unauthorized"
**Solution**: Check your API key and Instance ID are correct

### Error: "404 Not Found"
**Solution**: Create the application in Concert first:
- Application name must be: `demo-turbo-instana-concert`

## Alternative: Manual Upload via Concert UI

If the script doesn't work, you can upload manually:

1. **Get the reports first**:
```bash
POD_NAME=$(kubectl get pods -n demo-turbo-instana-concert -l job-name=zap-full-scan -o jsonpath='{.items[0].metadata.name}')
kubectl -n demo-turbo-instana-concert cp $POD_NAME:/zap/wrk/full-scan-report.json ./concert-security-scan.json
```

2. **Upload in Concert UI**:
   - Navigate to: Concert → Vulnerability/Exposures → Upload exposure
   - Scan Source: **ZAP**
   - Environment: **kubernetes_demo-turbo-instana-concert_production**
   - Access Point: **concert.lab.allwaysbeginner.com**
   - Upload file: `concert-security-scan.json`

## Full Documentation

For complete troubleshooting and all options, see:
- [ZAP Upload Troubleshooting Guide](docs/ZAP_UPLOAD_TROUBLESHOOTING.md)
- [ZAP Security Scan Guide](docs/ZAP_SECURITY_SCAN_GUIDE.md)
- [Concert Integration Guide](docs/CONCERT_INTEGRATION.md)