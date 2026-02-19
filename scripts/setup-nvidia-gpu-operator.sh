#!/bin/bash

set -e

# Trap Ctrl-C and exit immediately
trap 'echo -e "\n\033[0;31m[ERROR]\033[0m Installation aborted by user"; exit 130' INT

# Script to set up NVIDIA GPU Operator on OpenShift cluster
# This script installs:
#   - Node Feature Discovery (NFD) Operator
#   - NVIDIA GPU Operator
#   - ClusterPolicy for GPU resource management
# Usage: ./setup-nvidia-gpu-operator.sh

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if oc is installed and user is logged in
if ! command -v oc &> /dev/null; then
    log_error "oc command not found. Please install the OpenShift CLI."
    exit 1
fi

if ! oc whoami &> /dev/null; then
    log_error "Not logged in to OpenShift cluster. Please run 'oc login' first."
    exit 1
fi

log_info "Logged in as: $(oc whoami)"
log_info "Current cluster: $(oc whoami --show-server)"

# Function to check for GPU nodes
check_gpu_nodes() {
    local gpu_capable_nodes=$(oc get nodes -o jsonpath='{.items[*].metadata.labels}' | grep -c 'g4dn\|p3\|p4\|a10\|v100\|t4' || echo "0")
    echo $gpu_capable_nodes
}

# Function to wait for CSV to be ready
wait_for_csv() {
    local namespace=$1
    local csv_pattern=$2
    local timeout=${3:-300}

    log_info "Waiting for CSV ${csv_pattern} to be ready in namespace ${namespace}..."

    local counter=0
    while [ $counter -lt $timeout ]; do
        local csv_status=$(oc get csv -n ${namespace} -o jsonpath='{.items[?(@.metadata.name~"'${csv_pattern}'")].status.phase}' 2>/dev/null || echo "")
        if [ "$csv_status" = "Succeeded" ]; then
            log_info "CSV ${csv_pattern} is ready"
            return 0
        fi
        sleep 5
        counter=$((counter + 5))
    done

    log_error "Timeout waiting for CSV ${csv_pattern} to be ready"
    return 1
}

# Function to wait for pods to be ready
wait_for_pods() {
    local namespace=$1
    local timeout=${2:-300}

    log_info "Waiting for pods in namespace ${namespace} to be ready..."

    oc wait --for=condition=Ready pod --all -n ${namespace} --timeout=${timeout}s || log_warn "Some pods may not be ready within timeout"
}

echo ""
log_warn "========================================="
log_warn "NVIDIA GPU Operator Installation Script"
log_warn "========================================="
log_warn "This script will install the following on your cluster:"
log_warn "  - Node Feature Discovery (NFD) Operator"
log_warn "  - NVIDIA GPU Operator"
log_warn "  - ClusterPolicy for GPU resource management"
log_warn ""
log_warn "Prerequisites:"
log_warn "  - At least one GPU node (g4dn.xlarge, p3.2xlarge, etc.)"
log_warn "  - Cluster-admin permissions"
log_warn "  - GPU node properly joined to the cluster"
log_warn ""
log_warn "This will create/modify:"
log_warn "  - Namespaces: openshift-nfd, nvidia-gpu-operator"
log_warn "  - OperatorGroups and Subscriptions for NFD and GPU operators"
log_warn "  - ClusterPolicy for GPU configuration"
log_warn ""
log_warn "Cluster: $(oc whoami --show-server)"
log_warn "User: $(oc whoami)"
log_warn "========================================="
echo ""

# Check for GPU nodes
log_info "Checking for GPU-capable nodes..."
GPU_NODE_COUNT=$(check_gpu_nodes)

if [ "$GPU_NODE_COUNT" -eq 0 ]; then
    log_warn "Warning: No obvious GPU-capable nodes detected based on instance type labels"
    log_info "Available nodes:"
    oc get nodes -o custom-columns="NAME:.metadata.name,INSTANCE-TYPE:.metadata.labels.node\.kubernetes\.io/instance-type" --no-headers
    echo ""
    log_warn "You may still proceed if you have GPU nodes that aren't detected by this check"
fi

while true; do
    read -p "Do you want to proceed with the installation? (y/n): " CONFIRM

    case "$CONFIRM" in
        y|Y|yes|Yes|YES)
            log_info "Proceeding with installation..."
            break
            ;;
        n|N|no|No|NO)
            log_info "Installation cancelled by user"
            exit 0
            ;;
        *)
            log_error "Invalid input. Please enter 'y' or 'n'"
            ;;
    esac
done

echo ""

# Phase 1: Install Node Feature Discovery (NFD) Operator
log_info "========================================="
log_info "Phase 1: Installing Node Feature Discovery (NFD) Operator"
log_info "========================================="

