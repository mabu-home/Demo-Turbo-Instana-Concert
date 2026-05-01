# Ingress 404 Troubleshooting Guide

## Issue: Getting 404 Error on Ingress

If you're getting a 404 error when accessing `concert.lab.allwaysbeginner.com`, follow these troubleshooting steps:

## Prerequisites Check

### 1. Verify Kubernetes Cluster is Running

```bash
# Check cluster connectivity
kubectl cluster-info

# If you see "host is down" error:
# - Verify the K8s node at 192.168.178.35 is powered on
# - Check network connectivity: ping 192.168.178.35
# - Restart the K8s cluster if needed
```

### 2. Verify DNS/Hosts File Configuration

```bash
# Check if hostname resolves
ping concert.lab.allwaysbeginner.com

# If it doesn't resolve, add to /etc/hosts:
echo "192.168.178.35  concert.lab.allwaysbeginner.com" | sudo tee -a /etc/hosts

# Verify the entry
cat /etc/hosts | grep concert
```

## Troubleshooting Steps

### Step 1: Check Ingress Status

```bash
# Get ingress details
kubectl get ingress -n demo-turbo-instana-concert

# Expected output should show:
# NAME                                  CLASS   HOSTS                              ADDRESS   PORTS
# demo-turbo-instana-concert-ingress   nginx   concert.lab.allwaysbeginner.com    ...       80, 443

# Get detailed ingress configuration
kubectl describe ingress demo-turbo-instana-concert-ingress -n demo-turbo-instana-concert
```

**Common Issues:**
- ❌ Ingress not found → Apply the ingress: `kubectl apply -f k8s/ingress.yaml`
- ❌ Wrong hostname → Should be `concert.lab.allwaysbeginner.com`
- ❌ No ADDRESS → Ingress controller may not be running

### Step 2: Verify Ingress Controller

```bash
# Check if nginx ingress controller is running
kubectl get pods -n ingress-nginx

# Or check for other ingress controllers
kubectl get pods -A | grep ingress

# If no ingress controller found, install nginx ingress:
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml
```

### Step 3: Check Backend Services

```bash
# Verify services exist and have endpoints
kubectl get svc -n demo-turbo-instana-concert

# Expected services:
# - load-test-service (port 80)
# - vulnerable-echo-service (port 8085)

# Check service endpoints
kubectl get endpoints -n demo-turbo-instana-concert

# If no endpoints, check pods
kubectl get pods -n demo-turbo-instana-concert
```

**Common Issues:**
- ❌ Service not found → Deploy applications: `kubectl apply -f k8s/`
- ❌ No endpoints → Pods may not be running or selector mismatch
- ❌ Pods not ready → Check pod logs: `kubectl logs <pod-name> -n demo-turbo-instana-concert`

### Step 4: Test Service Connectivity Internally

```bash
# Test load-test-service from within cluster
kubectl run test-curl --image=curlimages/curl --rm -it --restart=Never -- \
  curl -v http://load-test-service.demo-turbo-instana-concert.svc.cluster.local/health

# Expected: 200 OK response

# Test vulnerable-echo-service
kubectl run test-curl --image=curlimages/curl --rm -it --restart=Never -- \
  curl -v http://vulnerable-echo-service.demo-turbo-instana-concert.svc.cluster.local:8085/api/echo
```

**If internal tests fail:**
- Check pod logs: `kubectl logs -l app=load-test-app -n demo-turbo-instana-concert`
- Check pod status: `kubectl describe pod <pod-name> -n demo-turbo-instana-concert`
- Verify port configuration in deployments

### Step 5: Check Ingress Rules

```bash
# View ingress configuration in detail
kubectl get ingress demo-turbo-instana-concert-ingress -n demo-turbo-instana-concert -o yaml

# Verify:
# 1. Host matches: concert.lab.allwaysbeginner.com
# 2. Paths are configured correctly
# 3. Backend services match existing services
# 4. Ports match service ports
```

### Step 6: Test Ingress Paths

```bash
# Test different paths (replace with your actual hostname/IP)
HOST="concert.lab.allwaysbeginner.com"

# Test health endpoint
curl -v http://$HOST/health

# Test echo endpoint
curl -v http://$HOST/api/echo

# Test root path
curl -v http://$HOST/

# Test with IP directly (bypass DNS)
curl -v -H "Host: concert.lab.allwaysbeginner.com" http://192.168.178.35/health
```

### Step 7: Check Ingress Controller Logs

```bash
# Get ingress controller pod name
INGRESS_POD=$(kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].metadata.name}')

# View logs
kubectl logs $INGRESS_POD -n ingress-nginx --tail=100

# Look for:
# - 404 errors with specific paths
# - Backend connection errors
# - SSL/TLS errors
# - Configuration reload errors
```

## Common 404 Causes and Solutions

### 1. Ingress Not Applied After Hostname Change

**Problem:** Ingress still has old hostname in cluster

**Solution:**
```bash
# Re-apply the ingress configuration
kubectl apply -f k8s/ingress.yaml

# Verify the change
kubectl get ingress -n demo-turbo-instana-concert -o yaml | grep -A 2 "host:"
```

### 2. Services Not Running

**Problem:** Backend services are not deployed or not ready

