#!/bin/bash
# OWASP ZAP Security Scan Automation Script
# This script deploys a ZAP security scan job and retrieves the results

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

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}OWASP ZAP Security Scan Automation${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Step 1: Clean up any existing ZAP scan job
echo -e "${YELLOW}Step 1: Cleaning up existing ZAP scan jobs...${NC}"
if kubectl get job "$JOB_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo "Deleting existing job: $JOB_NAME"
    kubectl delete job "$JOB_NAME" -n "$NAMESPACE" --ignore-not-found=true
    sleep 5
fi

# Step 2: Deploy the ZAP scan job
echo -e "${YELLOW}Step 2: Deploying ZAP security scan job...${NC}"
kubectl apply -f k8s/zaptest.yaml

# Step 3: Wait for pod to be created
echo -e "${YELLOW}Step 3: Waiting for ZAP scan pod to start...${NC}"
sleep 10

# Get pod name
POD_NAME=""
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
    echo -e "${RED}ERROR: Failed to get pod name${NC}"
    exit 1
fi

# Step 4: Monitor the scan progress
echo -e "${YELLOW}Step 4: Monitoring ZAP scan progress...${NC}"
echo "This may take several minutes. Press Ctrl+C to stop monitoring (scan will continue)."
echo ""

# Wait for pod to be running
kubectl wait --for=condition=Ready pod/"$POD_NAME" -n "$NAMESPACE" --timeout=120s || true

# Follow logs
echo -e "${BLUE}--- ZAP Scan Logs ---${NC}"
kubectl logs -f "pod/$POD_NAME" -n "$NAMESPACE" || true

# Step 5: Wait for scan completion
echo ""
echo -e "${YELLOW}Step 5: Waiting for scan to complete...${NC}"
kubectl wait --for=condition=complete job/"$JOB_NAME" -n "$NAMESPACE" --timeout=600s || {
    echo -e "${YELLOW}Warning: Job did not complete within timeout. Checking pod status...${NC}"
    kubectl get pod "$POD_NAME" -n "$NAMESPACE"
}

# Step 6: Retrieve scan results
echo -e "${YELLOW}Step 6: Retrieving scan results...${NC}"

# Get updated pod name (in case it changed)
POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l job-name="$JOB_NAME" -o jsonpath='{.items[0].metadata.name}')

# Copy HTML report
HTML_FILE="$OUTPUT_DIR/concert-security-scan-${TIMESTAMP}.html"
echo "Copying HTML report to: $HTML_FILE"
if kubectl -n "$NAMESPACE" cp "$POD_NAME:/zap/wrk/full-scan-report.html" "$HTML_FILE" 2>/dev/null; then
    echo -e "${GREEN}✓ HTML report saved${NC}"
else
    echo -e "${RED}✗ Failed to copy HTML report${NC}"
fi

# Copy JSON report
JSON_FILE="$OUTPUT_DIR/concert-security-scan-${TIMESTAMP}.json"
echo "Copying JSON report to: $JSON_FILE"
if kubectl -n "$NAMESPACE" cp "$POD_NAME:/zap/wrk/full-scan-report.json" "$JSON_FILE" 2>/dev/null; then
    echo -e "${GREEN}✓ JSON report saved${NC}"
else
    echo -e "${RED}✗ Failed to copy JSON report${NC}"
fi

# Create symlinks to latest reports
if [ -f "$HTML_FILE" ]; then
    ln -sf "$(basename "$HTML_FILE")" "$OUTPUT_DIR/concert-security-scan-latest.html"
fi
if [ -f "$JSON_FILE" ]; then
    ln -sf "$(basename "$JSON_FILE")" "$OUTPUT_DIR/concert-security-scan-latest.json"
fi

# Step 7: Display summary
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Scan Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${GREEN}Reports saved to:${NC}"
echo "  HTML: $HTML_FILE"
echo "  JSON: $JSON_FILE"
echo ""
echo -e "${GREEN}Latest reports (symlinks):${NC}"
echo "  HTML: $OUTPUT_DIR/concert-security-scan-latest.html"
echo "  JSON: $OUTPUT_DIR/concert-security-scan-latest.json"
echo ""

# Display file sizes
if [ -f "$HTML_FILE" ]; then
    HTML_SIZE=$(ls -lh "$HTML_FILE" | awk '{print $5}')
    echo "HTML report size: $HTML_SIZE"
fi
if [ -f "$JSON_FILE" ]; then
    JSON_SIZE=$(ls -lh "$JSON_FILE" | awk '{print $5}')
    echo "JSON report size: $JSON_SIZE"
fi

echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Review the security scan reports"
echo "2. Upload to IBM Concert:"
echo "   - Navigate to Concert > Vulnerability/Exposures > Upload exposure"
echo "   - Scan Source: ZAP"
echo "   - Environment: kubernetes_demo-turbo-instana-concert_production"
echo "   - Access Point: concert.lab.allwaysbeginner.com"
echo "   - Upload file: $HTML_FILE or $JSON_FILE"
echo ""
echo -e "${BLUE}To clean up the ZAP scan job:${NC}"
echo "  kubectl delete job $JOB_NAME -n $NAMESPACE"
echo ""

# Made with Bob
