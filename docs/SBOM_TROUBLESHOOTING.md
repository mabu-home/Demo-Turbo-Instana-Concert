# SBOM Upload Troubleshooting Guide

## Overview
This guide helps troubleshoot issues with SBOM (Software Bill of Materials) generation and upload to IBM Concert.

## Common Issues and Solutions

### Issue 1: "No SBOM files found"

**Symptoms:**
```
Looking for SBOM files in: /workspace/test/Demo-Turbo-Instana-Concert
No SBOM files found
⚠️  Java SBOM file not found: /workspace/test/Demo-Turbo-Instana-Concert/sbom-java-cyclonedx.json
⚠️  Python SBOM file not found: /workspace/test/Demo-Turbo-Instana-Concert/sbom-python-cyclonedx.json
```

**Root Causes:**
1. SBOM generation step failed silently
2. Docker images not available for scanning
3. Syft tool not installed or not working
4. File permissions issues
5. Wrong directory paths

**Solutions:**

#### 1. Check SBOM Generation Logs
Look for the "Generate SBOM" steps in the workflow output:
```bash
# Search for SBOM generation in workflow logs
grep -A 20 "Generating SBOM" workflow.log
```

#### 2. Verify Docker Images Exist
```bash
# Check if images were built successfully
docker images | grep echo-service
docker images | grep load-test-app

# Try to inspect the images
docker image inspect <registry>/echo-service:latest
docker image inspect <registry>/load-test-app:latest
```

#### 3. Install Syft on Runner
```bash
# Install Syft on the Gitea runner host
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin

# Verify installation
syft version
```

#### 4. Test SBOM Generation Manually
```bash
# Test with a simple image
syft alpine:latest -o cyclonedx-json=/tmp/test-sbom.json

# Test with your actual images
syft <registry>/echo-service:latest -o cyclonedx-json=/tmp/sbom-java-cyclonedx.json
syft <registry>/load-test-app:latest -o cyclonedx-json=/tmp/sbom-python-cyclonedx.json
```

#### 5. Check File Locations
The workflow now checks multiple locations:
```bash
# Check workspace directory
ls -lh $WORKSPACE_DIR/sbom-*.json

# Check /tmp directory
ls -lh /tmp/sbom-output/sbom-*.json

# Check current directory
ls -lh ./sbom-*.json
```

### Issue 2: SBOM Generation Fails

**Symptoms:**
```
❌ Syft scan failed
```

**Solutions:**

#### 1. Check Docker Socket Permissions
```bash
# Verify Docker socket is accessible
ls -l /var/run/docker.sock

# Fix permissions if needed
sudo chmod 666 /var/run/docker.sock
```

#### 2. Verify Image Registry Access
```bash
# Test registry login
docker login <registry>

# Try pulling the image
docker pull <registry>/echo-service:latest
```

#### 3. Check Syft Docker Container
```bash
# Test Syft Docker container
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  anchore/syft:latest \
  alpine:latest \
  -o cyclonedx-json=/dev/stdout
```

### Issue 3: Concert Upload Fails

**Symptoms:**
```
⚠️  Java SBOM upload failed with HTTP 400/401/500
```

**Solutions:**

#### 1. Verify Concert Credentials
```bash
# Check if secrets are set
echo "CONCERT_URL: ${CONCERT_URL}"
echo "CONCERT_API_KEY: ${CONCERT_API_KEY:0:10}..." # Show first 10 chars only
echo "CONCERT_INSTANCE_ID: ${CONCERT_INSTANCE_ID}"
```

#### 2. Test Concert API Manually
```bash
# Test authentication
curl -X GET "${CONCERT_URL}/core/api/v1/applications" \
  -H "C_API_KEY: ${CONCERT_API_KEY}" \
  -H "InstanceID: ${CONCERT_INSTANCE_ID}"

# Test SBOM upload
curl -X POST "${CONCERT_URL}/core/api/v1/applications/demo-turbo-instana-concert/sbom" \
  -H "C_API_KEY: ${CONCERT_API_KEY}" \
  -H "InstanceID: ${CONCERT_INSTANCE_ID}" \
  -H "Content-Type: application/json" \
  --data-binary @sbom-java-cyclonedx.json \
  -v
```

