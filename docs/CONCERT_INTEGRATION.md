# Concert Integration Guide

## Overview

This guide explains how the CI/CD pipeline integrates with IBM Concert for security scanning and SBOM management for the `demo-turbo-instana-concert` application.

## Features

### 1. SAST Scanning with Semgrep
- **When**: Runs after code checkout, before building Docker images
- **What**: Scans both `java-app/` and `python-app/` directories for security vulnerabilities
- **Output**: Generates SARIF and JSON format results
- **Upload**: Automatically uploads SARIF results to Concert

### 2. SBOM Generation with Syft
- **When**: Runs after Docker images are built and pushed
- **What**: Generates Software Bill of Materials for both Java and Python applications
- **Formats**: Creates both SPDX and CycloneDX formats
- **Upload**: Automatically uploads CycloneDX format to Concert (preferred format)

## Required Secrets

Configure these secrets in Gitea: **Repository → Settings → Secrets → Actions**

### Concert API Credentials

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `CONCERT_URL` | Your Concert instance URL | `https://91431.us-south-8.concert.saas.ibm.com` |
| `CONCERT_API_KEY` | Concert API key for authentication | `your-api-key-here` |
| `CONCERT_INSTANCE_ID` | Concert instance identifier | `your-instance-id` |

### How to Obtain Concert Credentials

1. **Concert URL**: Your Concert instance URL (provided by IBM)
2. **API Key**: 
   - Log into Concert
   - Navigate to Settings → API Keys
   - Generate a new API key with appropriate permissions
3. **Instance ID**:
   - Found in Concert Settings → Instance Information
   - Or in the URL when logged into Concert

## Pipeline Workflow

### Step-by-Step Process

```
1. Validate Secrets (includes Concert secrets check)
2. Checkout Code
3. Run Semgrep SAST Scan ← NEW
4. Upload Semgrep Results to Concert ← NEW
5. Install Docker
6. Install kubectl
7. Verify Docker/kubectl
8. Configure Docker Registry
9. Login to Registry
10. Build Java Echo Service
11. Build Python Load Test App
12. Generate Java SBOM
13. Generate Python SBOM
14. Upload SBOMs to Concert ← UPDATED
15. Upload SBOM Artifacts (to Gitea)
16-25. Deploy to Kubernetes...
```

## Concert Application Configuration

### Application Name
- **Concert Application**: `demo-turbo-instana-concert`
- **Kubernetes Namespace**: `demo-turbo-instana-concert`
- Both use the same name for consistency

### Data Uploaded to Concert

1. **SAST Results** (Semgrep)
   - Endpoint: `/core/api/v1/applications/demo-turbo-instana-concert/sast_results`
   - Format: SARIF (Security Analysis Results Interchange Format)
   - Content: Security vulnerabilities found in source code

2. **SBOM - Java Application**
   - Endpoint: `/core/api/v1/applications/demo-turbo-instana-concert/sbom`
   - Format: CycloneDX JSON
   - Content: Complete dependency tree for Java Echo Service

3. **SBOM - Python Application**
   - Endpoint: `/core/api/v1/applications/demo-turbo-instana-concert/sbom`
   - Format: CycloneDX JSON
   - Content: Complete dependency tree for Python Load Test App

## Semgrep SAST Scan Details

### Configuration
- **Rules**: Auto configuration (`--config=auto`)
- **Scope**: Both `java-app/` and `python-app/` directories
- **Output Formats**:
  - SARIF: For Concert upload
  - JSON: For pipeline summary

### Sample Output
```
============================================
Running Semgrep SAST Security Scan
============================================
Installing Semgrep...
Scanning java-app/ and python-app/ directories...
Application: demo-turbo-instana-concert

✓ Semgrep SAST scan completed

Scan Results Summary:
--------------------
Total findings: 15
By severity:
  ERROR: 3
  WARNING: 8
  INFO: 4
============================================
```

### What Semgrep Detects
- SQL injection vulnerabilities
- Cross-site scripting (XSS)
- Command injection
- Path traversal
- Insecure deserialization
- Hardcoded secrets
- Weak cryptography
- And many more security issues

## SBOM Generation Details

### Syft Configuration
- **Tool**: Anchore Syft
- **Execution**: Docker container or native binary
- **Formats Generated**:
  - SPDX JSON (industry standard)
  - CycloneDX JSON (Concert preferred)

### Sample Output
```
Generating SBOM for Java Echo Service...
Image: registry.example.com/repo/echo-service:latest

✓ Java SBOM generated successfully

Workspace files:
  sbom-java.json (SPDX format)
  sbom-java-cyclonedx.json (CycloneDX format)
```

### What SBOM Contains
- All application dependencies
- Library versions
- License information
- Package relationships
- Vulnerability metadata

## Concert Upload Process

