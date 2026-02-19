# rhoai-hwp-migration-test-helper

This repository contains helper scripts to test the Hardware Profile (HWP) migration that occurs during the Red Hat OpenShift AI (RHOAI) 2.25 to 3.3 upgrade.

## Overview

These scripts provide an end-to-end workflow for testing RHOAI upgrades, particularly focusing on the hardware profile migration from AcceleratorProfiles (2.x) to HardwareProfiles (3.x).

## Prerequisites

- OpenShift CLI (`oc`) installed and configured
- Logged in to an OpenShift cluster with cluster-admin privileges
- `jq` command-line tool (required for some scripts)

**GPU support (one-time):** To properly create and inject AP and deploy workloads into GPU nodes the cluster must have the NVIDIA GPU Operator installed. This is needed only once per cluster; skip if it is already set up. Run:

```bash
./scripts/setup-nvidia-gpu-operator.sh
```

Prerequisites for the GPU operator script:
- At least one GPU-capable node in the cluster (e.g. g4dn, p3, p4, A10, V100, T4)
- Cluster-admin permissions
- GPU node joined to the cluster before running the script

Without GPU nodes, workloads that request `nvidia.com/gpu` will remain unschedulable (Insufficient nvidia.com/gpu).

## Scripts

### 1. [setup-rhoai-2.25.sh](scripts/setup-rhoai-2.25.sh)

**Purpose:** Sets up a fresh RHOAI 2.25.1 installation on an OpenShift cluster.

**What it does:**
- Detects OpenShift version (4.19, 4.20, 4.21) and selects appropriate catalog source
- Creates CatalogSource for RHOAI 2.25.1
- Installs prerequisite operators:
  - Red Hat Authorino Operator (stable channel)
  - Red Hat OpenShift Serverless (stable channel)
  - Red Hat OpenShift Service Mesh 2 (stable channel)
- Installs RHOAI 2.25.1 operator (stable-2.25 channel)
- Creates DSCInitialization with managed Service Mesh
- Creates DataScienceCluster with dashboard, KServe, and workbenches components
- **Automatically configures hardware profiles ignorelist** by running `hardwareprofiles-ignorelist.sh`

**Usage:**
```bash
./scripts/setup-rhoai-2.25.sh [CATALOG_SOURCE_IMAGE]
```

**Parameters:**
- `CATALOG_SOURCE_IMAGE` (optional): Custom catalog source image. If not provided, uses default based on OpenShift version.

**Note:** This script automatically disables hardware profile annotations for InferenceServices as the final step of installation.

---

### 2. [capture-cluster-state.sh](scripts/capture-cluster-state.sh)

**Purpose:** Captures the state of RHOAI cluster resources before and after an upgrade.

**What it does:**
- Prompts user to select pre-upgrade or post-upgrade capture
- Pre-upgrade capture:
  - DataScienceCluster (DSC)
  - DSCInitialization (DSCI)
  - AcceleratorProfiles
  - ServingRuntimes, InferenceServices, and related resources
  - Notebooks and related resources
- Post-upgrade capture:
  - All pre-upgrade resources
  - **HardwareProfiles** (new in 3.x)
- Saves all resources to YAML files in `pre-post-cluster-state/` directory

**Usage:**
```bash
./scripts/capture-cluster-state.sh [output-directory]
```

**Parameters:**
- `output-directory` (optional): Directory name where files will be saved. Default: `pre-post-cluster-state/`

**Output Directory:** `pre-post-cluster-state/`

---

### 3. [prepare-rhoai-for-upgrade.sh](scripts/prepare-rhoai-for-upgrade.sh)

**Purpose:** Prepares RHOAI 2.25 for upgrade to 3.3 by handling incompatible components and operators.

**What it does:**

**Phase 1 - Disable incompatible components:**
- Sets DSC KServe serving managementState to `Removed`
- Sets DSCI Service Mesh managementState to `Removed`
- Waits for DSC and DSCI to reach Ready state

**Phase 2 - Manage operator dependencies:**
- Uninstalls Red Hat Authorino Operator
- Uninstalls Red Hat OpenShift Serverless (including namespace)
- Uninstalls Red Hat OpenShift Service Mesh 2
- Installs Red Hat Connectivity Link v1.2.1 (new dependency for 3.x)

