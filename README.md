# IBM AIOps Demo Environment

Integrated demo for **Instana**, **Turbonomic**, **IBM Concert**, and **Granite AI** on Kubernetes.

## Architecture

```
Mac (Claude Code / Bob)  ──git push──>  GitHub
         │                                  │
    docker context                   self-hosted runner
         │                                  │
         v                                  v
   Linux Build Host  ──docker push──>  Docker Hub (mbx1010)
                                            │
                                            v
                                    K8s Cluster (192.168.178.35)
                                            │
                              ┌─────────────┼─────────────┐
                              v             v             v
                          Instana     Turbonomic     Concert
```

## Quick Start

```bash
# Build on Linux, push to Docker Hub, deploy to K8s
make all

# Just build
make build

# Apply Concert patches + full pipeline
make patch-build

# Check status
make status
```

## Repository Structure

```
├── .gitea/workflows/           # Gitea Actions CI/CD with SAST & SBOM
├── python-app/                 # Load Test App (Python 3.9 / Flask)
│   ├── Dockerfile
│   ├── app.py
│   └── requirements.txt
├── java-app/                   # Vulnerable Echo Service (Java 11 / Log4j)
│   ├── Dockerfile
│   ├── pom.xml
│   └── src/
├── k8s/                        # Kubernetes manifests (split by resource)
│   ├── namespace.yaml
│   ├── configmaps.yaml
│   ├── python-app-deployment.yaml
│   ├── echo-service-deployment.yaml
│   ├── ingress.yaml
│   └── hpa.yaml
├── scripts/                    # Deployment & patch scripts
│   ├── deploy.sh
│   ├── apply-concert-patch.sh
│   └── diagnose-sbom.sh            # SBOM troubleshooting tool
├── concert-patches/            # IBM Concert remediation patches
├── docs/                       # Documentation
│   ├── CONCERT_INTEGRATION.md      # Concert SAST & SBOM setup
│   ├── CONCERT_SECRETS_SETUP.md    # Quick secrets configuration
│   ├── SBOM_TROUBLESHOOTING.md     # SBOM upload troubleshooting
│   └── GITEA_DEPLOYMENT_GUIDE.md   # Gitea CI/CD setup
├── Makefile                    # Build + push + deploy shortcuts
└── README.md
```

## Setup

### 1. Remote Docker Context (Mac to Linux)

```bash
docker context create linux-builder \
  --docker "host=ssh://manfred@linux"
docker context use linux-builder
```

### 2. Docker Hub Login (on Linux)

```bash
ssh linux
docker login -u mbx1010
```

### 3. Self-Hosted GitHub Runner (on Linux)

See [GitHub Actions runner setup](https://docs.github.com/en/actions/hosting-your-own-runners).
Add `DOCKERHUB_TOKEN` as a repository secret.

### 4. Kubeconfig

```bash
scp root@192.168.178.35:/etc/kubernetes/admin.conf ~/.kube/config
```

## Applications

| App | Port | Image | Purpose |
|-----|------|-------|---------|
| Load Test App | 8080 | `mbx1010/load-test-app` | CPU/memory stress, echo flood, ramp & wave patterns |
| Echo Service | 8085 | `mbx1010/vulnerable-echo-service` | Intentionally vulnerable (Log4j CVE-2021-44228) |

## IBM Product Integration

- **Instana** — traces, metrics, AI Actions (local Granite on vLLM + NVIDIA GPU)
- **Turbonomic** — resize/scale actions triggered by load patterns
- **Concert** — SAST scanning (Semgrep), SBOM generation (Syft), CVE detection, remediation patches
- **MCP Servers** — Instana + Kubernetes MCP connected to Claude & watsonx

## Security Scanning & SBOM

The CI/CD pipeline automatically performs:

### 🔍 SAST Scanning with Semgrep
- Runs on every commit after checkout
- Scans both Java and Python applications
- Detects security vulnerabilities in source code
- Uploads results to IBM Concert in SARIF format

### 📦 SBOM Generation with Syft
- Generates Software Bill of Materials for all container images
- Creates both SPDX and CycloneDX formats
- Uploads to IBM Concert for vulnerability tracking
- Stored as artifacts for compliance

### 📊 Concert Integration
All security data is uploaded to the `demo-turbo-instana-concert` application in IBM Concert:
- **SAST Results**: Security vulnerabilities from code analysis
- **SBOM Data**: Complete dependency inventory with versions
- **CVE Tracking**: Known vulnerabilities in dependencies

**Setup Guide**: See [docs/CONCERT_INTEGRATION.md](docs/CONCERT_INTEGRATION.md) for detailed configuration.

**Quick Start**: See [docs/CONCERT_SECRETS_SETUP.md](docs/CONCERT_SECRETS_SETUP.md) for secrets configuration.

**Troubleshooting**: See [docs/SBOM_TROUBLESHOOTING.md](docs/SBOM_TROUBLESHOOTING.md) if SBOM upload fails.

### Troubleshooting SBOM Upload

If you see "No SBOM files found" in the workflow logs:

```bash
# Run the diagnostic tool
bash scripts/diagnose-sbom.sh

# Or manually check:
# 1. Verify Docker images exist
docker images | grep echo-service
docker images | grep load-test-app

# 2. Test SBOM generation manually
syft <image>:latest -o cyclonedx-json=/tmp/test-sbom.json

# 3. Check Concert connectivity
curl -X GET "${CONCERT_URL}/core/api/v1/applications" \
  -H "C_API_KEY: ${CONCERT_API_KEY}" \
  -H "InstanceID: ${CONCERT_INSTANCE_ID}"
```

For detailed troubleshooting steps, see [docs/SBOM_TROUBLESHOOTING.md](docs/SBOM_TROUBLESHOOTING.md).

### Required Secrets (Gitea)
```bash
CONCERT_URL              # IBM Concert instance URL
CONCERT_API_KEY          # Concert API authentication key
CONCERT_INSTANCE_ID      # Concert instance identifier
```