#### 3. Verify SBOM Format
```bash
# Check if SBOM is valid JSON
jq . sbom-java-cyclonedx.json

# Verify it's CycloneDX format
jq '.bomFormat' sbom-java-cyclonedx.json
# Should output: "CycloneDX"

jq '.specVersion' sbom-java-cyclonedx.json
# Should output a version like: "1.4" or "1.5"
```

#### 4. Check Application Name in Concert
The application must exist in Concert with the exact name:
```bash
# List applications in Concert
curl -X GET "${CONCERT_URL}/core/api/v1/applications" \
  -H "C_API_KEY: ${CONCERT_API_KEY}" \
  -H "InstanceID: ${CONCERT_INSTANCE_ID}" | jq '.applications[].name'

# Verify "demo-turbo-instana-concert" exists
```

### Issue 4: Workflow Improvements Applied

The workflow has been updated with the following improvements:

#### 1. Enhanced SBOM Generation
- Added `continue-on-error: true` to prevent workflow failure
- Better error messages and debugging output
- File verification after generation
- Checks both workspace and /tmp directories

#### 2. Improved Upload Logic
- Checks multiple file locations (workspace and /tmp)
- Automatic fallback to alternative directory
- Better error messages
- Skips upload gracefully if no files found

#### 3. Better Logging
```
============================================
Generating SBOM for Java Echo Service
============================================
Image: registry.example.com/repo/echo-service:latest
Workspace: /workspace/test/Demo-Turbo-Instana-Concert

✓ Image found, generating SBOM...
Using native syft (v0.100.0)...
✓ Java SBOM generated successfully

Verifying generated files:
Workspace directory (/workspace/test/Demo-Turbo-Instana-Concert):
-rw-r--r-- 1 runner runner 45678 Apr 30 08:30 sbom-java-cyclonedx.json

/tmp/sbom-output directory:
-rw-r--r-- 1 runner runner 45678 Apr 30 08:30 sbom-java-cyclonedx.json

✓ SBOM file verification passed
============================================
```

## Verification Checklist

Before running the workflow, verify:

- [ ] Docker is installed and running on the runner
- [ ] Syft is installed (or Docker can pull anchore/syft:latest)
- [ ] Docker images were built successfully
- [ ] Concert secrets are configured correctly
- [ ] Application exists in Concert with correct name
- [ ] Network connectivity to Concert API
- [ ] File permissions allow writing to workspace and /tmp

## Manual Testing Commands

### Test Complete SBOM Workflow
```bash
# 1. Build images
docker build -t test/echo-service:latest ./java-app
docker build -t test/load-test-app:latest ./python-app

# 2. Generate SBOMs
syft test/echo-service:latest -o cyclonedx-json=sbom-java-cyclonedx.json
syft test/load-test-app:latest -o cyclonedx-json=sbom-python-cyclonedx.json

# 3. Verify SBOMs
jq . sbom-java-cyclonedx.json
jq . sbom-python-cyclonedx.json

# 4. Upload to Concert
curl -X POST "${CONCERT_URL}/core/api/v1/applications/demo-turbo-instana-concert/sbom" \
  -H "C_API_KEY: ${CONCERT_API_KEY}" \
  -H "InstanceID: ${CONCERT_INSTANCE_ID}" \
  -H "Content-Type: application/json" \
  --data-binary @sbom-java-cyclonedx.json

curl -X POST "${CONCERT_URL}/core/api/v1/applications/demo-turbo-instana-concert/sbom" \
  -H "C_API_KEY: ${CONCERT_API_KEY}" \
  -H "InstanceID: ${CONCERT_INSTANCE_ID}" \
  -H "Content-Type: application/json" \
  --data-binary @sbom-python-cyclonedx.json
```

## Getting Help

If issues persist:

1. Check the complete workflow logs
2. Verify all prerequisites are met
3. Test each step manually
4. Check Concert API documentation
5. Review Syft documentation: https://github.com/anchore/syft

## Related Documentation

- [Concert Integration Guide](CONCERT_INTEGRATION.md)
- [Concert Secrets Setup](CONCERT_SECRETS_SETUP.md)
- [Gitea Deployment Guide](GITEA_DEPLOYMENT_GUIDE.md)