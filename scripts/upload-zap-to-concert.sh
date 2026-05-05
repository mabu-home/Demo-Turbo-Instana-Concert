#!/bin/bash
# Upload ZAP Scan Results to IBM Concert
# This script waits for ZAP scan completion and uploads results to Concert

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

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Upload ZAP Results to IBM Concert${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check required environment variables
if [ -z "$CONCERT_URL" ]; then
    echo -e "${RED}ERROR: CONCERT_URL environment variable not set${NC}"
    exit 1
fi

if [ -z "$CONCERT_API_KEY" ]; then
    echo -e "${RED}ERROR: CONCERT_API_KEY environment variable not set${NC}"
    exit 1
fi

if [ -z "$CONCERT_INSTANCE_ID" ]; then
    echo -e "${RED}ERROR: CONCERT_INSTANCE_ID environment variable not set${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Concert credentials configured${NC}"
echo "  URL: $CONCERT_URL"
echo "  Instance ID: ${CONCERT_INSTANCE_ID:0:8}..."
echo ""

# Step 1: Wait for scan completion with retry logic
echo -e "${YELLOW}Step 1: Waiting for ZAP scan to complete...${NC}"
echo "This may take up to 15 minutes..."

MAX_RETRIES=3
RETRY_COUNT=0
WAIT_TIMEOUT=900  # 15 minutes

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if kubectl wait --for=condition=complete job/$JOB_NAME -n $NAMESPACE --timeout=${WAIT_TIMEOUT}s 2>/dev/null; then
        echo -e "${GREEN}✓ ZAP scan completed successfully${NC}"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo -e "${YELLOW}⚠️  Scan not complete yet. Retry $RETRY_COUNT/$MAX_RETRIES...${NC}"
            echo "Waiting 60 seconds before retry..."
            sleep 60
        else
            echo -e "${YELLOW}⚠️  Scan did not complete within timeout${NC}"
            echo "Checking if reports are available anyway..."
        fi
    fi
done

# Step 2: Get pod name with retry
echo ""
echo -e "${YELLOW}Step 2: Locating ZAP scan pod...${NC}"

RETRY_COUNT=0
POD_NAME=""
while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ -z "$POD_NAME" ]; do
    POD_NAME=$(kubectl get pods -n $NAMESPACE -l job-name=$JOB_NAME -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$POD_NAME" ]; then
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo -e "${YELLOW}⚠️  Pod not found. Retry $RETRY_COUNT/$MAX_RETRIES...${NC}"
            sleep 30
        fi
    fi
done

if [ -z "$POD_NAME" ]; then
    echo -e "${RED}ERROR: ZAP scan pod not found after $MAX_RETRIES retries${NC}"
    echo "Make sure the ZAP scan job has been deployed:"
    echo "  kubectl get job $JOB_NAME -n $NAMESPACE"
    exit 1
fi

echo -e "${GREEN}✓ Found pod: $POD_NAME${NC}"

# Step 3: Retrieve reports with retry logic
echo ""
echo -e "${YELLOW}Step 3: Retrieving scan reports...${NC}"
mkdir -p "$OUTPUT_DIR"

RETRY_COUNT=0
REPORT_RETRIEVED=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$REPORT_RETRIEVED" = "false" ]; do
    # Try to copy JSON report
    JSON_REPORT="$OUTPUT_DIR/concert-security-scan.json"
    if kubectl -n $NAMESPACE cp $POD_NAME:/zap/wrk/full-scan-report.json "$JSON_REPORT" 2>/dev/null; then
        if [ -s "$JSON_REPORT" ]; then
            echo -e "${GREEN}✓ JSON report retrieved${NC}"
            FILE_SIZE=$(ls -lh "$JSON_REPORT" | awk '{print $5}')
            echo "  File: $JSON_REPORT"
            echo "  Size: $FILE_SIZE"
            REPORT_RETRIEVED=true
            break
        fi
    fi
    
    # Try HTML as fallback
    HTML_REPORT="$OUTPUT_DIR/concert-security-scan.html"
    if kubectl -n $NAMESPACE cp $POD_NAME:/zap/wrk/full-scan-report.html "$HTML_REPORT" 2>/dev/null; then
        if [ -s "$HTML_REPORT" ]; then
            echo -e "${GREEN}✓ HTML report retrieved (fallback)${NC}"
            JSON_REPORT="$HTML_REPORT"
            FILE_SIZE=$(ls -lh "$HTML_REPORT" | awk '{print $5}')
            echo "  File: $HTML_REPORT"
            echo "  Size: $FILE_SIZE"
            REPORT_RETRIEVED=true
            break
        fi
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
        echo -e "${YELLOW}⚠️  Reports not available yet. Retry $RETRY_COUNT/$MAX_RETRIES...${NC}"
        echo "Scan may still be generating reports. Waiting 60 seconds..."
        sleep 60
    fi
done

if [ "$REPORT_RETRIEVED" = "false" ]; then
    echo -e "${RED}ERROR: No reports available after $MAX_RETRIES retries${NC}"
    echo ""
    echo "Troubleshooting steps:"
    echo "  1. Check if scan is still running:"
    echo "     kubectl get job $JOB_NAME -n $NAMESPACE"
    echo "  2. Check pod status:"
    echo "     kubectl get pod $POD_NAME -n $NAMESPACE"
    echo "  3. Check pod logs:"
    echo "     kubectl logs $POD_NAME -n $NAMESPACE"
    echo "  4. Check if reports exist in pod:"
    echo "     kubectl exec $POD_NAME -n $NAMESPACE -- ls -la /zap/wrk/"
    exit 1
fi

# Verify file is not empty
if [ ! -s "$JSON_REPORT" ]; then
    echo -e "${RED}ERROR: Report file is empty${NC}"
    exit 1
fi

# Step 4: Validate JSON format (if applicable)
if [[ "$JSON_REPORT" == *.json ]]; then
    echo ""
    echo -e "${YELLOW}Step 4: Validating JSON format...${NC}"
    if command -v jq &> /dev/null; then
        if jq empty "$JSON_REPORT" 2>/dev/null; then
            echo -e "${GREEN}✓ JSON file is valid${NC}"
        else
            echo -e "${RED}ERROR: JSON file is not valid${NC}"
            exit 1
        fi
    else
        echo -e "${YELLOW}⚠️  jq not available, skipping validation${NC}"
    fi
fi

# Step 5: Upload to Concert
echo ""
echo -e "${YELLOW}Step 5: Uploading to IBM Concert...${NC}"
echo "Endpoint: ${CONCERT_URL}/ingestion/api/v1/upload_files"

# Determine file extension
FILE_EXT="${JSON_REPORT##*.}"

# Create metadata with correct Concert format
METADATA="{\"env_name\":\"instanak3s\",\"access_point_name\":\"concert1\",\"access_point_url\":\"http://concert1.lab.allwaysbeginner.com\"}"

# Upload with detailed error handling
HTTP_CODE=$(curl -s -w "%{http_code}" -o /tmp/concert-zap-response.json \
    -X POST "${CONCERT_URL}/ingestion/api/v1/upload_files" \
    -H "accept: application/json" \
    -H "Content-Type: multipart/form-data" \
    -H "InstanceID: ${CONCERT_INSTANCE_ID}" \
    -H "Authorization: C_API_KEY ${CONCERT_API_KEY}" \
    -F "data_type=dynamic_scan" \
    -F "filename=@${JSON_REPORT}" \
    -F "metadata=${METADATA}" \
    --connect-timeout 10 \
    --max-time 120)

echo ""
echo "HTTP Response Code: ${HTTP_CODE}"

# Check response
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "202" ]; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✅ SUCCESS!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "ZAP scan results uploaded to Concert"
    echo ""
    echo "Response:"
    if [ -f /tmp/concert-zap-response.json ]; then
        cat /tmp/concert-zap-response.json | jq '.' 2>/dev/null || cat /tmp/concert-zap-response.json
    fi
    echo ""
    echo "View results in Concert:"
    echo "  ${CONCERT_URL}/applications/demo-turbo-instana-concert"
    echo ""
