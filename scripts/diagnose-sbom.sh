#!/bin/bash

# SBOM Diagnostic Script
# This script helps diagnose SBOM generation and upload issues

set -e

echo "============================================"
echo "SBOM Diagnostic Tool"
echo "============================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
    fi
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# 1. Check Docker
echo "1. Checking Docker..."
if command -v docker &> /dev/null; then
    print_status 0 "Docker is installed"
    docker --version
    
    if docker info &> /dev/null; then
        print_status 0 "Docker daemon is running"
    else
        print_status 1 "Docker daemon is not running or not accessible"
        echo "  Try: sudo systemctl start docker"
    fi
else
    print_status 1 "Docker is not installed"
    echo "  Install: https://docs.docker.com/engine/install/"
fi
echo ""

# 2. Check Syft
echo "2. Checking Syft..."
if command -v syft &> /dev/null; then
    print_status 0 "Syft is installed"
    syft version
else
    print_warning "Syft is not installed (will use Docker-based Syft)"
    echo "  Install: curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin"
fi
echo ""

# 3. Check Docker Images
echo "3. Checking Docker Images..."
REGISTRY="${GIT_REGISTRY:-registry.example.com}"
REPO="${GITEA_REPOSITORY:-demo/demo-turbo-instana-concert}"
REPO_LOWER=$(echo "$REPO" | tr '[:upper:]' '[:lower:]')

JAVA_IMAGE="${REGISTRY}/${REPO_LOWER}/echo-service:latest"
PYTHON_IMAGE="${REGISTRY}/${REPO_LOWER}/load-test-app:latest"

echo "Looking for images:"
echo "  - $JAVA_IMAGE"
echo "  - $PYTHON_IMAGE"
echo ""

if docker image inspect "$JAVA_IMAGE" &> /dev/null; then
    print_status 0 "Java image found: $JAVA_IMAGE"
else
    print_status 1 "Java image not found: $JAVA_IMAGE"
    echo "  Try: docker pull $JAVA_IMAGE"
fi

if docker image inspect "$PYTHON_IMAGE" &> /dev/null; then
    print_status 0 "Python image found: $PYTHON_IMAGE"
else
    print_status 1 "Python image not found: $PYTHON_IMAGE"
    echo "  Try: docker pull $PYTHON_IMAGE"
fi
echo ""

# 4. Check File Locations
echo "4. Checking SBOM File Locations..."
WORKSPACE_DIR="${WORKSPACE_DIR:-.}"

echo "Workspace directory: $WORKSPACE_DIR"
if [ -d "$WORKSPACE_DIR" ]; then
    print_status 0 "Workspace directory exists"
    ls -lh "$WORKSPACE_DIR"/sbom-*.json 2>/dev/null || print_warning "No SBOM files in workspace"
else
    print_status 1 "Workspace directory not found"
fi
echo ""

echo "/tmp/sbom-output directory:"
if [ -d "/tmp/sbom-output" ]; then
    print_status 0 "/tmp/sbom-output exists"
    ls -lh /tmp/sbom-output/sbom-*.json 2>/dev/null || print_warning "No SBOM files in /tmp/sbom-output"
else
    print_warning "/tmp/sbom-output does not exist"
    echo "  Creating: mkdir -p /tmp/sbom-output"
    mkdir -p /tmp/sbom-output
fi
echo ""

# 5. Test SBOM Generation
echo "5. Testing SBOM Generation..."
if command -v syft &> /dev/null && docker image inspect alpine:latest &> /dev/null 2>&1 || docker pull alpine:latest &> /dev/null; then
    echo "Testing with alpine:latest image..."
    TEST_OUTPUT="/tmp/sbom-test-$(date +%s).json"
    
    if syft alpine:latest -o cyclonedx-json="$TEST_OUTPUT" &> /dev/null; then
        print_status 0 "SBOM generation test successful"
        echo "  Output: $TEST_OUTPUT"
        
        # Verify it's valid JSON
        if jq . "$TEST_OUTPUT" &> /dev/null; then
            print_status 0 "Generated SBOM is valid JSON"
        else
            print_status 1 "Generated SBOM is not valid JSON"
        fi
        
        # Clean up
        rm -f "$TEST_OUTPUT"
    else
        print_status 1 "SBOM generation test failed"
    fi
else
    print_warning "Skipping SBOM generation test (syft or alpine image not available)"
fi
echo ""

# 6. Check Concert Configuration
echo "6. Checking Concert Configuration..."
if [ -n "$CONCERT_URL" ]; then
    print_status 0 "CONCERT_URL is set: $CONCERT_URL"
