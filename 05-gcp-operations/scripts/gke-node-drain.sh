#!/usr/bin/env bash
# Safer GKE node drain helper with preflight checks and dry-run mode.
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
CLUSTER=""
LOCATION=""
NODE=""
EXECUTE=false
GET_CREDENTIALS=false
DELETE_EMPTYDIR_DATA=true
FORCE_DRAIN=false
SKIP_PDB_CHECK=false
DRAIN_TIMEOUT="600s"
GRACE_PERIOD="-1"

usage() {
  cat <<'EOF'
Usage: ./gke-node-drain.sh --node NODE [options]

Options:
  --node NODE                 Node name to cordon and drain
  --project PROJECT           GCP project ID
  --cluster CLUSTER           GKE cluster name
  --location LOCATION         Cluster region or zone
  --get-credentials           Refresh kubeconfig before checks
  --execute                   Perform the drain; default is dry-run only
  --no-delete-emptydir-data   Do not delete emptyDir volumes during drain
  --force                     Pass --force to kubectl drain
  --skip-pdb-check            Skip PDB warnings
  --drain-timeout TIMEOUT     Drain timeout (default: 600s)
  --grace-period SECONDS      Grace period for pod termination
  -h, --help                  Show help

Examples:
  ./gke-node-drain.sh --node gke-prod-node-1
  ./gke-node-drain.sh --project my-project --cluster prod-cluster --location us-central1 --node gke-prod-node-1 --execute
EOF
}

section() {
  printf "\n${BLUE}=== %s ===${NC}\n" "$1"
}

ok() {
  printf "${GREEN}[OK]${NC} %s\n" "$*"
}

warn() {
  printf "${YELLOW}[WARN]${NC} %s\n" "$*"
}

fail() {
  printf "${RED}[FAIL]${NC} %s\n" "$*"
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --node)
        NODE="$2"
        shift 2
        ;;
      --project)
        PROJECT="$2"
        shift 2
        ;;
      --cluster)
        CLUSTER="$2"
        shift 2
        ;;
      --location)
        LOCATION="$2"
        shift 2
        ;;
      --get-credentials)
        GET_CREDENTIALS=true
        shift
        ;;
      --execute)
        EXECUTE=true
        shift
        ;;
      --no-delete-emptydir-data)
        DELETE_EMPTYDIR_DATA=false
        shift
        ;;
      --force)
        FORCE_DRAIN=true
        shift
        ;;
      --skip-pdb-check)
        SKIP_PDB_CHECK=true
        shift
        ;;
      --drain-timeout)
        DRAIN_TIMEOUT="$2"
        shift 2
        ;;
      --grace-period)
        GRACE_PERIOD="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "Unknown option: $1"
        ;;
    esac
  done
}

maybe_refresh_kubeconfig() {
  if [[ "$GET_CREDENTIALS" != true ]]; then
    return
  fi

  [[ -n "$CLUSTER" && -n "$LOCATION" && -n "$PROJECT" ]] || fail "--get-credentials requires --cluster, --location, and --project"

  section "Refreshing kubeconfig"
  gcloud container clusters get-credentials "$CLUSTER" --location "$LOCATION" --project "$PROJECT" >/dev/null
  ok "Updated kubeconfig for ${CLUSTER}"
}

check_context() {
  section "Context checks"
  kubectl version --request-timeout=10s >/dev/null 2>&1 || fail "kubectl cannot reach the cluster"
  ok "kubectl API access is healthy"
  info_context="$(kubectl config current-context 2>/dev/null || true)"
  if [[ -n "$info_context" ]]; then
    ok "Current context: ${info_context}"
  fi
}

check_node_exists() {
  section "Node checks"
  kubectl get node "$NODE" >/dev/null 2>&1 || fail "Node ${NODE} not found"
  ok "Node ${NODE} exists"

  local state
  state="$(kubectl get node "$NODE" -o jsonpath='{.spec.unschedulable}' 2>/dev/null || true)"
  if [[ "$state" == "true" ]]; then
    warn "Node ${NODE} is already cordoned"
  else
    ok "Node ${NODE} is schedulable"
  fi

  kubectl get node "$NODE" -o wide
}

check_cluster_capacity() {
  section "Capacity checks"
  local ready_others
  ready_others="$(kubectl get nodes --no-headers 2>/dev/null | awk -v node="$NODE" '$1 != node && $2 ~ /^Ready/ {count++} END {print count+0}')"
  if [[ "$ready_others" -gt 0 ]]; then
    ok "${ready_others} other Ready node(s) available"
  else
    fail "No other Ready nodes available; drain would be highly disruptive"
  fi
}

