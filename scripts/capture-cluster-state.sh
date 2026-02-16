#!/bin/bash

set -e

# Trap Ctrl-C and exit immediately
trap 'echo -e "\n\033[0;31m[ERROR]\033[0m Capture aborted by user"; exit 130' INT

# Script to capture RHOAI cluster state before and after upgrade
# This script captures the state of various OpenShift resources related to RHOAI
# Usage: ./capture-cluster-state.sh [output-directory]
#   output-directory: Optional. Directory name where files will be saved (default: pre-post-cluster-state)

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

# Parse command-line arguments
OUTPUT_DIR="${1:-pre-post-cluster-state}"

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

# Script header
echo ""
log_info "========================================="
log_info "RHOAI Cluster State Capture Script"
log_info "========================================="
echo ""

# Create output directory
if [ ! -d "$OUTPUT_DIR" ]; then
    log_info "Creating directory: $OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
else
    log_info "Directory already exists: $OUTPUT_DIR"
fi

# Change to output directory
cd "$OUTPUT_DIR"
log_info "Saving cluster state to: $(pwd)"
echo ""

# Prompt for pre or post upgrade
while true; do
    read -p "Do you want to capture pre or post upgrade state? (pre/post): " CAPTURE_STAGE
    
    case "$CAPTURE_STAGE" in
        pre|PRE)
            CAPTURE_STAGE="pre"
            log_info "Selected pre-upgrade state capture"
            break
            ;;
        post|POST)
            CAPTURE_STAGE="post"
            log_info "Selected post-upgrade state capture"
            break
            ;;
        *)
            log_error "Invalid input. Please enter either 'pre' or 'post'"
            ;;
    esac
done

echo ""

# Branch based on stage selection
if [ "$CAPTURE_STAGE" = "pre" ]; then
    log_info "========================================="
    log_info "Starting Pre-Upgrade State Capture"
    log_info "========================================="
    echo ""
    
    log_info "Step 1: Capturing DataScienceCluster..."
    oc get datascienceclusters.datasciencecluster.opendatahub.io default-dsc -oyaml > pre-upgrade-dsc.yaml 2>/dev/null || true
    log_info "  ✓ Saved to pre-upgrade-dsc.yaml"
    
    log_info "Step 2: Capturing DataScienceClusterInitialization..."
    oc get dscinitializations.dscinitialization.opendatahub.io default-dsci -oyaml > pre-upgrade-dsci.yaml 2>/dev/null || true
    log_info "  ✓ Saved to pre-upgrade-dsci.yaml"
    
    log_info "Step 3: Capturing AcceleratorProfiles..."
    oc get acceleratorprofiles.dashboard.opendatahub.io -A -oyaml > pre-upgrade-aps.yaml 2>/dev/null || true
    log_info "  ✓ Saved to pre-upgrade-aps.yaml"
    
    log_info "Step 4: Capturing ServingRuntimes..."
    oc get servingruntimes.serving.kserve.io -A -oyaml > pre-upgrade-servingruntimes.yaml 2>/dev/null || true
    log_info "  ✓ Saved to pre-upgrade-servingruntimes.yaml"
    
    log_info "Step 5: Capturing InferenceServices..."
    oc get inferenceservices.serving.kserve.io -A -oyaml > pre-upgrade-isvcs.yaml 2>/dev/null || true
    log_info "  ✓ Saved to pre-upgrade-isvcs.yaml"
    
    log_info "Step 6: Capturing InferenceService Pods..."
    oc get pods -A -l serving.kserve.io/inferenceservice -oyaml > pre-upgrade-isvc-pods.yaml 2>/dev/null || true
    log_info "  ✓ Saved to pre-upgrade-isvc-pods.yaml"
    
    log_info "Step 7: Capturing InferenceService ReplicaSets..."
    oc get replicasets -A -l serving.kserve.io/inferenceservice -oyaml > pre-upgrade-isvc-replicasets.yaml 2>/dev/null || true
    log_info "  ✓ Saved to pre-upgrade-isvc-replicasets.yaml"
    
    log_info "Step 8: Capturing InferenceService Deployments..."
    oc get deployments -A -l serving.kserve.io/inferenceservice -oyaml > pre-upgrade-isvc-deployments.yaml 2>/dev/null || true
    log_info "  ✓ Saved to pre-upgrade-isvc-deployments.yaml"
    
    log_info "Step 9: Capturing Notebooks..."
    oc get notebooks -A -oyaml > pre-upgrade-notebooks.yaml 2>/dev/null || true
    log_info "  ✓ Saved to pre-upgrade-notebooks.yaml"
    
    log_info "Step 10: Capturing Notebook Pods..."
    oc get pods -A -l opendatahub.io/workbenches -oyaml > pre-upgrade-notebook-pods.yaml 2>/dev/null || true
    log_info "  ✓ Saved to pre-upgrade-notebook-pods.yaml"
    
    log_info "Step 11: Capturing Notebook StatefulSets..."
    oc get statefulsets -A -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,OWNER_KIND:.metadata.ownerReferences[0].kind" > pre-upgrade-notebook-statefulsets.yaml 2>/dev/null || true
    log_info "  ✓ Saved to pre-upgrade-notebook-statefulsets.yaml"
    
    echo ""
    log_info "========================================="
    log_info "Pre-Upgrade State Capture Completed"
    log_info "========================================="
    
