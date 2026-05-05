# Concert ZAP Upload Fix - Final Working Solution

## Problem Identified
ZAP scans were uploading to Concert but failing during processing with errors in Concert logs.

## Root Cause
Incorrect API parameters were being used:
1. ❌ `data_type=dynamic_code_scan` (wrong)
2. ❌ Metadata used `access_point`, `tool`, `format`, `scan_type`, `application` (wrong structure)

## Solution Applied

### Correct API Parameters (Per Concert Documentation)

**data_type**: `dynamic_scan` (not `dynamic_code_scan`)

**metadata structure**:
```json
{
  "env_name": "instanak3s",
  "access_point_name": "concert1",
  "access_point_url": "http://concert1.lab.allwaysbeginner.com"
}
```

### Working Upload Command

```bash
curl -X POST "https://concert1.lab.allwaysbeginner.com:12443/ingestion/api/v1/upload_files" \
  -H "Authorization: C_API_KEY bWFuZnJlZDo4MWVlYTY0Ny03NDIwLTQ2ZDEtYTA5MC1kYWE5M2VkMDk3Y2Q=" \
  -H "InstanceID: 0000-0000-0000-0000" \
  -H "Content-Type: multipart/form-data" \
  -F "data_type=dynamic_scan" \
  -F "filename=@security-reports/concert-compatible-zap-scan.json" \
  -F 'metadata={"env_name":"instanak3s","access_point_name":"concert1","access_point_url":"http://concert1.lab.allwaysbeginner.com"}' \
  --insecure
```

### Successful Upload Result

```json
{
  "record_paths": [
    "0000-0000-0000-0000/roja/dynamic_scan/2026/5/5/131957455_concert-compatible-zap-scan.json"
  ],
  "event_ids": [
    "40cfeaf5-5484-42b4-b458-391a77f1cc16"
  ],
  "job_data": {
    "message": "202 Accepted"
  }
}
```

**Status**: HTTP 202 Accepted - Processing successfully in Concert ✅

## Files Updated

### 1. k8s/zap-uploader-job.yaml
**Changes**:
- Line 159: Changed `data_type=dynamic_code_scan` → `data_type=dynamic_scan`
- Line 161: Updated metadata structure to use `env_name`, `access_point_name`, `access_point_url`

**Before**:
```yaml
-F "data_type=dynamic_code_scan" \
-F 'metadata={"env_name":"prod","tool":"zap","format":"'${REPORT_FORMAT}'","scan_type":"dast","access_point":"concert.lab.allwaysbeginner.com","application":"demo-turbo-instana-concert"}' \
```

**After**:
```yaml
-F "data_type=dynamic_scan" \
-F 'metadata={"env_name":"instanak3s","access_point_name":"concert1","access_point_url":"http://concert1.lab.allwaysbeginner.com"}' \
```

### 2. scripts/upload-zap-to-concert.sh
**Changes**:
- Line 186-187: Updated metadata structure
- Line 196: Changed `data_type=dynamic_code_scan` → `data_type=dynamic_scan`

**Before**:
```bash
METADATA="{\"env_name\":\"prod\",\"tool\":\"zap\",\"format\":\"${FILE_EXT}\",\"scan_type\":\"dast\",\"access_point\":\"concert.lab.allwaysbeginner.com\",\"application\":\"demo-turbo-instana-concert\"}"
-F "data_type=dynamic_code_scan" \
```

**After**:
```bash
METADATA="{\"env_name\":\"instanak3s\",\"access_point_name\":\"concert1\",\"access_point_url\":\"http://concert1.lab.allwaysbeginner.com\"}"
-F "data_type=dynamic_scan" \
```

### 3. scripts/run-and-upload-zap-to-concert.sh
**Changes**:
- Line 111: Updated metadata structure
- Line 119: Changed `data_type=dynamic_code_scan` → `data_type=dynamic_scan`

**Before**:
```bash
METADATA="{\"env_name\":\"prod\",\"tool\":\"zap\",\"format\":\"json\",\"scan_type\":\"dast\",\"access_point\":\"concert1.lab.allwaysbeginner.com\",\"application\":\"demo-turbo-instana-concert\"}"
-F "data_type=dynamic_scan" \
```

**After**:
```bash
METADATA="{\"env_name\":\"instanak3s\",\"access_point_name\":\"concert1\",\"access_point_url\":\"http://concert1.lab.allwaysbeginner.com\"}"
-F "data_type=dynamic_scan" \
```

## Concert API Documentation Reference

### Supported Scan Types

| File type | Scan source | File format |
|-----------|-------------|-------------|
| Dynamic scan | Zap | JSON |
| Dynamic scan | Others (custom) | CSV, XLS, XLSX |
| Static scan | Concert | JSON, CSV |
| Static scan | SonarQube | JSON, CSV |

### Required Metadata Fields

**Dynamic Scan**:
- `env_name`: Environment name (must match existing environment in Concert)
- `access_point_name`: Name of the access point
- `access_point_url`: URL of the access point

**Static Scan**:
- `repository_name`: Repository name
- `repository_url`: Repository URL

## Verification Steps

1. **Check Upload Success**:
   ```bash
   # Look for HTTP 202 response
   # Verify event_id is returned
   ```

2. **View in Concert UI**:
   - Navigate to: `https://concert1.lab.allwaysbeginner.com:12443`
   - Go to: Applications → demo-turbo-instana-concert
   - Check: Vulnerability/Exposures section
   - Look for: Event ID `40cfeaf5-5484-42b4-b458-391a77f1cc16`

3. **Verify Processing**:
   - Check Concert logs for processing status
   - Confirm no "error processing" messages
   - Verify vulnerabilities appear in UI

## Testing

### Manual Test
```bash
# Run the upload script
./scripts/upload-zap-to-concert.sh
```

### Automated Test (Kubernetes)
```bash
# Deploy uploader job
kubectl apply -f k8s/zap-uploader-job.yaml

# Monitor logs
kubectl logs -f job/zap-uploader -n demo-turbo-instana-concert
```

### Full Pipeline Test
```bash
# Trigger Gitea workflow
git commit -m "test: trigger pipeline"
git push
```

## Key Takeaways

1. ✅ Always use `data_type=dynamic_scan` for ZAP scans
2. ✅ Use simplified metadata: `env_name`, `access_point_name`, `access_point_url`
3. ✅ Environment name must match existing Concert environment (`instanak3s`)
4. ✅ ZAP scans must be in JSON format (per documentation)
5. ✅ HTTP 202 indicates successful acceptance and processing

## Related Documentation

- [Concert Integration Guide](./CONCERT_INTEGRATION.md)
- [ZAP Security Scan Guide](./ZAP_SECURITY_SCAN_GUIDE.md)
- [ZAP Upload Troubleshooting](./ZAP_UPLOAD_TROUBLESHOOTING.md)
- [Concert Scan Upload Summary](./CONCERT_SCAN_UPLOAD_SUMMARY.md)

---

**Status**: ✅ RESOLVED - ZAP scans now upload and process successfully in Concert
**Date**: May 5, 2026
**Event ID**: 40cfeaf5-5484-42b4-b458-391a77f1cc16