# Step 1: Create NFD namespace
log_info "Step 1: Creating namespace: openshift-nfd"
if oc get namespace openshift-nfd &> /dev/null; then
    log_warn "Namespace openshift-nfd already exists, skipping creation"
else
    oc create namespace openshift-nfd
    log_info "Namespace openshift-nfd created successfully"
fi

# Step 2: Create NFD OperatorGroup
log_info "Step 2: Creating OperatorGroup for NFD..."

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-nfd-operatorgroup
  namespace: openshift-nfd
spec:
  targetNamespaces:
  - openshift-nfd
EOF

log_info "NFD OperatorGroup created successfully"

# Step 3: Create NFD Subscription
log_info "Step 3: Creating Subscription for NFD operator..."

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: nfd-subscription
  namespace: openshift-nfd
spec:
  channel: stable
  installPlanApproval: Automatic
  name: nfd
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

log_info "NFD Subscription created successfully"

# Step 4: Wait for NFD operator to be ready
wait_for_csv "openshift-nfd" "nfd"

# Step 5: Create NFD Instance
log_info "Step 5: Creating NFD Instance..."

cat <<EOF | oc apply -f -
apiVersion: nfd.openshift.io/v1
kind: NodeFeatureDiscovery
metadata:
  name: nfd-instance
  namespace: openshift-nfd
spec:
  instance: ""
EOF

log_info "NFD Instance created successfully"

# Wait for NFD pods to be ready
wait_for_pods "openshift-nfd" 180

log_info "Phase 1 completed: NFD operator is ready"

# Phase 2: Install NVIDIA GPU Operator
log_info ""
log_info "========================================="
log_info "Phase 2: Installing NVIDIA GPU Operator"
log_info "========================================="

# Step 1: Create GPU operator namespace
log_info "Step 1: Creating namespace: nvidia-gpu-operator"
if oc get namespace nvidia-gpu-operator &> /dev/null; then
    log_warn "Namespace nvidia-gpu-operator already exists, skipping creation"
else
    oc create namespace nvidia-gpu-operator
    log_info "Namespace nvidia-gpu-operator created successfully"
fi

# Step 2: Create GPU Operator OperatorGroup
log_info "Step 2: Creating OperatorGroup for NVIDIA GPU Operator..."

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: nvidia-gpu-operator-group
  namespace: nvidia-gpu-operator
spec:
  targetNamespaces:
  - nvidia-gpu-operator
EOF

log_info "GPU Operator OperatorGroup created successfully"

# Step 3: Create GPU Operator Subscription
log_info "Step 3: Creating Subscription for NVIDIA GPU Operator..."

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: nvidia-gpu-operator-subscription
  namespace: nvidia-gpu-operator
spec:
  channel: stable
  installPlanApproval: Automatic
  name: gpu-operator-certified
  source: certified-operators
  sourceNamespace: openshift-marketplace
EOF

log_info "GPU Operator Subscription created successfully"

# Step 4: Wait for GPU operator to be ready
wait_for_csv "nvidia-gpu-operator" "gpu-operator-certified"

log_info "Phase 2 completed: NVIDIA GPU operator is ready"

# Phase 3: Create ClusterPolicy
log_info ""
log_info "========================================="
log_info "Phase 3: Creating GPU ClusterPolicy"
log_info "========================================="

log_info "Creating ClusterPolicy for GPU resource management..."

cat <<EOF | oc apply -f -
apiVersion: nvidia.com/v1
kind: ClusterPolicy
metadata:
  name: gpu-cluster-policy
spec:
  operator:
    defaultRuntime: crio
    use_ocp_driver_toolkit: true
  daemonsets:
    updateStrategy: RollingUpdate
    rollingUpdate:
      maxUnavailable: "1"
  driver:
    enabled: true
    useNvidiaDriverCRD: false
  toolkit:
    enabled: true
  devicePlugin:
    enabled: true
  dcgm:
    enabled: true
  dcgmExporter:
    enabled: true
  gfd:
    enabled: true
  migManager:
    enabled: true
  nodeStatusExporter:
    enabled: true
  gds:
    enabled: false
  vgpuManager:
    enabled: false
  vgpuDeviceManager:
    enabled: false
  cdi:
    enabled: true
  sandboxWorkloads:
    enabled: false
    defaultWorkload: container
EOF

log_info "ClusterPolicy created successfully"

log_info "Phase 3 completed: ClusterPolicy created"

# Phase 4: Monitor deployment and verification
log_info ""
log_info "========================================="
log_info "Phase 4: Monitoring GPU Operator Deployment"
log_info "========================================="

