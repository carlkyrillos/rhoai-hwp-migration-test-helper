#!/bin/bash

set -e

# Trap Ctrl-C and exit immediately
trap 'echo -e "\n\033[0;31m[ERROR]\033[0m Installation aborted by user"; exit 130' INT

# Script to set up RHOAI 2.25 and prerequisite operators on OpenShift cluster
# This script installs:
#   - Red Hat Authorino Operator v1.2.4
#   - Red Hat OpenShift Serverless v1.37.1
#   - Red Hat OpenShift Service Mesh v2.6.13-0
#   - Red Hat OpenShift AI v2.25.1
# Usage: ./setup-rhoai-2.25.sh [CATALOG_SOURCE_IMAGE]

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

echo ""
log_warn "========================================="
log_warn "RHOAI 2.25.1 Installation Script"
log_warn "========================================="
log_warn "This script will install the following on your cluster:"
log_warn "  - Red Hat Authorino Operator (stable channel)"
log_warn "  - Red Hat OpenShift Serverless (stable channel)"
log_warn "  - Red Hat OpenShift Service Mesh (stable channel)"
log_warn "  - Red Hat OpenShift AI 2.25.1 (stable-2.25 channel)"
log_warn "  - DataScienceCluster with dashboard, kserve, and workbenches"
log_warn ""
log_warn "This will create/modify:"
log_warn "  - CatalogSource in openshift-marketplace"
log_warn "  - Operator subscriptions and installations"
log_warn "  - Namespaces: openshift-serverless, redhat-ods-operator"
log_warn "  - OperatorGroups in custom namespaces"
log_warn ""
log_warn "Cluster: $(oc whoami --show-server)"
log_warn "User: $(oc whoami)"
log_warn "========================================="
echo ""

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

# Detect OpenShift version
log_info "Detecting OpenShift version..."
OCP_VERSION=$(oc version -o json | jq -r '.openshiftVersion // .serverVersion.gitVersion' | sed 's/^v//' | cut -d. -f1,2)

if [ -z "$OCP_VERSION" ]; then
    log_error "Failed to detect OpenShift version"
    exit 1
fi

log_info "Detected OpenShift version: ${OCP_VERSION}"

# Set default catalog source image based on OpenShift version
case "$OCP_VERSION" in
    4.19)
        DEFAULT_IMAGE="quay.io/rhoai/rhoai-fbc-fragment:ocp-4.19-rhoai-3.3-216738f4c869a8178a8306d11a76b320e066317b@sha256:f3c94a10198ce8b3a6398757f30a91c60dfb2687ba27bb731c8c0f4ba7b1cba0"
        ;;
    4.20)
        DEFAULT_IMAGE="quay.io/rhoai/rhoai-fbc-fragment:ocp-4.20-rhoai-3.3-216738f4c869a8178a8306d11a76b320e066317b@sha256:266c877bd737d313c8624579bbc4b5759d8177eeb57b4684caba67fc7b05ea54"
        ;;
    4.21)
        DEFAULT_IMAGE="quay.io/rhoai/rhoai-fbc-fragment:ocp-4.21-rhoai-3.3-216738f4c869a8178a8306d11a76b320e066317b@sha256:2a546c18e5310971409b55865d3bcb3f369651abe3af9a6f291f4ad0f8e9a5cf"
        ;;
    *)
        log_warn "Unknown OpenShift version: ${OCP_VERSION}. Using default for 4.20"
        DEFAULT_IMAGE="quay.io/rhoai/rhoai-fbc-fragment:ocp-4.20-rhoai-3.3-216738f4c869a8178a8306d11a76b320e066317b@sha256:266c877bd737d313c8624579bbc4b5759d8177eeb57b4684caba67fc7b05ea54"
        ;;
esac

# Use provided image or default
CATALOG_IMAGE="${1:-$DEFAULT_IMAGE}"
log_info "Using catalog source image: ${CATALOG_IMAGE}"

# Create operator namespace
log_info "Creating namespace: redhat-ods-operator"
if oc get namespace redhat-ods-operator &> /dev/null; then
    log_warn "Namespace redhat-ods-operator already exists, skipping creation"
else
    oc create namespace redhat-ods-operator
    log_info "Namespace redhat-ods-operator created successfully"
fi

# Create CatalogSource
log_info "Creating CatalogSource: rhoai-catalog-dev"

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: rhoai-catalog-dev
  namespace: openshift-marketplace