**Solution:**
```bash
# Deploy all resources
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmaps.yaml
kubectl apply -f k8s/python-app-deployment.yaml
kubectl apply -f k8s/echo-service-deployment.yaml
kubectl apply -f k8s/ingress.yaml

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app=load-test-app -n demo-turbo-instana-concert --timeout=120s
kubectl wait --for=condition=ready pod -l app=vulnerable-echo-service -n demo-turbo-instana-concert --timeout=120s
```

### 3. Path Mismatch

**Problem:** Requested path doesn't match any ingress rule

**Solution:**
```bash
# Check available paths in ingress
kubectl get ingress demo-turbo-instana-concert-ingress -n demo-turbo-instana-concert -o jsonpath='{.spec.rules[0].http.paths[*].path}' | tr ' ' '\n'

# Available paths should include:
# /stress, /echo, /stop, /ramp, /wave, /flood, /health, /metrics, /status, /api/echo, /
```

### 4. Ingress Controller Not Running

**Problem:** No ingress controller to process ingress rules

**Solution:**
```bash
# Check for ingress controller
kubectl get pods -A | grep ingress

# If not found, install nginx ingress controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml

# Wait for it to be ready
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

### 5. DNS Not Resolving

**Problem:** Hostname doesn't resolve to cluster IP

**Solution:**
```bash
# Add to /etc/hosts
echo "192.168.178.35  concert.lab.allwaysbeginner.com" | sudo tee -a /etc/hosts

# Or test with IP and Host header
curl -H "Host: concert.lab.allwaysbeginner.com" http://192.168.178.35/health
```

## Quick Fix Script

Create a script to quickly diagnose and fix common issues:

```bash
#!/bin/bash
# ingress-fix.sh

echo "=== Ingress Troubleshooting ==="
echo ""

# 1. Check cluster
echo "1. Checking cluster connectivity..."
if ! kubectl cluster-info &>/dev/null; then
    echo "❌ Cluster is not accessible"
    exit 1
fi
echo "✓ Cluster is accessible"

# 2. Check namespace
echo "2. Checking namespace..."
if ! kubectl get namespace demo-turbo-instana-concert &>/dev/null; then
    echo "❌ Namespace not found, creating..."
    kubectl apply -f k8s/namespace.yaml
fi
echo "✓ Namespace exists"

# 3. Check services
echo "3. Checking services..."
kubectl get svc -n demo-turbo-instana-concert

# 4. Check pods
echo "4. Checking pods..."
kubectl get pods -n demo-turbo-instana-concert

# 5. Check ingress
echo "5. Checking ingress..."
kubectl get ingress -n demo-turbo-instana-concert

# 6. Re-apply ingress
echo "6. Re-applying ingress configuration..."
kubectl apply -f k8s/ingress.yaml

# 7. Test internal connectivity
echo "7. Testing internal service connectivity..."
kubectl run test-curl --image=curlimages/curl --rm -it --restart=Never -- \
  curl -s http://load-test-service.demo-turbo-instana-concert.svc.cluster.local/health || echo "❌ Internal test failed"

echo ""
echo "=== Troubleshooting Complete ==="
echo "Try accessing: http://concert.lab.allwaysbeginner.com/health"
```

## Verification Checklist

After troubleshooting, verify everything works:

- [ ] Cluster is accessible: `kubectl cluster-info`
- [ ] Namespace exists: `kubectl get ns demo-turbo-instana-concert`
- [ ] Services are running: `kubectl get svc -n demo-turbo-instana-concert`
- [ ] Pods are ready: `kubectl get pods -n demo-turbo-instana-concert`
- [ ] Ingress exists: `kubectl get ingress -n demo-turbo-instana-concert`
- [ ] Ingress has correct hostname: `concert.lab.allwaysbeginner.com`
- [ ] Ingress controller is running: `kubectl get pods -A | grep ingress`
- [ ] DNS/hosts file configured: `ping concert.lab.allwaysbeginner.com`
- [ ] Health endpoint works: `curl http://concert.lab.allwaysbeginner.com/health`
- [ ] Echo endpoint works: `curl http://concert.lab.allwaysbeginner.com/api/echo`

## Still Having Issues?

If you've tried all the above and still getting 404:

1. **Capture detailed logs:**
   ```bash
   # Ingress controller logs
   kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=200 > ingress-logs.txt
   
   # Service logs
   kubectl logs -n demo-turbo-instana-concert -l app=load-test-app --tail=200 > app-logs.txt
   
   # Ingress configuration
   kubectl get ingress -n demo-turbo-instana-concert -o yaml > ingress-config.yaml
   ```

2. **Check ingress annotations:**
   - Verify ingress class is correct (`nginx`)
   - Check for conflicting annotations
   - Ensure TLS configuration is valid

3. **Test with different ingress class:**
   ```bash
   # If using Traefik instead of nginx
   kubectl get ingressclass
   
   # Update ingress.yaml if needed
   ```

4. **Restart ingress controller:**
   ```bash
   kubectl rollout restart deployment -n ingress-nginx ingress-nginx-controller
   ```

## Related Documentation

- [K3S_REGISTRY_FIX.md](./K3S_REGISTRY_FIX.md) - Registry troubleshooting
- [REGISTRY_TROUBLESHOOTING.md](./REGISTRY_TROUBLESHOOTING.md) - General registry issues
- [ZAP_SECURITY_SCAN_GUIDE.md](./ZAP_SECURITY_SCAN_GUIDE.md) - Security scanning setup

---

**Last Updated:** 2026-05-01  
**Version:** 1.0