#!/bin/bash

set -e

# Trap Ctrl-C and exit immediately
trap 'echo -e "\n\033[0;31m[ERROR]\033[0m Installation aborted by user"; exit 130' INT

# Script to clean up RHOAI installation from OpenShift cluster
# This script can uninstall:
#   - RHOAI 2.x (including prerequisite operators)
#   - RHOAI 3.x (including prerequisite operators)
# Usage: ./cleanup-rhoai.sh

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

# Prompt for RHOAI version to clean up
echo ""
log_info "========================================="
log_info "RHOAI Cleanup Script"
log_info "========================================="
echo ""

while true; do
    read -p "Which version of RHOAI do you want to clean up? (2.x/3.x): " RHOAI_VERSION
    
    case "$RHOAI_VERSION" in
        2.x|2.X|2)
            RHOAI_VERSION="2.x"
            log_info "Selected RHOAI 2.x for cleanup"
            break
            ;;
        3.x|3.X|3)
            RHOAI_VERSION="3.x"
            log_info "Selected RHOAI 3.x for cleanup"
            break
            ;;
        *)
            log_error "Invalid input. Please enter either '2.x' or '3.x'"
            ;;
    esac
done

echo ""
log_warn "========================================="
log_warn "WARNING: DESTRUCTIVE OPERATION"
log_warn "========================================="
log_warn "You are about to tear down RHOAI ${RHOAI_VERSION} installation"
log_warn "This will remove:"
log_warn "  - RHOAI operator and all its resources"
log_warn "  - DataScienceCluster (if exists)"
log_warn "  - Prerequisite operators (Authorino, Serverless, Service Mesh)"
log_warn "  - Associated namespaces and configurations"
log_warn "  - CatalogSources"
log_warn ""
log_warn "Cluster: $(oc whoami --show-server)"
log_warn "User: $(oc whoami)"
log_warn "========================================="
echo ""

while true; do
    read -p "Do you want to proceed with the cleanup? (y/n): " CONFIRM
    
    case "$CONFIRM" in
        y|Y|yes|Yes|YES)
            log_info "Proceeding with cleanup..."
            break
            ;;
        n|N|no|No|NO)
            log_info "Cleanup cancelled by user"
            exit 0
            ;;
        *)
            log_error "Invalid input. Please enter 'y' or 'n'"
            ;;
    esac
done

echo ""