### SAST Upload
```bash
curl -X POST "${CONCERT_URL}/core/api/v1/applications/demo-turbo-instana-concert/sast_results" \
  -H "C_API_KEY: ${CONCERT_API_KEY}" \
  -H "InstanceID: ${CONCERT_INSTANCE_ID}" \
  -H "Content-Type: application/sarif+json" \
  --data-binary @semgrep-results.sarif
```

### SBOM Upload
```bash
curl -X POST "${CONCERT_URL}/core/api/v1/applications/demo-turbo-instana-concert/sbom" \
  -H "C_API_KEY: ${CONCERT_API_KEY}" \
  -H "InstanceID: ${CONCERT_INSTANCE_ID}" \
  -H "Content-Type: application/json" \
  --data-binary @sbom-java-cyclonedx.json
```

## Error Handling

### Non-Blocking Failures
Both SAST and SBOM uploads are configured with `continue-on-error: true`, meaning:
- Upload failures won't stop the pipeline
- Deployment continues even if Concert is unavailable
- Errors are logged but don't fail the build

### Common Issues and Solutions

#### 1. Concert Upload Fails with 401 Unauthorized
**Cause**: Invalid API key or Instance ID
**Solution**: 
- Verify `CONCERT_API_KEY` is correct
- Verify `CONCERT_INSTANCE_ID` matches your instance
- Check API key hasn't expired

#### 2. Concert Upload Fails with 404 Not Found
**Cause**: Application doesn't exist in Concert
**Solution**:
- Create application in Concert first
- Ensure application name is exactly `demo-turbo-instana-concert`
- Check Concert URL is correct

#### 3. Semgrep Installation Fails
**Cause**: pip3 not available or network issues
**Solution**:
- Ensure runner has Python 3 and pip3 installed
- Check network connectivity
- Try manual installation: `pip3 install --user semgrep`

#### 4. SBOM Generation Fails
**Cause**: Docker image not found or Syft not available
**Solution**:
- Ensure images are built successfully before SBOM generation
- Check Docker daemon is running
- Verify image names are correct

## Viewing Results in Concert

### SAST Results
1. Log into Concert
2. Navigate to Applications → `demo-turbo-instana-concert`
3. Go to Security → SAST Results
4. View vulnerabilities by severity, file, and rule

### SBOM Data
1. Log into Concert
2. Navigate to Applications → `demo-turbo-instana-concert`
3. Go to Dependencies → SBOM
4. View complete dependency tree
5. Check for known vulnerabilities in dependencies

## Testing the Integration

### Manual Test Commands

1. **Test Semgrep Locally**:
```bash
pip3 install semgrep
semgrep --config=auto --sarif --output=test-results.sarif java-app/ python-app/
```

2. **Test Syft Locally**:
```bash
docker pull anchore/syft:latest
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  anchore/syft:latest your-image:latest -o cyclonedx-json
```

3. **Test Concert API**:
```bash
curl -X GET "${CONCERT_URL}/core/api/v1/applications" \
  -H "C_API_KEY: ${CONCERT_API_KEY}" \
  -H "InstanceID: ${CONCERT_INSTANCE_ID}"
```

## Best Practices

1. **Regular Scans**: Run pipeline on every commit to catch issues early
2. **Review Results**: Regularly check Concert for new vulnerabilities
3. **Update Dependencies**: Use SBOM data to identify outdated packages
4. **Fix Critical Issues**: Prioritize fixing CRITICAL and HIGH severity findings
5. **Monitor Trends**: Track security posture over time in Concert

## Troubleshooting

### Enable Debug Logging
Add to workflow for more verbose output:
```yaml
- name: Debug Concert Upload
  run: |
    curl -v -X POST "${CONCERT_URL}/core/api/v1/applications/demo-turbo-instana-concert/sbom" \
      -H "C_API_KEY: ${CONCERT_API_KEY}" \
      -H "InstanceID: ${CONCERT_INSTANCE_ID}" \
      -H "Content-Type: application/json" \
      --data-binary @sbom-java-cyclonedx.json
```

### Check Generated Files
```bash
# In workflow, add:
- name: Verify Generated Files
  run: |
    echo "SAST Results:"
    ls -lh semgrep-results.*
    echo ""
    echo "SBOM Files:"
    ls -lh sbom-*.json
    echo ""
    echo "Sample SARIF content:"
    head -n 20 semgrep-results.sarif
```

## Support

For issues with:
- **Semgrep**: https://semgrep.dev/docs/
- **Syft**: https://github.com/anchore/syft
- **Concert API**: Contact IBM Concert support
- **Pipeline**: Check Gitea Actions logs

## References

- [Semgrep Documentation](https://semgrep.dev/docs/)
- [Syft Documentation](https://github.com/anchore/syft)
- [SARIF Format](https://sarifweb.azurewebsites.net/)
- [CycloneDX Format](https://cyclonedx.org/)
- [IBM Concert Documentation](https://www.ibm.com/docs/en/concert)