log_info "Waiting for GPU operator components to deploy (this may take 10-15 minutes)..."
log_warn "Driver compilation and container runtime setup can take time..."

# Wait for ClusterPolicy to show ready status (with extended timeout)
log_info "Monitoring ClusterPolicy status..."
TIMEOUT=900  # 15 minutes
COUNTER=0

while [ $COUNTER -lt $TIMEOUT ]; do
    CLUSTER_POLICY_STATE=$(oc get clusterpolicy gpu-cluster-policy -o jsonpath='{.status.state}' 2>/dev/null || echo "NotReady")

    case "$CLUSTER_POLICY_STATE" in
        "ready"|"Ready"|"READY")
            log_info "✓ ClusterPolicy is Ready!"
            break
            ;;
        "")
            log_info "⏳ ClusterPolicy status not yet available..."
            ;;
        *)
            log_info "⏳ ClusterPolicy state: ${CLUSTER_POLICY_STATE}"
            ;;
    esac

    sleep 30
    COUNTER=$((COUNTER + 30))
done

if [ $COUNTER -ge $TIMEOUT ]; then
    log_warn "ClusterPolicy did not reach Ready state within timeout, but installation may still be proceeding"
fi

# Phase 5: Verification
log_info ""
log_info "========================================="
log_info "Phase 5: Verification"
log_info "========================================="

# Check GPU resources
log_info "Checking GPU resource availability..."
GPU_RESOURCES=$(oc get nodes -o custom-columns="NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu" --no-headers | grep -v "<none>" | wc -l)

if [ "$GPU_RESOURCES" -gt 0 ]; then
    log_info "✓ GPU resources are available on ${GPU_RESOURCES} node(s):"
    oc get nodes -o custom-columns="NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu" --no-headers | grep -v "<none>"
else
    log_warn "⚠ No GPU resources detected yet. Driver installation may still be in progress."
fi

echo ""

# Check GPU operator pod status
log_info "GPU Operator component status:"
oc get pods -n nvidia-gpu-operator --no-headers | while read pod_info; do
    pod_name=$(echo $pod_info | awk '{print $1}')
    pod_status=$(echo $pod_info | awk '{print $3}')

    case "$pod_status" in
        "Running"|"Completed")
            log_info "✓ $pod_name: $pod_status"
            ;;
        "Pending"|"ContainerCreating"|"Init:0/1")
            log_warn "⏳ $pod_name: $pod_status (still deploying)"
            ;;
        *)
            log_error "✗ $pod_name: $pod_status"
            ;;
    esac
done

# Final status summary
echo ""
log_info "========================================="
log_info "NVIDIA GPU Operator Installation Summary"
log_info "========================================="

# Check overall status
NFD_STATUS=$(oc get csv -n openshift-nfd -o jsonpath='{.items[?(@.metadata.name~"nfd")].status.phase}' 2>/dev/null || echo "Unknown")
GPU_STATUS=$(oc get csv -n nvidia-gpu-operator -o jsonpath='{.items[?(@.metadata.name~"gpu-operator-certified")].status.phase}' 2>/dev/null || echo "Unknown")
POLICY_STATE=$(oc get clusterpolicy gpu-cluster-policy -o jsonpath='{.status.state}' 2>/dev/null || echo "Unknown")

log_info "Installation Status:"
log_info "  - NFD Operator: ${NFD_STATUS}"
log_info "  - GPU Operator: ${GPU_STATUS}"
log_info "  - ClusterPolicy: ${POLICY_STATE}"
log_info ""

if [ "$NFD_STATUS" = "Succeeded" ] && [ "$GPU_STATUS" = "Succeeded" ]; then
    log_info "✓ Operators installed successfully"
else
    log_warn "⚠ Some operators may not be fully ready yet"
fi

if [ "$GPU_RESOURCES" -gt 0 ]; then
    log_info "✓ GPU resources are available for scheduling"

    echo ""
    log_info "Next steps:"
    log_info "  - GPU nodes should be ready for workloads requiring nvidia.com/gpu resources"
    log_info "  - Monitor GPU operator pods: oc get pods -n nvidia-gpu-operator"
    log_info "  - Test GPU scheduling with workloads that request nvidia.com/gpu resources"
else
    log_warn "⚠ GPU resources not yet available"
    echo ""
    log_info "Troubleshooting steps:"
    log_info "  - Check GPU operator pods: oc get pods -n nvidia-gpu-operator"
    log_info "  - Check driver compilation: oc logs -n nvidia-gpu-operator -l app=nvidia-driver-daemonset"
    log_info "  - Verify GPU nodes have proper labels: oc get nodes --show-labels | grep nvidia"
    log_info "  - Driver installation can take 10-15 minutes depending on node resources"
fi

echo ""
log_info "========================================="