# Branch based on version selection
if [ "$RHOAI_VERSION" = "2.x" ]; then
    log_info "========================================="
    log_info "Starting RHOAI 2.x cleanup"
    log_info "========================================="
    
    # Step 1 - Delete RHOAI custom resources
    log_info "Step 1: Deleting RHOAI custom resources..."
    
    log_info "  - Deleting InferenceServices..."
    oc delete inferenceservices.serving.kserve.io --all -A || log_warn "No InferenceServices found or deletion timed out"
    
    log_info "  - Deleting ServingRuntimes..."
    oc delete servingruntimes.serving.kserve.io --all -A || log_warn "No ServingRuntimes found or deletion timed out"
    
    log_info "  - Deleting Notebooks..."
    oc delete notebooks.kubeflow.org --all -A || log_warn "No Notebooks found or deletion timed out"
    
    log_info "  - Deleting HardwareProfiles..."
    oc delete hardwareprofiles.infrastructure.opendatahub.io --all -A || log_warn "No HardwareProfiles found or deletion timed out"
    
    log_info "  - Deleting AcceleratorProfiles..."
    oc delete acceleratorprofiles.dashboard.opendatahub.io --all -A || log_warn "No AcceleratorProfiles found or deletion timed out"
    
    log_info "Custom resources deleted"
    
    # Step 2 - Delete DataScienceCluster and DataScienceClusterInitialization
    log_info "Step 2: Deleting DataScienceCluster and DataScienceClusterInitialization..."
    
    if oc get datascienceclusters.datasciencecluster.opendatahub.io default-dsc &> /dev/null; then
        log_info "  - Deleting DataScienceCluster: default-dsc"
        oc delete datascienceclusters.datasciencecluster.opendatahub.io default-dsc --timeout=300s || log_warn "DataScienceCluster deletion timed out"
    else
        log_warn "  - DataScienceCluster default-dsc not found"
    fi
    
    # Delete DSCI
    DSCI=$(oc get dscinitializations.dscinitialization.opendatahub.io -o name 2>/dev/null || true)
    if [ -n "$DSCI" ]; then
        log_info "  - Deleting DataScienceClusterInitialization..."
        oc delete dscinitializations.dscinitialization.opendatahub.io default-dsci --timeout=300s || log_warn "DSCI deletion timed out"
    else
        log_warn "  - No DataScienceClusterInitialization found"
    fi
    
    log_info "DataScienceCluster and DSCI deleted"
    
    # Wait for DSC and DSCI to be fully removed
    log_info "Waiting for DataScienceCluster and DSCI to be fully deleted..."
    oc wait --for=delete datasciencecluster --all --timeout=300s 2>/dev/null || log_warn "DSC deletion wait timed out or no resources found"
    oc wait --for=delete dscinitializations.dscinitialization.opendatahub.io --all --timeout=300s 2>/dev/null || log_warn "DSCI deletion wait timed out or no resources found"
    log_info "DSC and DSCI fully deleted"
    
    # Step 3 - Delete RHOAI operator subscription
    log_info "Step 3: Deleting RHOAI operator subscription..."
    
    if oc get subscription rhods-operator -n redhat-ods-operator &> /dev/null; then
        log_info "  - Deleting subscription: rhods-operator"
        oc delete subscription rhods-operator -n redhat-ods-operator || log_warn "Failed to delete RHOAI subscription"
    else
        log_warn "  - RHOAI subscription not found"
    fi
    
    # Step 4 - Delete RHOAI operator CSV
    log_info "Step 4: Deleting RHOAI operator CSV..."
    
    RHOAI_CSV=$(oc get csv -n redhat-ods-operator -o name 2>/dev/null | grep -i rhods || true)
    if [ -n "$RHOAI_CSV" ]; then
        log_info "  - Deleting CSV: ${RHOAI_CSV}"
        oc delete ${RHOAI_CSV} -n redhat-ods-operator || log_warn "Failed to delete RHOAI CSV"
    else
        log_warn "  - RHOAI CSV not found"
    fi
    
    # Step 5 - Delete RHOAI operator OperatorGroup
    log_info "Step 5: Deleting RHOAI operator OperatorGroup..."
    
    if oc get operatorgroup redhat-ods-operator -n redhat-ods-operator &> /dev/null; then
        log_info "  - Deleting OperatorGroup: redhat-ods-operator"
        oc delete operatorgroup redhat-ods-operator -n redhat-ods-operator || log_warn "Failed to delete RHOAI OperatorGroup"
    else
        log_warn "  - RHOAI OperatorGroup not found"
    fi
    
    # Step 6 - Delete CatalogSource
    log_info "Step 6: Deleting RHOAI CatalogSource..."
    
    if oc get catalogsource rhoai-catalog-dev -n openshift-marketplace &> /dev/null; then
        log_info "  - Deleting CatalogSource: rhoai-catalog-dev"
        oc delete catalogsource rhoai-catalog-dev -n openshift-marketplace || log_warn "Failed to delete RHOAI CatalogSource"
    else
        log_warn "  - RHOAI CatalogSource not found"
    fi
    
    # Step 7 - Delete prerequisite operators
    log_info "Step 7: Deleting prerequisite operators..."
    
    # Delete Service Mesh operator
    log_info "  - Deleting Red Hat OpenShift Service Mesh operator..."
    if oc get subscription servicemeshoperator -n openshift-operators &> /dev/null; then
        oc delete subscription servicemeshoperator -n openshift-operators || log_warn "Failed to delete Service Mesh subscription"
        
        SERVICEMESH_CSV=$(oc get csv -n openshift-operators -o name 2>/dev/null | grep servicemesh || true)
        if [ -n "$SERVICEMESH_CSV" ]; then
            log_info "    - Deleting Service Mesh CSV: ${SERVICEMESH_CSV}"
            oc delete ${SERVICEMESH_CSV} -n openshift-operators || log_warn "Failed to delete Service Mesh CSV"
        fi
    else
        log_warn "    - Service Mesh subscription not found"
    fi
    
    # Delete Serverless operator
    log_info "  - Deleting Red Hat OpenShift Serverless operator..."
    if oc get subscription serverless-operator -n openshift-serverless &> /dev/null; then
        oc delete subscription serverless-operator -n openshift-serverless || log_warn "Failed to delete Serverless subscription"
        
        SERVERLESS_CSV=$(oc get csv -n openshift-serverless -o name 2>/dev/null | grep serverless || true)
        if [ -n "$SERVERLESS_CSV" ]; then
            log_info "    - Deleting Serverless CSV: ${SERVERLESS_CSV}"
            oc delete ${SERVERLESS_CSV} -n openshift-serverless || log_warn "Failed to delete Serverless CSV"
        fi
    else
        log_warn "    - Serverless subscription not found"
    fi
    
    # Delete Serverless OperatorGroup
    if oc get operatorgroup openshift-serverless -n openshift-serverless &> /dev/null; then
        log_info "    - Deleting Serverless OperatorGroup"
        oc delete operatorgroup openshift-serverless -n openshift-serverless || log_warn "Failed to delete Serverless OperatorGroup"
    fi
    
    # Delete Authorino operator
    log_info "  - Deleting Red Hat Authorino operator..."
    if oc get subscription authorino-operator -n openshift-operators &> /dev/null; then
        oc delete subscription authorino-operator -n openshift-operators || log_warn "Failed to delete Authorino subscription"
        
        AUTHORINO_CSV=$(oc get csv -n openshift-operators -o name 2>/dev/null | grep authorino || true)
        if [ -n "$AUTHORINO_CSV" ]; then
            log_info "    - Deleting Authorino CSV: ${AUTHORINO_CSV}"
            oc delete ${AUTHORINO_CSV} -n openshift-operators || log_warn "Failed to delete Authorino CSV"
        fi
    else
        log_warn "    - Authorino subscription not found"
    fi
    
    log_info "Prerequisite operators deleted"
    
    # Step 8 - Delete namespaces
    log_info "Step 8: Deleting namespaces..."
    
    if oc get namespace redhat-ods-operator &> /dev/null; then
        log_info "  - Deleting namespace: redhat-ods-operator"
        oc delete namespace redhat-ods-operator --timeout=300s || log_warn "Namespace deletion timed out (may still be in progress)"
    else
        log_warn "  - Namespace redhat-ods-operator not found"
    fi
    
    if oc get namespace openshift-serverless &> /dev/null; then
        log_info "  - Deleting namespace: openshift-serverless"
        oc delete namespace openshift-serverless --timeout=300s || log_warn "Namespace deletion timed out (may still be in progress)"
    else
        log_warn "  - Namespace openshift-serverless not found"
    fi
    
    # Check for and delete RHOAI application namespace
    if oc get namespace redhat-ods-applications &> /dev/null; then
        log_info "  - Deleting namespace: redhat-ods-applications"
        oc delete namespace redhat-ods-applications --timeout=300s || log_warn "Namespace deletion timed out (may still be in progress)"
    else
        log_warn "  - Namespace redhat-ods-applications not found"
    fi
    
    if oc get namespace redhat-ods-monitoring &> /dev/null; then
        log_info "  - Deleting namespace: redhat-ods-monitoring"
        oc delete namespace redhat-ods-monitoring --timeout=300s || log_warn "Namespace deletion timed out (may still be in progress)"
    else
        log_warn "  - Namespace redhat-ods-monitoring not found"
    fi
    
    if oc get namespace opendatahub &> /dev/null; then
        log_info "  - Deleting namespace: opendatahub"
        oc delete namespace opendatahub --timeout=300s || log_warn "Namespace deletion timed out (may still be in progress)"
    else
        log_warn "  - Namespace opendatahub not found"
    fi
    
    if oc get namespace rhods-notebooks &> /dev/null; then
        log_info "  - Deleting namespace: rhods-notebooks"
        oc delete namespace rhods-notebooks --timeout=300s || log_warn "Namespace deletion timed out (may still be in progress)"
    else
        log_warn "  - Namespace rhods-notebooks not found"
    fi
    
    if oc get namespace redhat-ods-applications-auth-provider &> /dev/null; then
        log_info "  - Deleting namespace: redhat-ods-applications-auth-provider"
        oc delete namespace redhat-ods-applications-auth-provider --timeout=300s || log_warn "Namespace deletion timed out (may still be in progress)"
    else
        log_warn "  - Namespace redhat-ods-applications-auth-provider not found"
    fi
    
    log_info "Namespaces deleted"
    
    # Step 9 - Delete RHOAI Custom Resource Definitions
    log_info "Step 9: Deleting RHOAI Custom Resource Definitions..."
    
    CRDS=(
        "acceleratorprofiles.dashboard.opendatahub.io"
        "auths.services.platform.opendatahub.io"
        "codeflares.components.platform.opendatahub.io"
        "dashboards.components.platform.opendatahub.io"
        "datascienceclusters.datasciencecluster.opendatahub.io"
        "datasciencepipelines.components.platform.opendatahub.io"
        "dscinitializations.dscinitialization.opendatahub.io"
        "feastoperators.components.platform.opendatahub.io"
        "featuretrackers.features.opendatahub.io"
        "hardwareprofiles.dashboard.opendatahub.io"
        "hardwareprofiles.infrastructure.opendatahub.io"
        "kserves.components.platform.opendatahub.io"
        "kueues.components.platform.opendatahub.io"
        "llamastackoperators.components.platform.opendatahub.io"
        "modelcontrollers.components.platform.opendatahub.io"
        "modelmeshservings.components.platform.opendatahub.io"
        "modelregistries.components.platform.opendatahub.io"
        "monitorings.services.platform.opendatahub.io"
        "rays.components.platform.opendatahub.io"
        "servicemeshes.services.platform.opendatahub.io"
        "trainingoperators.components.platform.opendatahub.io"
        "trustyais.components.platform.opendatahub.io"
        "workbenches.components.platform.opendatahub.io"
    )
    
    for crd in "${CRDS[@]}"; do
        if oc get crd "$crd" &> /dev/null; then
            log_info "  - Deleting CRD: $crd"
            oc delete crd "$crd" --timeout=60s || log_warn "Failed to delete CRD: $crd"
        else
            log_warn "  - CRD not found: $crd"
        fi
    done
    
    log_info "Custom Resource Definitions deleted"
    
    log_info "========================================="
    log_info "RHOAI 2.x cleanup completed"
    log_info "========================================="
    