**Phase 3 - Prepare RHOAI subscription:**
- Sets RHOAI subscription installPlanApproval to `Manual`
- Updates RHOAI subscription channel to `stable-3.3`
- Provides command to manually approve the upgrade

**Usage:**
```bash
./scripts/prepare-rhoai-for-upgrade.sh
```

**Next Steps:** After running this script, manually approve the upgrade using the provided command:
```bash
oc patch installplan <INSTALL_PLAN_NAME> -n redhat-ods-operator --type=merge -p '{"spec":{"approved":true}}'
```

---

### 4. [hardwareprofiles-ignorelist.sh](scripts/hardwareprofiles-ignorelist.sh)

**Purpose:** Disables hardware profile annotations in KServe's inferenceservice-config ConfigMap.

**What it does:**
- Adds `opendatahub.io/managed=false` annotation to the ConfigMap
- Adds hardware profile annotations to `serviceAnnotationDisallowedList`:
  - `opendatahub.io/hardware-profile-name`
  - `opendatahub.io/hardware-profile-namespace`
- Restarts kserve-controller-manager deployment to apply changes
- Supports dry-run mode for previewing changes

**Usage:**
```bash
# Apply changes
./scripts/hardwareprofiles-ignorelist.sh -n <namespace>

# Preview changes without applying
./scripts/hardwareprofiles-ignorelist.sh -n <namespace> --dry-run
```

**Parameters:**
- `-n, --namespace`: Application namespace where inferenceservice-config exists (required)
- `--dry-run`: Show what would be changed without applying (optional)

**Example:**
```bash
./scripts/hardwareprofiles-ignorelist.sh -n redhat-ods-applications
```

**Note:** This script is automatically called by `setup-rhoai-2.25.sh` during installation, so manual execution is typically not required unless you need to reconfigure or use dry-run mode.

---

### 5. [cleanup-rhoai.sh](scripts/cleanup-rhoai.sh)

**Purpose:** Completely removes RHOAI installation from an OpenShift cluster.

**What it does:**
- Supports cleanup of both RHOAI 2.x and 3.x
- Deletes custom resources (InferenceServices, ServingRuntimes, Notebooks, HardwareProfiles, AcceleratorProfiles)
- Deletes DataScienceCluster and DSCInitialization
- Removes RHOAI operator subscription, CSV, and OperatorGroup
- Removes CatalogSource
- Uninstalls prerequisite operators:
  - **2.x**: Authorino, Serverless, Service Mesh 2
  - **3.x**: RHCL, Authorino, DNS, Limitador, Service Mesh 3
- Deletes RHOAI namespaces
- Removes RHOAI Custom Resource Definitions (CRDs)

**Usage:**
```bash
./scripts/cleanup-rhoai.sh
```

**Interactive:** Script will prompt for RHOAI version (2.x or 3.x) and confirmation before proceeding.

---

### 6. [delete-hanging-resources.sh](scripts/delete-hanging-resources.sh)

**Purpose:** Finds resources stuck in **Terminating** after cleanup and removes their finalizers so they can be deleted. Use this when `cleanup-rhoai.sh` has run but some objects remain in Terminating state.

**What it does:**
- Scans the same resource types as in the pre/post cluster state YAMLs:
  - Custom resources: InferenceService, ServingRuntime, Notebook, HardwareProfile, AcceleratorProfile, DataScienceCluster, DSCInitialization (2.x and 3.x)
  - Core resources: Deployment, ReplicaSet, StatefulSet, Pod
  - Namespaces
- For each type, lists resources that have `metadata.deletionTimestamp` set (i.e. stuck in Terminating)
- Patches each such resource to remove `metadata.finalizers`, allowing the API server to complete deletion

**Usage:**
```bash
# Preview what would be patched (no changes)
./scripts/delete-hanging-resources.sh --dry-run

# Remove finalizers from hanging resources
./scripts/delete-hanging-resources.sh
```

**Parameters:**
- `--dry-run`: List terminating resources and show what would be patched; do not modify the cluster

**When to use:** Run after `cleanup-rhoai.sh` if namespaces, CRs, or workloads remain in Terminating. Re-run the script if any resources are still stuck after the first run.

**Requirements:** `oc` (logged in) and `jq`.