spec:
  displayName: Red Hat OpenShift AI
  grpcPodConfig:
    securityContextConfig: restricted
  image: '${CATALOG_IMAGE}'
  publisher: RHOAI Development Catalog
  sourceType: grpc
EOF

log_info "CatalogSource created successfully"

# Wait for CatalogSource to be ready
log_info "Waiting for CatalogSource rhoai-catalog-dev to be READY..."
oc wait --for=jsonpath='{.status.connectionState.lastObservedState}'=READY \
    catalogsource/rhoai-catalog-dev \
    -n openshift-marketplace \
    --timeout=300s

log_info "CatalogSource rhoai-catalog-dev is READY"

log_info "========================================="
log_info "Installing prerequisite operators..."
log_info "========================================="

# Install Red Hat Authorino Operator
log_info "Installing Red Hat Authorino Operator..."

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: authorino-operator
  namespace: openshift-operators
spec:
  channel: stable
  installPlanApproval: Automatic
  name: authorino-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

log_info "Authorino Operator subscription created"

# Create namespace for OpenShift Serverless
log_info "Creating namespace: openshift-serverless"
if oc get namespace openshift-serverless &> /dev/null; then
    log_warn "Namespace openshift-serverless already exists, skipping creation"
else
    oc create namespace openshift-serverless
    log_info "Namespace openshift-serverless created successfully"
fi

# Check if OperatorGroup already exists for OpenShift Serverless
EXISTING_OG=$(oc get operatorgroup -n openshift-serverless -o name 2>/dev/null | wc -l)
if [ "$EXISTING_OG" -eq 0 ]; then
    log_info "Creating OperatorGroup in openshift-serverless namespace"
    
    cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-serverless
  namespace: openshift-serverless
spec:
  upgradeStrategy: Default
EOF
    
    log_info "OperatorGroup created successfully"
else
    log_info "OperatorGroup already exists in openshift-serverless namespace, skipping creation"
fi

# Install Red Hat OpenShift Serverless
log_info "Installing Red Hat OpenShift Serverless..."

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: serverless-operator
  namespace: openshift-serverless
spec:
  channel: stable
  installPlanApproval: Automatic
  name: serverless-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

log_info "OpenShift Serverless subscription created"

# Install Red Hat OpenShift Service Mesh 2
log_info "Installing Red Hat OpenShift Service Mesh..."

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: servicemeshoperator
  namespace: openshift-operators
spec:
  channel: stable
  installPlanApproval: Automatic
  name: servicemeshoperator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

log_info "OpenShift Service Mesh subscription created"

log_info "========================================="
log_info "Prerequisite operators installation initiated"
log_info "========================================="
log_info ""

# Check if OperatorGroup already exists for RHOAI
EXISTING_OG=$(oc get operatorgroup -n redhat-ods-operator -o name 2>/dev/null | wc -l)
if [ "$EXISTING_OG" -eq 0 ]; then
    log_info "Creating OperatorGroup in redhat-ods-operator namespace"
    
    cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: redhat-ods-operator
  namespace: redhat-ods-operator
spec:
  upgradeStrategy: Default
EOF
    
    log_info "OperatorGroup created successfully"
else
    log_info "OperatorGroup already exists in redhat-ods-operator namespace, skipping creation"
fi

# Create Subscription to install RHOAI operator
log_info "Creating Subscription for RHOAI operator"

cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhods-operator
  namespace: redhat-ods-operator
spec:
  channel: stable-2.25
  installPlanApproval: Automatic
  name: rhods-operator
  source: rhoai-catalog-dev
  sourceNamespace: openshift-marketplace
EOF

log_info "Subscription created successfully"

# Wait for RHOAI operator installation to complete
log_info "========================================="
log_info "Waiting for RHOAI operator installation..."
log_info "========================================="

log_info "Step 1/4: Waiting for InstallPlan to be created..."
oc wait --for=condition=InstallPlanPending=true subscription/rhods-operator -n redhat-ods-operator --timeout=300s

log_info "Step 2/4: Getting InstallPlan name..."
INSTALL_PLAN=$(oc get subscription rhods-operator -n redhat-ods-operator -o jsonpath='{.status.installplan.name}')
log_info "InstallPlan: ${INSTALL_PLAN}"

log_info "Step 3/4: Waiting for InstallPlan to be installed..."
oc wait --for=condition=Installed=true installplan/${INSTALL_PLAN} -n redhat-ods-operator --timeout=300s

log_info "Step 4/4: Waiting for rhods-operator deployment to be available..."
oc wait --for=condition=Available=true deployment/rhods-operator -n redhat-ods-operator --timeout=300s

