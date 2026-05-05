# Concert Security Scan Upload Summary

## ✅ DAST (ZAP) Upload - SUCCESS

### Upload Details
- **Date**: May 4, 2026 17:25:59 UTC
- **Status**: HTTP 202 Accepted
- **Event ID**: `65942907-be98-433c-94b6-7bc3a371af37`
- **Record Path**: `0000-0000-0000-0000/roja/dynamic_code_scan/2026/5/4/191372967_test-zap-scan.json`

### DAST Upload Command (Working)
```bash
curl -X POST "https://concert1.lab.allwaysbeginner.com:12443/ingestion/api/v1/upload_files" \
  -H "Authorization: C_API_KEY bWFuZnJlZDo4MWVlYTY0Ny03NDIwLTQ2ZDEtYTA5MC1kYWE5M2VkMDk3Y2Q=" \
  -H "InstanceID: 0000-0000-0000-0000" \
  -H "Content-Type: multipart/form-data" \
  -F "data_type=dynamic_code_scan" \
  -F "filename=@security-reports/test-zap-scan.json" \
  -F 'metadata={"env_name":"prod","tool":"zap","format":"json","scan_type":"dast","access_point":"concert.lab.allwaysbeginner.com","application":"demo-turbo-instana-concert"}' \
  --insecure
```

### DAST Response
```json
{
  "record_paths": [
    "0000-0000-0000-0000/roja/dynamic_code_scan/2026/5/4/191372967_test-zap-scan.json"
  ],
  "event_ids": [
    "65942907-be98-433c-94b6-7bc3a371af37"
  ],
  "job_data": {
    "message": "202 Accepted"
  }
}
```

### DAST Scan Contents
The test ZAP scan included **5 security findings**:
1. **High Risk**: Cross Site Scripting (Reflected) - XSS vulnerability
2. **Medium Risk**: Cross-Domain Misconfiguration - CORS issue
3. **Low Risk**: X-Content-Type-Options Header Missing
4. **Low Risk**: Strict-Transport-Security Header Not Set
5. **Low Risk**: Application Error Disclosure

---

## ⚠️ SAST Upload - Endpoint Not Available

### Attempted SAST Upload
The SAST endpoint appears to not be available in this Concert instance:
- **Endpoint Tried**: `/core/api/v1/applications/{app_id}/sast_results`
- **Status**: HTTP 404 Not Found
- **Application ID**: `861f409f-f488-495f-bfc9-d81418ae2f4f`
- **Application Name**: `demo-turbo-instana-concert`

### SAST Upload Command (404 Error)
```bash
curl -X POST "https://concert1.lab.allwaysbeginner.com:12443/core/api/v1/applications/861f409f-f488-495f-bfc9-d81418ae2f4f/sast_results" \
  -H "Authorization: C_API_KEY bWFuZnJlZDo4MWVlYTY0Ny03NDIwLTQ2ZDEtYTA5MC1kYWE5M2VkMDk3Y2Q=" \
  -H "InstanceID: 0000-0000-0000-0000" \
  -H "Content-Type: application/sarif+json" \
  --data-binary @security-reports/test-sast-semgrep.sarif \
  --insecure
```

### SAST Scan Contents (Created but Not Uploaded)
The test SAST scan in SARIF format included **5 security findings**:
1. **Error**: Dangerous system call - Command injection risk
2. **Error**: Hardcoded secret - Secret management issue
3. **Error**: SQL injection vulnerability
4. **Warning**: XSS vulnerability in template
5. **Warning**: Insecure hash function (MD5)

### Possible Reasons for SAST 404
1. **Feature Not Enabled**: SAST upload might not be enabled in this Concert instance
2. **Different Endpoint**: The endpoint path might be different in this version
3. **License Limitation**: SAST features might require a specific license
4. **API Version**: The endpoint might be in a different API version

### Alternative SAST Upload Methods
Since the direct SAST endpoint is not available, you can try:

1. **Use the Generic Upload Endpoint** (like DAST):
```bash
curl -X POST "https://concert1.lab.allwaysbeginner.com:12443/ingestion/api/v1/upload_files" \
  -H "Authorization: C_API_KEY bWFuZnJlZDo4MWVlYTY0Ny03NDIwLTQ2ZDEtYTA5MC1kYWE5M2VkMDk3Y2Q=" \
  -H "InstanceID: 0000-0000-0000-0000" \
  -H "Content-Type: multipart/form-data" \
  -F "data_type=static_code_scan" \
  -F "filename=@security-reports/test-sast-semgrep.sarif" \
  -F 'metadata={"env_name":"prod","tool":"semgrep","format":"sarif","scan_type":"sast","application":"demo-turbo-instana-concert"}' \
  --insecure
```

2. **Check Concert Documentation**: Verify the correct SAST upload endpoint for your Concert version

3. **Contact IBM Support**: Ask about SAST upload capabilities in your Concert instance

---

## Concert Configuration

### Authentication
- **URL**: `https://concert1.lab.allwaysbeginner.com:12443`
- **Instance ID**: `0000-0000-0000-0000`
- **API Key**: `bWFuZnJlZDo4MWVlYTY0Ny03NDIwLTQ2ZDEtYTA5MC1kYWE5M2VkMDk3Y2Q=`
- **Auth Format**: `Authorization: C_API_KEY <token>`

### Application Details
- **Name**: `demo-turbo-instana-concert`
- **ID**: `861f409f-f488-495f-bfc9-d81418ae2f4f`
- **Version**: `1.0.0`
- **Environment**: `instanak3s` (Production)

---

## Files Created

1. **DAST Scan**: `security-reports/test-zap-scan.json` ✅ Uploaded
2. **SAST Scan**: `security-reports/test-sast-semgrep.sarif` ⚠️ Not uploaded (endpoint unavailable)
3. **Documentation**: 
   - `docs/ZAP_TEST_UPLOAD_SUCCESS.md`
   - `docs/CONCERT_SCAN_UPLOAD_SUMMARY.md` (this file)

---

## View Results in Concert

1. Navigate to: `https://concert1.lab.allwaysbeginner.com:12443`
2. Go to **Applications** → **demo-turbo-instana-concert**
3. Look for **Vulnerability/Exposures** or **Security Scans** section
4. You should see the uploaded ZAP scan with Event ID: `65942907-be98-433c-94b6-7bc3a371af37`

---

## Next Steps

### For DAST (Working)
✅ Use the working DAST upload command for ZAP scans
✅ Integrate into CI/CD pipeline
✅ Monitor Concert for scan results

### For SAST (Needs Investigation)
⚠️ Contact IBM Support to verify SAST upload endpoint
⚠️ Check Concert version and feature availability
⚠️ Try alternative upload methods (generic ingestion endpoint)
⚠️ Review Concert documentation for SAST capabilities

---

## Summary

| Scan Type | Status | Endpoint | HTTP Code | Event ID |
|-----------|--------|----------|-----------|----------|
| DAST (ZAP) | ✅ Success | `/ingestion/api/v1/upload_files` | 202 | 65942907-be98-433c-94b6-7bc3a371af37 |
| SAST (Semgrep) | ⚠️ Failed | `/core/api/v1/applications/{id}/sast_results` | 404 | N/A |

**Recommendation**: Use the working DAST upload endpoint for all security scans until SAST endpoint availability is confirmed.