elif [ "$RHOAI_VERSION" = "3.x" ]; then
    log_info "========================================="
    log_info "Starting RHOAI 3.x cleanup"
    log_info "========================================="
    
    # Step 1 - Delete RHOAI custom resources
    log_info "Step 1: Deleting RHOAI custom resources..."
    
    log_info "  - Deleting InferenceServices..."
    oc delete inferenceservices.serving.kserve.io --all -A --timeout=60s || log_warn "No InferenceServices found or deletion timed out"
    
    log_info "  - Deleting ServingRuntimes..."
    oc delete servingruntimes.serving.kserve.io --all -A --timeout=60s || log_warn "No ServingRuntimes found or deletion timed out"
    
    log_info "  - Deleting Notebooks..."
    oc delete notebooks.kubeflow.org --all -A --timeout=60s || log_warn "No Notebooks found or deletion timed out"
    
    log_info "  - Deleting HardwareProfiles..."
    oc delete hardwareprofiles.infrastructure.opendatahub.io --all -A --timeout=60s || log_warn "No HardwareProfiles found or deletion timed out"
    
    log_info "  - Deleting AcceleratorProfiles..."
    oc delete acceleratorprofiles.dashboard.opendatahub.io --all -A --timeout=60s || log_warn "No AcceleratorProfiles found or deletion timed out"
    
    log_info "Custom resources deleted"
    
    # Step 2 - Delete DataScienceCluster and DataScienceClusterInitialization
    log_info "Step 2: Deleting DataScienceCluster and DataScienceClusterInitialization..."
    
    if oc get datasciencecluster default-dsc &> /dev/null; then
        log_info "  - Deleting DataScienceCluster: default-dsc"
        oc delete datasciencecluster default-dsc --timeout=300s || log_warn "DataScienceCluster deletion timed out"
    else
        log_warn "  - DataScienceCluster default-dsc not found"
    fi
    
    # Check for any other DataScienceClusters
    OTHER_DSC=$(oc get datasciencecluster -o name 2>/dev/null || true)
    if [ -n "$OTHER_DSC" ]; then
        log_info "  - Deleting remaining DataScienceClusters..."
        oc delete datasciencecluster --all --timeout=300s || log_warn "Remaining DataScienceClusters deletion timed out"
    fi
    
    # Delete DSCI
    DSCI=$(oc get dscinitializations.dscinitialization.opendatahub.io -o name 2>/dev/null || true)
    if [ -n "$DSCI" ]; then
        log_info "  - Deleting DataScienceClusterInitialization..."
        oc delete dscinitializations.dscinitialization.opendatahub.io --all --timeout=300s || log_warn "DSCI deletion timed out"
    else
        log_warn "  - No DataScienceClusterInitialization found"
    fi
    
    log_info "DataScienceCluster and DSCI deleted"
    
    # Wait for DSC and DSCI to be fully removed
    log_info "Waiting for DataScienceCluster and DSCI to be fully deleted..."
    oc wait --for=delete datasciencecluster --all --timeout=300s 2>/dev/null || log_warn "DSC deletion wait timed out or no resources found"
    oc wait --for=delete dscinitializations.dscinitialization.opendatahub.io --all --timeout=300s 2>/dev/null || log_warn "DSCI deletion wait timed out or no resources found"
    log_info "DSC and DSCI fully deleted"
    
    # Step 3 - Delete RHOAI operator subscription
    log_info "Step 3: Deleting RHOAI operator subscription..."
    
    if oc get subscription rhods-operator -n redhat-ods-operator &> /dev/null; then
        log_info "  - Deleting subscription: rhods-operator"
        oc delete subscription rhods-operator -n redhat-ods-operator || log_warn "Failed to delete RHOAI subscription"
    else
        log_warn "  - RHOAI subscription not found"
    fi
    
    # Step 4 - Delete RHOAI operator CSV
    log_info "Step 4: Deleting RHOAI operator CSV..."
    
    RHOAI_CSV=$(oc get csv -n redhat-ods-operator -o name 2>/dev/null | grep -i rhods || true)
    if [ -n "$RHOAI_CSV" ]; then
        log_info "  - Deleting CSV: ${RHOAI_CSV}"
        oc delete ${RHOAI_CSV} -n redhat-ods-operator || log_warn "Failed to delete RHOAI CSV"
    else
        log_warn "  - RHOAI CSV not found"
    fi
    
    # Step 5 - Delete RHOAI operator OperatorGroup
    log_info "Step 5: Deleting RHOAI operator OperatorGroup..."
    
    if oc get operatorgroup redhat-ods-operator -n redhat-ods-operator &> /dev/null; then
        log_info "  - Deleting OperatorGroup: redhat-ods-operator"
        oc delete operatorgroup redhat-ods-operator -n redhat-ods-operator || log_warn "Failed to delete RHOAI OperatorGroup"
    else
        log_warn "  - RHOAI OperatorGroup not found"
    fi
    
    # Step 6 - Delete CatalogSource
    log_info "Step 6: Deleting RHOAI CatalogSource..."
    
    if oc get catalogsource rhoai-catalog-dev -n openshift-marketplace &> /dev/null; then
        log_info "  - Deleting CatalogSource: rhoai-catalog-dev"
        oc delete catalogsource rhoai-catalog-dev -n openshift-marketplace || log_warn "Failed to delete RHOAI CatalogSource"
    else
        log_warn "  - RHOAI CatalogSource not found"
    fi
    
    # Step 7 - Delete prerequisite operators
    log_info "Step 7: Deleting prerequisite operators..."
    
    # Delete RHCL operator
    log_info "  - Deleting Red Hat Connectivity Link operator..."
    if oc get subscription rhcl-operator -n openshift-operators &> /dev/null; then
        oc delete subscription rhcl-operator -n openshift-operators || log_warn "Failed to delete RHCL subscription"
        
        RHCL_CSV=$(oc get csv -n openshift-operators -o name 2>/dev/null | grep rhcl || true)
        if [ -n "$RHCL_CSV" ]; then
            log_info "    - Deleting RHCL CSV: ${RHCL_CSV}"
            oc delete ${RHCL_CSV} -n openshift-operators || log_warn "Failed to delete RHCL CSV"
        fi
    else
        log_warn "    - RHCL subscription not found"
    fi
    
    # Delete Authorino operator
    log_info "  - Deleting Authorino operator..."
    if oc get subscription authorino-operator-stable-redhat-operators-openshift-marketplace -n openshift-operators &> /dev/null; then
        oc delete subscription authorino-operator-stable-redhat-operators-openshift-marketplace -n openshift-operators || log_warn "Failed to delete Authorino subscription"
        
        AUTHORINO_CSV=$(oc get csv -n openshift-operators -o name 2>/dev/null | grep authorino || true)
        if [ -n "$AUTHORINO_CSV" ]; then
            log_info "    - Deleting Authorino CSV: ${AUTHORINO_CSV}"
            oc delete ${AUTHORINO_CSV} -n openshift-operators || log_warn "Failed to delete Authorino CSV"
        fi
    else
        log_warn "    - Authorino subscription not found"
    fi
    
    # Delete DNS operator
    log_info "  - Deleting DNS operator..."
    if oc get subscription dns-operator-stable-redhat-operators-openshift-marketplace -n openshift-operators &> /dev/null; then
        oc delete subscription dns-operator-stable-redhat-operators-openshift-marketplace -n openshift-operators || log_warn "Failed to delete DNS subscription"
        
        DNS_CSV=$(oc get csv -n openshift-operators -o name 2>/dev/null | grep dns || true)
        if [ -n "$DNS_CSV" ]; then
            log_info "    - Deleting DNS CSV: ${DNS_CSV}"
            oc delete ${DNS_CSV} -n openshift-operators || log_warn "Failed to delete DNS CSV"
        fi
    else
        log_warn "    - DNS subscription not found"
    fi
    
    # Delete Limitador operator
    log_info "  - Deleting Limitador operator..."
    if oc get subscription limitador-operator-stable-redhat-operators-openshift-marketplace -n openshift-operators &> /dev/null; then
        oc delete subscription limitador-operator-stable-redhat-operators-openshift-marketplace -n openshift-operators || log_warn "Failed to delete Limitador subscription"
        
        LIMITADOR_CSV=$(oc get csv -n openshift-operators -o name 2>/dev/null | grep limitador || true)
        if [ -n "$LIMITADOR_CSV" ]; then
            log_info "    - Deleting Limitador CSV: ${LIMITADOR_CSV}"
            oc delete ${LIMITADOR_CSV} -n openshift-operators || log_warn "Failed to delete Limitador CSV"
        fi
    else
        log_warn "    - Limitador subscription not found"
    fi
    
    # Delete Service Mesh 3 operator
    log_info "  - Deleting Red Hat OpenShift Service Mesh 3 operator..."
    if oc get subscription servicemeshoperator3 -n openshift-operators &> /dev/null; then
        oc delete subscription servicemeshoperator3 -n openshift-operators || log_warn "Failed to delete Service Mesh 3 subscription"
        
        SERVICEMESH3_CSV=$(oc get csv -n openshift-operators -o name 2>/dev/null | grep servicemeshoperator3 || true)
        if [ -n "$SERVICEMESH3_CSV" ]; then
            log_info "    - Deleting Service Mesh 3 CSV: ${SERVICEMESH3_CSV}"
            oc delete ${SERVICEMESH3_CSV} -n openshift-operators || log_warn "Failed to delete Service Mesh 3 CSV"
        fi
    else
        log_warn "    - Service Mesh 3 subscription not found"
    fi
    
    log_info "Prerequisite operators deleted"
    
    # Step 8 - Delete namespaces
    log_info "Step 8: Deleting namespaces..."
    
    if oc get namespace redhat-ods-operator &> /dev/null; then
        log_info "  - Deleting namespace: redhat-ods-operator"
        oc delete namespace redhat-ods-operator --timeout=300s || log_warn "Namespace deletion timed out (may still be in progress)"
    else
        log_warn "  - Namespace redhat-ods-operator not found"
    fi
    
    if oc get namespace openshift-serverless &> /dev/null; then
        log_info "  - Deleting namespace: openshift-serverless"
        oc delete namespace openshift-serverless --timeout=300s || log_warn "Namespace deletion timed out (may still be in progress)"
    else
        log_warn "  - Namespace openshift-serverless not found"
    fi
    
    if oc get namespace redhat-ods-applications &> /dev/null; then
        log_info "  - Deleting namespace: redhat-ods-applications"
        oc delete namespace redhat-ods-applications --timeout=300s || log_warn "Namespace deletion timed out (may still be in progress)"
    else
        log_warn "  - Namespace redhat-ods-applications not found"
    fi
    
    if oc get namespace redhat-ods-monitoring &> /dev/null; then
        log_info "  - Deleting namespace: redhat-ods-monitoring"
        oc delete namespace redhat-ods-monitoring --timeout=300s || log_warn "Namespace deletion timed out (may still be in progress)"
    else
        log_warn "  - Namespace redhat-ods-monitoring not found"
    fi
    
    if oc get namespace opendatahub &> /dev/null; then
        log_info "  - Deleting namespace: opendatahub"
        oc delete namespace opendatahub --timeout=300s || log_warn "Namespace deletion timed out (may still be in progress)"
    else
        log_warn "  - Namespace opendatahub not found"
    fi
    
    if oc get namespace rhods-notebooks &> /dev/null; then
        log_info "  - Deleting namespace: rhods-notebooks"
        oc delete namespace rhods-notebooks --timeout=300s || log_warn "Namespace deletion timed out (may still be in progress)"
    else
        log_warn "  - Namespace rhods-notebooks not found"
    fi
    
    if oc get namespace redhat-ods-applications-auth-provider &> /dev/null; then
        log_info "  - Deleting namespace: redhat-ods-applications-auth-provider"
        oc delete namespace redhat-ods-applications-auth-provider --timeout=300s || log_warn "Namespace deletion timed out (may still be in progress)"
    else
        log_warn "  - Namespace redhat-ods-applications-auth-provider not found"
    fi
    
    log_info "Namespaces deleted"
    
    # Step 9 - Delete RHOAI Custom Resource Definitions
    log_info "Step 9: Deleting RHOAI Custom Resource Definitions..."
    
    CRDS=(
        "acceleratorprofiles.dashboard.opendatahub.io"
        "auths.services.platform.opendatahub.io"
        "codeflares.components.platform.opendatahub.io"
        "dashboards.components.platform.opendatahub.io"
        "datascienceclusters.datasciencecluster.opendatahub.io"
        "datasciencepipelines.components.platform.opendatahub.io"
        "dscinitializations.dscinitialization.opendatahub.io"
        "feastoperators.components.platform.opendatahub.io"
        "featuretrackers.features.opendatahub.io"
        "gatewayconfigs.services.platform.opendatahub.io"
        "hardwareprofiles.dashboard.opendatahub.io"
        "hardwareprofiles.infrastructure.opendatahub.io"
        "kserves.components.platform.opendatahub.io"
        "kueues.components.platform.opendatahub.io"
        "llamastackoperators.components.platform.opendatahub.io"
        "mlflowoperators.components.platform.opendatahub.io"
        "modelcontrollers.components.platform.opendatahub.io"
        "modelmeshservings.components.platform.opendatahub.io"
        "modelregistries.components.platform.opendatahub.io"
        "modelsasservices.components.platform.opendatahub.io"
        "monitorings.services.platform.opendatahub.io"
        "rays.components.platform.opendatahub.io"
        "servicemeshes.services.platform.opendatahub.io"
        "trainers.components.platform.opendatahub.io"
        "trainingoperators.components.platform.opendatahub.io"
        "trustyais.components.platform.opendatahub.io"
        "workbenches.components.platform.opendatahub.io"
    )
    
    for crd in "${CRDS[@]}"; do
        if oc get crd "$crd" &> /dev/null; then
            log_info "  - Deleting CRD: $crd"
            oc delete crd "$crd" --timeout=60s || log_warn "Failed to delete CRD: $crd"
        else
            log_warn "  - CRD not found: $crd"
        fi
    done
    
    log_info "Custom Resource Definitions deleted"
    
    log_info "========================================="
    log_info "RHOAI 3.x cleanup completed"
    log_info "========================================="
fi

echo ""
log_info "========================================="
log_info "Cleanup Summary"
log_info "========================================="
log_info "Version cleaned: ${RHOAI_VERSION}"
log_info "Cluster: $(oc whoami --show-server)"
log_info ""
log_info "========================================="
