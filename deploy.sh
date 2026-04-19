#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$SCRIPT_DIR/k8s"
APP_DIR="$SCRIPT_DIR/app"


# 1. Build Docker image
echo "Building Docker image custom-app:latest"
docker build -t custom-app:latest "$APP_DIR"

# 2. ConfigMap
echo "Applying ConfigMap:"
kubectl apply -f "$K8S_DIR/configmap.yaml"

# 3. Initial test Pod
echo "Deploying initial test Pod:"
kubectl apply -f "$K8S_DIR/pod.yaml"
echo "Waiting for pod/custom-app-pod to be Ready..."
kubectl wait --for=condition=Ready pod/custom-app-pod --timeout=90s

# 4. Deployment
echo "Deploying Deployment with 3 replicas:"
kubectl apply -f "$K8S_DIR/deployment.yaml"
echo "Waiting for rollout:"
kubectl rollout status deployment/custom-app --timeout=120s

# 5. Service
echo "Service:"
kubectl apply -f "$K8S_DIR/service.yaml"

# 6. DaemonSet log-agent
echo "DaemonSet log-agent:"
kubectl apply -f "$K8S_DIR/daemonset.yaml"
echo "Waiting for DaemonSet to be available:"
kubectl rollout status daemonset/log-agent --timeout=120s

# 7. StatefulSet 
echo "Deploying StatefulSet:"
kubectl apply -f "$K8S_DIR/statefulset.yaml"
echo "Waiting for StatefulSet rollout:"
kubectl rollout status statefulset/custom-app-stateful --timeout=120s

# 8. CronJob
echo "CronJob log-archiver:"
kubectl apply -f "$K8S_DIR/cronjob.yaml"

# 9. Istio service mesh
echo "Installing Istio (profile: demo)..."
if ! command -v istioctl &>/dev/null; then
    curl -L https://istio.io/downloadIstio | sh -
    ISTIO_DIR=$(ls -d istio-* 2>/dev/null | head -1)
    export PATH="$PWD/$ISTIO_DIR/bin:$PATH"
fi
istioctl install --set profile=demo -y

echo "Enabling sidecar injection for namespace default..."
kubectl label namespace default istio-injection=enabled --overwrite

echo "Restarting workloads to inject sidecars..."
kubectl rollout restart deployment/custom-app
kubectl rollout restart daemonset/log-agent
kubectl rollout status deployment/custom-app --timeout=120s

echo "Applying Istio Gateway..."
kubectl apply -f "$K8S_DIR/istio-gateway.yaml"

echo "Applying VirtualService..."
kubectl apply -f "$K8S_DIR/istio-virtualservice.yaml"

echo "Applying DestinationRule..."
kubectl apply -f "$K8S_DIR/istio-destinationrule.yaml"
