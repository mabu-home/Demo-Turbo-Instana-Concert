#!/bin/bash
# Run ZAP Scan and Upload to Concert
# This script runs a real ZAP scan and uploads it to Concert

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="demo-turbo-instana-concert"
JOB_NAME="zap-full-scan"
OUTPUT_DIR="./security-reports"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Concert Configuration
CONCERT_URL="https://concert1.lab.allwaysbeginner.com:12443"
CONCERT_API_KEY="bWFuZnJlZDo4MWVlYTY0Ny03NDIwLTQ2ZDEtYTA5MC1kYWE5M2VkMDk3Y2Q="
CONCERT_INSTANCE_ID="0000-0000-0000-0000"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}ZAP Scan and Concert Upload${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Step 1: Check if ZAP scan job exists
echo -e "${YELLOW}Step 1: Checking for existing ZAP scan...${NC}"
if kubectl get job "$JOB_NAME" -n "$NAMESPACE" &> /dev/null; then
    POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l job-name="$JOB_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "$POD_NAME" ]; then
        POD_STATUS=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
        echo "Found existing ZAP scan pod: $POD_NAME (Status: $POD_STATUS)"
        
        if [ "$POD_STATUS" = "Succeeded" ] || [ "$POD_STATUS" = "Running" ]; then
            echo -e "${GREEN}Using existing scan results${NC}"
        else
            echo -e "${YELLOW}Pod not ready, will start new scan${NC}"
            kubectl delete job "$JOB_NAME" -n "$NAMESPACE" --ignore-not-found=true
            sleep 5
            POD_NAME=""
        fi
    fi
else
    echo "No existing ZAP scan found"
fi

# Step 2: Start new scan if needed
if [ -z "$POD_NAME" ]; then
    echo -e "${YELLOW}Step 2: Starting new ZAP scan...${NC}"
    kubectl apply -f k8s/zaptest.yaml
    
    echo "Waiting for pod to be created..."
    sleep 10
    
    for i in {1..30}; do
        POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l job-name="$JOB_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [ -n "$POD_NAME" ]; then
            echo -e "${GREEN}Pod created: $POD_NAME${NC}"
            break
        fi
        echo "Waiting for pod creation... (attempt $i/30)"
        sleep 2
    done
    
    if [ -z "$POD_NAME" ]; then
        echo -e "${RED}ERROR: Failed to create pod${NC}"
        exit 1
    fi
    
    echo "Waiting for scan to complete (this may take 10-20 minutes)..."
    kubectl wait --for=condition=complete job/"$JOB_NAME" -n "$NAMESPACE" --timeout=1200s || {
        echo -e "${YELLOW}Warning: Scan may still be running${NC}"
    }
fi

# Step 3: Retrieve scan results
echo ""
echo -e "${YELLOW}Step 3: Retrieving scan results...${NC}"
mkdir -p "$OUTPUT_DIR"

JSON_FILE="$OUTPUT_DIR/zap-scan-${TIMESTAMP}.json"
HTML_FILE="$OUTPUT_DIR/zap-scan-${TIMESTAMP}.html"

echo "Copying JSON report..."
if kubectl -n "$NAMESPACE" cp "$POD_NAME:/zap/wrk/full-scan-report.json" "$JSON_FILE" 2>/dev/null; then
    echo -e "${GREEN}✓ JSON report retrieved${NC}"
    FILE_SIZE=$(ls -lh "$JSON_FILE" | awk '{print $5}')
    echo "  File: $JSON_FILE"
    echo "  Size: $FILE_SIZE"
else
    echo -e "${RED}✗ Failed to copy JSON report${NC}"
    echo "Checking if reports exist in pod..."
    kubectl exec "$POD_NAME" -n "$NAMESPACE" -- ls -la /zap/wrk/ || true
    exit 1
fi

echo "Copying HTML report..."
kubectl -n "$NAMESPACE" cp "$POD_NAME:/zap/wrk/full-scan-report.html" "$HTML_FILE" 2>/dev/null || echo "HTML report not available"

# Step 4: Upload to Concert
echo ""
echo -e "${YELLOW}Step 4: Uploading to Concert...${NC}"
echo "Endpoint: ${CONCERT_URL}/ingestion/api/v1/upload_files"

# Create metadata with correct Concert format
METADATA="{\"env_name\":\"instanak3s\",\"access_point_name\":\"concert1\",\"access_point_url\":\"http://concert1.lab.allwaysbeginner.com\"}"

# Upload
HTTP_CODE=$(curl -s -w "%{http_code}" -o /tmp/concert-upload-response.json \
    -X POST "${CONCERT_URL}/ingestion/api/v1/upload_files" \
    -H "Authorization: C_API_KEY ${CONCERT_API_KEY}" \
    -H "InstanceID: ${CONCERT_INSTANCE_ID}" \
    -H "Content-Type: multipart/form-data" \
    -F "data_type=dynamic_scan" \
    -F "filename=@${JSON_FILE}" \
    -F "metadata=${METADATA}" \
    --insecure \
    --connect-timeout 10 \
    --max-time 120)

echo ""
echo "HTTP Response Code: ${HTTP_CODE}"

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "202" ]; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✅ SUCCESS!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "ZAP scan uploaded to Concert"
    echo ""
    echo "Response:"
    cat /tmp/concert-upload-response.json | jq '.' 2>/dev/null || cat /tmp/concert-upload-response.json
    echo ""
    echo "View results in Concert:"
    echo "  ${CONCERT_URL}/applications/demo-turbo-instana-concert"
    echo ""
    echo "Files saved:"
    echo "  JSON: $JSON_FILE"
    [ -f "$HTML_FILE" ] && echo "  HTML: $HTML_FILE"
    echo ""
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}❌ UPLOAD FAILED${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "HTTP ${HTTP_CODE}"
    echo ""
    echo "Response:"
    cat /tmp/concert-upload-response.json 2>/dev/null || echo "No response body"
    echo ""
    exit 1
fi

# Made with Bob