---

### 7. [setup-nvidia-gpu-operator.sh](scripts/setup-nvidia-gpu-operator.sh)

**Purpose:** Sets up the NVIDIA GPU Operator on an OpenShift cluster so GPU nodes can schedule workloads that request `nvidia.com/gpu` (e.g. RHOAI Notebooks or InferenceServices using AcceleratorProfiles/HardwareProfiles with GPU).

**What it does:**

**Phase 1 – Node Feature Discovery (NFD):**
- Creates namespace `openshift-nfd`
- Installs NFD Operator from `redhat-operators` (stable channel)
- Creates NodeFeatureDiscovery instance so nodes are labeled with hardware features (including GPU)

**Phase 2 – NVIDIA GPU Operator:**
- Creates namespace `nvidia-gpu-operator`
- Installs NVIDIA GPU Operator from `certified-operators` (stable channel)

**Phase 3 – ClusterPolicy:**
- Creates a ClusterPolicy `gpu-cluster-policy` with:
  - Driver enabled (using OCP driver toolkit)
  - Toolkit, device plugin, DCGM, DCGM Exporter, GFD, MIG Manager, Node Status Exporter
  - CDI enabled; vGPU and sandbox workloads disabled

**Phase 4 – Monitoring:**
- Waits for ClusterPolicy to reach ready state (up to ~15 minutes; driver compilation can be slow)

**Phase 5 – Verification:**
- Reports nodes with allocatable `nvidia.com/gpu`
- Shows GPU operator pod status and troubleshooting hints if GPUs are not yet available

**Prerequisites:**
- At least one GPU-capable node (e.g. g4dn, p3, p4, A10, V100, T4) in the cluster
- Cluster-admin permissions
- OpenShift CLI (`oc`) installed and logged in

**Usage:**
```bash
./scripts/setup-nvidia-gpu-operator.sh
```

**Interactive:** The script checks for GPU-capable nodes (by instance-type labels), then prompts for confirmation before installing.

**Namespaces created:** `openshift-nfd`, `nvidia-gpu-operator`

**Note:** This is a one-time prerequisite when testing GPU-backed resources (see [Prerequisites](#prerequisites)). Run it before creating GPU-backed Notebooks or AcceleratorProfiles if the cluster does not already have the NVIDIA GPU Operator.

---

## Typical Workflow

Here's a typical workflow for testing the RHOAI 2.25 to 3.3 upgrade:

1. **Install RHOAI 2.25:**
   ```bash
   ./scripts/setup-rhoai-2.25.sh
   ```
   > **Note:** This automatically configures hardware profiles ignorelist during installation.

2. **Create test resources** (AcceleratorProfiles, InferenceServices, Notebooks, etc.)

3. **Capture pre-upgrade state:**
   ```bash
   ./scripts/capture-cluster-state.sh
   # Select "pre" when prompted
   ```

4. **Prepare for upgrade:**
   ```bash
   ./scripts/prepare-rhoai-for-upgrade.sh
   ```

5. **Manually approve the upgrade** (use the command provided by the script)

6. **Wait for upgrade to complete** and verify RHOAI 3.3 is running

7. **Capture post-upgrade state:**
   ```bash
   ./scripts/capture-cluster-state.sh
   # Select "post" when prompted
   ```

8. **Compare pre and post upgrade states** to verify hardware profile migration

9. **(Optional) Clean up when testing is complete:**
   ```bash
   ./scripts/cleanup-rhoai.sh
   ```
   If some resources remain in **Terminating**, run:
   ```bash
   ./scripts/delete-hanging-resources.sh
   ```

---

## Output Files

All scripts create output files in the current directory:

- `capture-cluster-state.sh`: Creates `pre-post-cluster-state/` directory with YAML files
  - Pre-upgrade files: `pre-upgrade-*.yaml`
  - Post-upgrade files: `post-upgrade-*.yaml`

---

## Important Notes

- All scripts include confirmation prompts before making destructive changes
- Scripts use colored output for better visibility (INFO in green, WARN in yellow, ERROR in red)
- All scripts can be interrupted with Ctrl-C
- `cleanup-rhoai.sh` performs destructive operations - use with caution
- Always verify cluster state after running preparation and upgrade scripts

---