elif [ "$CAPTURE_STAGE" = "post" ]; then
    log_info "========================================="
    log_info "Starting Post-Upgrade State Capture"
    log_info "========================================="
    echo ""
    
    log_info "Step 1: Capturing DataScienceCluster..."
    oc get datascienceclusters.datasciencecluster.opendatahub.io default-dsc -oyaml > post-upgrade-dsc.yaml 2>/dev/null || true
    log_info "  ✓ Saved to post-upgrade-dsc.yaml"
    
    log_info "Step 2: Capturing DataScienceClusterInitialization..."
    oc get dscinitializations.dscinitialization.opendatahub.io default-dsci -oyaml > post-upgrade-dsci.yaml 2>/dev/null || true
    log_info "  ✓ Saved to post-upgrade-dsci.yaml"
    
    log_info "Step 3: Capturing HardwareProfiles..."
    oc get hardwareprofiles.infrastructure.opendatahub.io -A -oyaml > post-upgrade-hwps.yaml 2>/dev/null || true
    log_info "  ✓ Saved to post-upgrade-hwps.yaml"
    
    log_info "Step 4: Capturing AcceleratorProfiles..."
    oc get acceleratorprofiles.dashboard.opendatahub.io -A -oyaml > post-upgrade-aps.yaml 2>/dev/null || true
    log_info "  ✓ Saved to post-upgrade-aps.yaml"
    
    log_info "Step 5: Capturing ServingRuntimes..."
    oc get servingruntimes.serving.kserve.io -A -oyaml > post-upgrade-servingruntimes.yaml 2>/dev/null || true
    log_info "  ✓ Saved to post-upgrade-servingruntimes.yaml"
    
    log_info "Step 6: Capturing InferenceServices..."
    oc get inferenceservices.serving.kserve.io -A -oyaml > post-upgrade-isvcs.yaml 2>/dev/null || true
    log_info "  ✓ Saved to post-upgrade-isvcs.yaml"
    
    log_info "Step 7: Capturing InferenceService Pods..."
    oc get pods -A -l serving.kserve.io/inferenceservice -oyaml > post-upgrade-isvc-pods.yaml 2>/dev/null || true
    log_info "  ✓ Saved to post-upgrade-isvc-pods.yaml"
    
    log_info "Step 8: Capturing InferenceService ReplicaSets..."
    oc get replicasets -A -l serving.kserve.io/inferenceservice -oyaml > post-upgrade-isvc-replicasets.yaml 2>/dev/null || true
    log_info "  ✓ Saved to post-upgrade-isvc-replicasets.yaml"
    
    log_info "Step 9: Capturing InferenceService Deployments..."
    oc get deployments -A -l serving.kserve.io/inferenceservice -oyaml > post-upgrade-isvc-deployments.yaml 2>/dev/null || true
    log_info "  ✓ Saved to post-upgrade-isvc-deployments.yaml"
    
    log_info "Step 10: Capturing Notebooks..."
    oc get notebooks -A -oyaml > post-upgrade-notebooks.yaml 2>/dev/null || true
    log_info "  ✓ Saved to post-upgrade-notebooks.yaml"
    
    log_info "Step 11: Capturing Notebook Pods..."
    oc get pods -A -l opendatahub.io/workbenches -oyaml > post-upgrade-notebook-pods.yaml 2>/dev/null || true
    log_info "  ✓ Saved to post-upgrade-notebook-pods.yaml"
    
    log_info "Step 12: Capturing Notebook StatefulSets..."
    oc get statefulsets -A -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,OWNER_KIND:.metadata.ownerReferences[0].kind" > post-upgrade-notebook-statefulsets.yaml 2>/dev/null || true
    log_info "  ✓ Saved to post-upgrade-notebook-statefulsets.yaml"
    
    echo ""
    log_info "========================================="
    log_info "Post-Upgrade State Capture Completed"
    log_info "========================================="
fi

echo ""
log_info "========================================="
log_info "Capture Summary"
log_info "========================================="
log_info "Capture stage: ${CAPTURE_STAGE}-upgrade"
log_info "Output directory: $(pwd)"
log_info "Cluster: $(oc whoami --show-server)"
log_info ""
log_info "Files saved:"
for file in ${CAPTURE_STAGE}-upgrade-*.yaml; do
    if [ -f "$file" ]; then
        log_info "  - $file"
    fi
done
log_info "========================================="