inspect_workloads() {
  section "Workloads on target node"
  local pods
  pods="$(kubectl get pods -A --field-selector spec.nodeName="$NODE" --no-headers 2>/dev/null || true)"

  if [[ -z "$pods" ]]; then
    warn "No pods currently scheduled on ${NODE}"
    return
  fi

  printf '%s\n' "$pods" | awk '{printf "%-20s %-40s %-20s %-10s\n", $1, $2, $4, $3}' | head -40

  local ds_pods regular_pods
  ds_pods="$(printf '%s\n' "$pods" | grep -E 'DaemonSet|daemon' || true)"
  regular_pods="$(printf '%s\n' "$pods" | grep -vE 'DaemonSet|daemon' || true)"

  if [[ -n "$regular_pods" ]]; then
    ok "Found evictable workload pods on ${NODE}"
  else
    warn "Only daemonset-style or non-evictable pods detected"
  fi

  if [[ -n "$ds_pods" ]]; then
    info "Daemonset-like workloads will remain unless node is removed"
  fi
}

check_pdbs() {
  if [[ "$SKIP_PDB_CHECK" == true ]]; then
    section "PDB checks"
    warn "Skipping PDB review by request"
    return
  fi

  section "PDB checks"
  local namespaces line issues=0
  namespaces="$(kubectl get pods -A --field-selector spec.nodeName="$NODE" -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}' 2>/dev/null | sort -u | sed '/^$/d' || true)"

  if [[ -z "$namespaces" ]]; then
    warn "No namespaces found for pods on ${NODE}"
    return
  fi

  while IFS= read -r ns; do
    [[ -z "$ns" ]] && continue
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local name min_available allowed_disruptions current_healthy desired_healthy
      name="$(printf '%s\n' "$line" | awk '{print $1}')"
      min_available="$(printf '%s\n' "$line" | awk '{print $2}')"
      current_healthy="$(printf '%s\n' "$line" | awk '{print $4}')"
      desired_healthy="$(printf '%s\n' "$line" | awk '{print $5}')"
      allowed_disruptions="$(printf '%s\n' "$line" | awk '{print $6}')"

      if [[ "$allowed_disruptions" == "0" ]]; then
        warn "PDB ${ns}/${name} allows zero disruptions (current=${current_healthy}, desired=${desired_healthy}, min=${min_available})"
        issues=$((issues + 1))
      fi
    done < <(kubectl get pdb -n "$ns" --no-headers 2>/dev/null || true)
  done <<< "$namespaces"

  if [[ "$issues" -eq 0 ]]; then
    ok "No obvious PDB blockers found"
  else
    warn "Review PDB blockers before draining"
  fi
}

build_drain_command() {
  DRAIN_CMD=(kubectl drain "$NODE" --ignore-daemonsets --timeout="$DRAIN_TIMEOUT")

  if [[ "$DELETE_EMPTYDIR_DATA" == true ]]; then
    DRAIN_CMD+=(--delete-emptydir-data)
  fi

  if [[ "$FORCE_DRAIN" == true ]]; then
    DRAIN_CMD+=(--force)
  fi

  if [[ "$GRACE_PERIOD" != "-1" ]]; then
    DRAIN_CMD+=(--grace-period="$GRACE_PERIOD")
  fi
}

show_plan() {
  section "Drain plan"
  build_drain_command
  printf 'Cordon command: kubectl cordon %s\n' "$NODE"
  printf 'Drain command: '
  printf '%q ' "${DRAIN_CMD[@]}"
  printf '\n'

  if [[ "$EXECUTE" != true ]]; then
    warn "Dry-run mode only. Re-run with --execute to apply the drain."
  else
    ok "Execution mode enabled"
  fi
}

perform_drain() {
  [[ "$EXECUTE" == true ]] || return

  section "Executing drain"
  kubectl cordon "$NODE"
  ok "Node cordoned"

  build_drain_command
  "${DRAIN_CMD[@]}"
  ok "Node drained"
}

post_verify() {
  section "Post-drain verification"
  local remaining
  remaining="$(kubectl get pods -A --field-selector spec.nodeName="$NODE" --no-headers 2>/dev/null || true)"

  if [[ -z "$remaining" ]]; then
    ok "No pods remain scheduled on ${NODE}"
  else
    warn "Some pods still remain on ${NODE}"
    printf '%s\n' "$remaining"
  fi

  info "To restore scheduling after maintenance: kubectl uncordon ${NODE}"
}

main() {
  parse_args "$@"
  require_cmd gcloud
  require_cmd kubectl
  [[ -n "$NODE" ]] || fail "--node is required"
  [[ -n "$PROJECT" ]] || fail "No project supplied and no default project configured"

  printf '==============================================\n'
  printf ' GKE Node Drain Planner — %s\n' "$(date)"
  printf ' Project: %s\n' "$PROJECT"
  printf ' Node: %s\n' "$NODE"
  printf '==============================================\n'

  maybe_refresh_kubeconfig
  check_context
  check_node_exists
  check_cluster_capacity
  inspect_workloads
  check_pdbs
  show_plan
  perform_drain
  post_verify
}

main "$@"