log_info "RHOAI operator is ready!"

# Create DSCInitialization
log_info "========================================="
log_info "Creating DSCInitialization..."
log_info "========================================="

cat <<EOF | oc apply -f -
apiVersion: dscinitialization.opendatahub.io/v1
kind: DSCInitialization
metadata:
  labels:
    app.kubernetes.io/name: dscinitialization
    app.kubernetes.io/instance: default-dsci
    app.kubernetes.io/part-of: rhods-operator
    app.kubernetes.io/managed-by: kustomize
    app.kubernetes.io/created-by: rhods-operator
  name: default-dsci
spec:
  monitoring:
    managementState: Managed
    namespace: redhat-ods-monitoring
  applicationsNamespace: redhat-ods-applications
  serviceMesh:
    controlPlane:
      metricsCollection: Istio
      name: data-science-smcp
      namespace: istio-system
    managementState: Managed
  trustedCABundle:
    managementState: Managed
    customCABundle: ""
EOF

log_info "DSCInitialization created successfully"

# Wait for DSCI to be ready
log_info "Waiting for DSCInitialization to be ready..."
oc wait --for=jsonpath='{.status.phase}'=Ready \
    dscinitialization/default-dsci \
    --timeout=300s || log_warn "DSCInitialization did not reach Ready state within timeout"

DSCI_PHASE=$(oc get dscinitialization default-dsci -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
log_info "DSCInitialization phase: ${DSCI_PHASE}"

# Create DataScienceCluster
log_info "========================================="
log_info "Creating DataScienceCluster..."
log_info "========================================="

cat <<EOF | oc apply -f -
kind: DataScienceCluster
apiVersion: datasciencecluster.opendatahub.io/v1
metadata:
  labels:
    app.kubernetes.io/created-by: rhods-operator
    app.kubernetes.io/instance: default-dsc
    app.kubernetes.io/managed-by: kustomize
    app.kubernetes.io/name: datasciencecluster
    app.kubernetes.io/part-of: rhods-operator
  name: default-dsc
spec:
  components:
    dashboard:
      managementState: Managed
    kserve:
      managementState: Managed
      nim:
        managementState: Managed
      serving:
        ingressGateway:
          certificate:
            type: OpenshiftDefaultIngress
        managementState: Managed
        name: knative-serving
    workbenches:
      managementState: Managed
EOF

log_info "DataScienceCluster created successfully"

# Wait for DSC to be ready
log_info "Waiting for DataScienceCluster to be ready (this may take several minutes)..."
oc wait --for=jsonpath='{.status.phase}'=Ready \
    datasciencecluster/default-dsc \
    --timeout=1200s || log_warn "DataScienceCluster did not reach Ready state within timeout"

DSC_PHASE=$(oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
if [ "$DSC_PHASE" = "Ready" ]; then
    log_info "DataScienceCluster is Ready!"
else
    log_warn "Current DSC phase: ${DSC_PHASE}"
fi

log_info "========================================="
log_info "RHOAI 2.25.1 setup completed successfully!"
log_info "========================================="
log_info ""
log_info "Installed Operators:"
log_info "  - Red Hat Authorino Operator (openshift-operators)"
log_info "  - Red Hat OpenShift Serverless (openshift-serverless)"
log_info "  - Red Hat OpenShift Service Mesh (openshift-operators)"
log_info "  - Red Hat OpenShift AI (redhat-ods-operator)"
log_info ""
log_info "RHOAI Configuration:"
log_info "  - DSCInitialization: default-dsci (Phase: ${DSCI_PHASE})"
log_info "  - DataScienceCluster: default-dsc (Phase: ${DSC_PHASE})"

# Run hardware profiles ignorelist configuration
log_info ""
log_info "========================================="
log_info "Configuring hardware profiles ignorelist..."
log_info "========================================="

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARDWAREPROFILES_SCRIPT="${SCRIPT_DIR}/hardwareprofiles-ignorelist.sh"

if [ -f "$HARDWAREPROFILES_SCRIPT" ]; then
    if bash "$HARDWAREPROFILES_SCRIPT" -n redhat-ods-applications; then
        log_info "Hardware profiles ignorelist configured successfully"
    else
        log_warn "Hardware profiles ignorelist configuration failed or was skipped"
    fi
else
    log_warn "Hardware profiles ignorelist script not found at: ${HARDWAREPROFILES_SCRIPT}"
    log_warn "Skipping hardware profiles configuration"
fi