elif [ "$HTTP_CODE" = "401" ]; then
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}❌ FAILED: Authentication Error${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "HTTP 401 Unauthorized"
    echo ""
    echo "Possible causes:"
    echo "  1. Invalid CONCERT_API_KEY"
    echo "  2. Invalid CONCERT_INSTANCE_ID"
    echo "  3. API key expired"
    echo ""
    echo "Please verify your Concert credentials"
    exit 1
elif [ "$HTTP_CODE" = "404" ]; then
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}❌ FAILED: Application Not Found${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "HTTP 404 Not Found"
    echo ""
    echo "The application 'demo-turbo-instana-concert' does not exist in Concert"
    echo ""
    echo "Please create the application in Concert first:"
    echo "  1. Log into Concert"
    echo "  2. Navigate to Applications"
    echo "  3. Create new application: demo-turbo-instana-concert"
    exit 1
elif [ "$HTTP_CODE" = "413" ]; then
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}❌ FAILED: File Too Large${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "HTTP 413 Payload Too Large"
    echo "Report size: $FILE_SIZE"
    echo ""
    echo "Consider:"
    echo "  1. Reducing ZAP scan scope"
    echo "  2. Using compressed format"
    echo "  3. Filtering results before upload"
    exit 1
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}❌ FAILED: Unexpected Error${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "HTTP ${HTTP_CODE}"
    echo ""
    echo "Response:"
    if [ -f /tmp/concert-zap-response.json ]; then
        cat /tmp/concert-zap-response.json
    fi
    echo ""
    exit 1
fi

# Made with Bob