else
    print_status 1 "CONCERT_URL is not set"
fi

if [ -n "$CONCERT_API_KEY" ]; then
    print_status 0 "CONCERT_API_KEY is set (${#CONCERT_API_KEY} characters)"
else
    print_status 1 "CONCERT_API_KEY is not set"
fi

if [ -n "$CONCERT_INSTANCE_ID" ]; then
    print_status 0 "CONCERT_INSTANCE_ID is set: $CONCERT_INSTANCE_ID"
else
    print_status 1 "CONCERT_INSTANCE_ID is not set"
fi
echo ""

# 7. Test Concert Connectivity
if [ -n "$CONCERT_URL" ] && [ -n "$CONCERT_API_KEY" ] && [ -n "$CONCERT_INSTANCE_ID" ]; then
    echo "7. Testing Concert API Connectivity..."
    
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -X GET "${CONCERT_URL}/core/api/v1/applications" \
        -H "C_API_KEY: ${CONCERT_API_KEY}" \
        -H "InstanceID: ${CONCERT_INSTANCE_ID}" \
        --connect-timeout 10 \
        --max-time 30 2>/dev/null || echo "000")
    
    if [ "$HTTP_CODE" = "200" ]; then
        print_status 0 "Concert API is accessible (HTTP $HTTP_CODE)"
        
        # Check if application exists
        APP_EXISTS=$(curl -s \
            -X GET "${CONCERT_URL}/core/api/v1/applications" \
            -H "C_API_KEY: ${CONCERT_API_KEY}" \
            -H "InstanceID: ${CONCERT_INSTANCE_ID}" 2>/dev/null | \
            jq -r '.applications[]? | select(.name=="demo-turbo-instana-concert") | .name' 2>/dev/null || echo "")
        
        if [ "$APP_EXISTS" = "demo-turbo-instana-concert" ]; then
            print_status 0 "Application 'demo-turbo-instana-concert' exists in Concert"
        else
            print_status 1 "Application 'demo-turbo-instana-concert' not found in Concert"
            echo "  Create the application in Concert first"
        fi
    elif [ "$HTTP_CODE" = "401" ]; then
        print_status 1 "Concert API authentication failed (HTTP $HTTP_CODE)"
        echo "  Check CONCERT_API_KEY and CONCERT_INSTANCE_ID"
    elif [ "$HTTP_CODE" = "000" ]; then
        print_status 1 "Cannot connect to Concert API"
        echo "  Check CONCERT_URL and network connectivity"
    else
        print_status 1 "Concert API returned HTTP $HTTP_CODE"
    fi
else
    print_warning "Skipping Concert connectivity test (credentials not set)"
fi
echo ""

# 8. Summary
echo "============================================"
echo "Diagnostic Summary"
echo "============================================"
echo ""
echo "Next Steps:"
echo ""

# Provide recommendations
ISSUES=0

if ! command -v docker &> /dev/null; then
    echo "1. Install Docker"
    ISSUES=$((ISSUES + 1))
fi

if ! docker info &> /dev/null 2>&1; then
    echo "2. Start Docker daemon: sudo systemctl start docker"
    ISSUES=$((ISSUES + 1))
fi

if ! command -v syft &> /dev/null; then
    echo "3. Install Syft (optional, can use Docker-based): curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin"
fi

if ! docker image inspect "$JAVA_IMAGE" &> /dev/null 2>&1; then
    echo "4. Build or pull Java image: docker build -t $JAVA_IMAGE ./java-app"
    ISSUES=$((ISSUES + 1))
fi

if ! docker image inspect "$PYTHON_IMAGE" &> /dev/null 2>&1; then
    echo "5. Build or pull Python image: docker build -t $PYTHON_IMAGE ./python-app"
    ISSUES=$((ISSUES + 1))
fi

if [ -z "$CONCERT_URL" ] || [ -z "$CONCERT_API_KEY" ] || [ -z "$CONCERT_INSTANCE_ID" ]; then
    echo "6. Set Concert environment variables (see docs/CONCERT_SECRETS_SETUP.md)"
    ISSUES=$((ISSUES + 1))
fi

if [ $ISSUES -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed! Ready to generate and upload SBOMs.${NC}"
else
    echo -e "${YELLOW}⚠ Found $ISSUES issue(s) that need attention.${NC}"
fi

echo ""
echo "For more help, see: docs/SBOM_TROUBLESHOOTING.md"
echo "============================================"

# Made with Bob
