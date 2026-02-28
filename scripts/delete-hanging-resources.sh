#!/bin/bash
# delete-hanging-resources.sh
# Finds resources stuck in Terminating (from pre-post cluster state YAMLs) and removes
# finalizers so they can be deleted. Run after cleanup-rhoai.sh if objects are stuck.
#
# Usage: ./delete-hanging-resources.sh [--dry-run]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${SCRIPT_DIR}/../pre-post-cluster-state"
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
  esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if ! command -v oc &> /dev/null; then
  log_error "oc not found. Install OpenShift CLI."
  exit 1
fi
if ! oc whoami &> /dev/null; then
  log_error "Not logged in. Run 'oc login' first."
  exit 1
fi
if ! command -v jq &> /dev/null; then
  log_error "jq not found. Install jq for JSON parsing."
  exit 1
fi

# Resource types that appear in pre-post YAMLs and can get stuck in Terminating.
# Format: "oc resource type" (as used in: oc get <type> -A)
RESOURCE_TYPES=(
  "inferenceservices.serving.kserve.io"
  "servingruntimes.serving.kserve.io"
  "notebooks.kubeflow.org"
  "hardwareprofiles.infrastructure.opendatahub.io"
  "acceleratorprofiles.dashboard.opendatahub.io"
  "datascienceclusters.datasciencecluster.opendatahub.io"
  "dscinitializations.dscinitialization.opendatahub.io"
  "datasciencecluster"
  "datascienceclusterinitialization"
  "deployment"
  "replicaset"
  "statefulset"
  "pod"
  "namespace"
)

find_terminating() {
  local rtype="$1"
  oc get "$rtype" -A -o json 2>/dev/null | jq -r '
    .items[]? | select(.metadata.deletionTimestamp != null) |
    "\(.metadata.namespace) \(.metadata.name)"
  ' 2>/dev/null || true
}

patch_remove_finalizers() {
  local rtype="$1"
  local ns="$2"
  local name="$3"
  # For cluster-scoped namespace resource, jq outputs "null <name>"
  if [[ "$rtype" == "namespace" ]]; then
    [[ "$ns" == "null" || -z "$ns" ]] && ns="$name"
    name="$ns"
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    [[ "$rtype" == "namespace" ]] && log_info "[DRY-RUN] Would patch namespace $name" || log_info "[DRY-RUN] Would patch $rtype $name -n $ns"
    return 0
  fi
  if [[ "$rtype" == "namespace" ]]; then
    oc patch namespace "$name" -p '{"metadata":{"finalizers":null}}' --type=merge || log_warn "Failed to patch namespace $name"
  else
    oc patch "$rtype" "$name" -n "$ns" -p '{"metadata":{"finalizers":null}}' --type=merge || log_warn "Failed to patch $rtype $name in $ns"
  fi
}

log_info "========================================="
log_info "Hanging (Terminating) resources cleanup"
log_info "========================================="
[[ "$DRY_RUN" == "true" ]] && log_warn "DRY-RUN: no changes will be made."
log_info "Cluster: $(oc whoami --show-server)"
echo ""

total_found=0
for rtype in "${RESOURCE_TYPES[@]}"; do
  count=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    ns="${line%% *}"
    name="${line#* }"
    log_info "Terminating: $rtype $name (ns: $ns)"
    patch_remove_finalizers "$rtype" "$ns" "$name"
    ((count++)) || true
  done < <(find_terminating "$rtype")
  if [[ $count -gt 0 ]]; then
    log_info "  -> Patched $count $rtype resource(s)"
    ((total_found+=count)) || true
  fi
done

echo ""
if [[ $total_found -eq 0 ]]; then
  log_info "No resources stuck in Terminating were found."
else
  log_info "Done. Patched $total_found resource(s) to remove finalizers."
  log_info "They should disappear shortly. Re-run this script if any remain."
fi
log_info "========================================="
