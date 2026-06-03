#!/usr/bin/env bash
# Advanced GCP and GKE health check script.
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
CLUSTER=""
LOCATION=""
NAMESPACE=""
GET_CREDENTIALS=false
INCLUDE_LOGS=false
SKIP_KUBECTL=false

usage() {
  cat <<'EOF'
Usage: ./gcp-health-check.sh [options]

Options:
  -p, --project PROJECT         GCP project ID
  -c, --cluster CLUSTER         GKE cluster name to inspect
  -l, --location LOCATION       Cluster region or zone
  -n, --namespace NAMESPACE     Focus pod checks on one namespace
      --get-credentials         Refresh kubeconfig for the target cluster
      --include-logs            Show recent Cloud Logging errors
      --skip-kubectl            Skip Kubernetes API checks
  -h, --help                    Show help

Examples:
  ./gcp-health-check.sh --project my-project
  ./gcp-health-check.sh --project my-project --cluster prod-cluster --location us-central1 --get-credentials
EOF
}

section() {
  printf "\n${BLUE}=== %s ===${NC}\n" "$1"
}

ok() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf "${GREEN}[OK]${NC} %s\n" "$*"
}

warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  printf "${YELLOW}[WARN]${NC} %s\n" "$*"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf "${RED}[FAIL]${NC} %s\n" "$*"
}

info() {
  printf "       %s\n" "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

safe_count_lines() {
  local output="${1:-}"
  if [[ -z "$output" ]]; then
    echo 0
  else
    printf '%s\n' "$output" | sed '/^$/d' | wc -l | tr -d ' '
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p|--project)
        PROJECT="$2"
        shift 2
        ;;
      -c|--cluster)
        CLUSTER="$2"
        shift 2
        ;;
      -l|--location)
        LOCATION="$2"
        shift 2
        ;;
      -n|--namespace)
        NAMESPACE="$2"
        shift 2
        ;;
      --get-credentials)
        GET_CREDENTIALS=true
        shift
        ;;
      --include-logs)
        INCLUDE_LOGS=true
        shift
        ;;
      --skip-kubectl)
        SKIP_KUBECTL=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
}

check_auth() {
  section "Authentication"
  local account
  account="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1 || true)"
  if [[ -n "$account" ]]; then
    ok "Authenticated as ${account}"
  else
    fail "No active gcloud account found"
    return
  fi

  if [[ -n "$PROJECT" ]]; then
    if gcloud projects describe "$PROJECT" >/dev/null 2>&1; then
      ok "Project ${PROJECT} is reachable"
    else
      fail "Project ${PROJECT} is not accessible with current identity"
    fi
  else
    fail "No project configured or supplied"
  fi
}

check_services() {
  section "Core APIs"
  local enabled
  enabled="$(gcloud services list --enabled --project "$PROJECT" --format='value(config.name)' 2>/dev/null || true)"

  for api in container.googleapis.com monitoring.googleapis.com logging.googleapis.com iam.googleapis.com; do
    if printf '%s\n' "$enabled" | grep -qx "$api"; then
      ok "API enabled: $api"
    else
      warn "API not enabled: $api"
    fi
  done
}

maybe_refresh_kubeconfig() {
  if [[ "$GET_CREDENTIALS" != true || -z "$CLUSTER" || -z "$LOCATION" ]]; then
    return
  fi

  section "Refreshing kubeconfig"
  if gcloud container clusters get-credentials "$CLUSTER" --location "$LOCATION" --project "$PROJECT" >/dev/null 2>&1; then
    ok "Updated kubeconfig for ${CLUSTER}"
  else
    fail "Unable to update kubeconfig for ${CLUSTER}"
  fi
}

check_cluster_metadata() {
  section "GKE cluster metadata"

  if [[ -z "$CLUSTER" ]]; then
    local clusters
    clusters="$(gcloud container clusters list --project "$PROJECT" --format='table(name,location,status,currentMasterVersion,releaseChannel.channel)' 2>/dev/null || true)"
    if [[ -n "$clusters" ]]; then
      ok "Cluster inventory retrieved"
      printf '%s\n' "$clusters"
    else
      warn "No clusters found or Container API unavailable"
    fi
    return
  fi

  if [[ -z "$LOCATION" ]]; then
    fail "--location is required when --cluster is specified"
    return
  fi

  local status master_version node_version release_channel workload_pool autopilot private_nodes
  status="$(gcloud container clusters describe "$CLUSTER" --location "$LOCATION" --project "$PROJECT" --format='value(status)' 2>/dev/null || true)"
  master_version="$(gcloud container clusters describe "$CLUSTER" --location "$LOCATION" --project "$PROJECT" --format='value(currentMasterVersion)' 2>/dev/null || true)"
  node_version="$(gcloud container clusters describe "$CLUSTER" --location "$LOCATION" --project="$PROJECT" --format='value(currentNodeVersion)' 2>/dev/null || true)"
  release_channel="$(gcloud container clusters describe "$CLUSTER" --location "$LOCATION" --project="$PROJECT" --format='value(releaseChannel.channel)' 2>/dev/null || true)"
  workload_pool="$(gcloud container clusters describe "$CLUSTER" --location "$LOCATION" --project="$PROJECT" --format='value(workloadIdentityConfig.workloadPool)' 2>/dev/null || true)"
  autopilot="$(gcloud container clusters describe "$CLUSTER" --location "$LOCATION" --project="$PROJECT" --format='value(autopilot.enabled)' 2>/dev/null || true)"
  private_nodes="$(gcloud container clusters describe "$CLUSTER" --location "$LOCATION" --project="$PROJECT" --format='value(privateClusterConfig.enablePrivateNodes)' 2>/dev/null || true)"

  if [[ "$status" == "RUNNING" ]]; then
    ok "Cluster ${CLUSTER} status is RUNNING"
  elif [[ -n "$status" ]]; then
    fail "Cluster ${CLUSTER} status is ${status}"
  else
    fail "Cluster ${CLUSTER} could not be described"
    return
  fi

  info "Master version: ${master_version:-unknown}"
  info "Node version: ${node_version:-unknown}"
  info "Release channel: ${release_channel:-none}"
  info "Autopilot: ${autopilot:-false}"
  info "Private nodes: ${private_nodes:-false}"

  if [[ -n "$workload_pool" ]]; then
    ok "Workload Identity enabled: ${workload_pool}"
  else
    warn "Workload Identity is not enabled"
  fi

  local pools
  pools="$(gcloud container node-pools list --cluster "$CLUSTER" --location "$LOCATION" --project "$PROJECT" --format='table(name,status,version,management.autoRepair,management.autoUpgrade)' 2>/dev/null || true)"
  if [[ -n "$pools" ]]; then
    ok "Node pool inventory retrieved"
    printf '%s\n' "$pools"
  else
    warn "Unable to list node pools"
  fi
}

check_kubectl_access() {
  if [[ "$SKIP_KUBECTL" == true ]]; then
    section "Kubernetes checks"
    warn "Skipping kubectl checks by request"
    return
  fi

  section "Kubernetes checks"
  if ! command -v kubectl >/dev/null 2>&1; then
    warn "kubectl is not installed"
    return
  fi

  if ! kubectl version --request-timeout=10s >/dev/null 2>&1; then
    fail "kubectl cannot reach the cluster"
    return
  fi

  ok "kubectl can reach the cluster"

  local nodes total_nodes not_ready cordoned
  nodes="$(kubectl get nodes --no-headers 2>/dev/null || true)"
  total_nodes="$(safe_count_lines "$nodes")"
  not_ready="$(printf '%s\n' "$nodes" | awk '$2 != "Ready" {count++} END {print count+0}')"
  cordoned="$(printf '%s\n' "$nodes" | awk '$2 == "Ready,SchedulingDisabled" {count++} END {print count+0}')"

  if [[ "$total_nodes" -eq 0 ]]; then
    warn "No nodes returned by kubectl"
  elif [[ "$not_ready" -eq 0 ]]; then
    ok "All ${total_nodes} nodes are Ready"
  else
    fail "${not_ready}/${total_nodes} nodes are not Ready"
    printf '%s\n' "$nodes" | awk '$2 != "Ready"'
  fi

  if [[ "$cordoned" -gt 0 ]]; then
    warn "${cordoned} node(s) are cordoned"
  fi

  local pod_scope problem_pods pending_pods crashloop_pods
  if [[ -n "$NAMESPACE" ]]; then
    pod_scope="-n ${NAMESPACE}"
  else
    pod_scope="-A"
  fi

  problem_pods="$(kubectl get pods ${pod_scope} --no-headers 2>/dev/null | awk '$4 !~ /Running|Completed|Succeeded/ {print}')"
  pending_pods="$(kubectl get pods ${pod_scope} --field-selector=status.phase=Pending --no-headers 2>/dev/null || true)"
  crashloop_pods="$(kubectl get pods ${pod_scope} --no-headers 2>/dev/null | grep -E 'CrashLoopBackOff|Error|ImagePullBackOff' || true)"

  if [[ -z "$problem_pods" ]]; then
    ok "No unhealthy pods detected in scope ${NAMESPACE:-all-namespaces}"
  else
    warn "Pods need attention in scope ${NAMESPACE:-all-namespaces}"
    printf '%s\n' "$problem_pods" | head -20
  fi

  if [[ -n "$pending_pods" ]]; then
    warn "Pending pods detected"
    printf '%s\n' "$pending_pods" | head -10
  fi

  if [[ -n "$crashloop_pods" ]]; then
    warn "CrashLoopBackOff or image pull failures detected"
    printf '%s\n' "$crashloop_pods" | head -10
  fi

  local warnings
  warnings="$(kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp --no-headers 2>/dev/null | tail -10 || true)"
  if [[ -n "$warnings" ]]; then
    warn "Recent warning events found"
    printf '%s\n' "$warnings"
  else
    ok "No recent warning events returned"
  fi
}

check_monitoring_and_logging() {
  section "Observability posture"

  local uptime_count sink_count
  uptime_count="$(gcloud monitoring uptime list-configs --project "$PROJECT" --format='value(name)' 2>/dev/null | wc -l | tr -d ' ' || echo 0)"
  sink_count="$(gcloud logging sinks list --project "$PROJECT" --format='value(name)' 2>/dev/null | wc -l | tr -d ' ' || echo 0)"

  if [[ "$uptime_count" -gt 0 ]]; then
    ok "${uptime_count} uptime check(s) configured"
  else
    warn "No uptime checks found"
  fi

  if [[ "$sink_count" -gt 0 ]]; then
    ok "${sink_count} log sink(s) configured"
  else
    warn "No log sinks found"
  fi

  if [[ "$INCLUDE_LOGS" == true ]]; then
    local recent_errors
    recent_errors="$(gcloud logging read 'severity>=ERROR' --project "$PROJECT" --limit=10 --freshness=1h --format='table(timestamp,resource.type,severity)' 2>/dev/null || true)"
    if [[ -n "$recent_errors" ]]; then
      warn "Recent errors found in Cloud Logging"
      printf '%s\n' "$recent_errors"
    else
      ok "No recent Cloud Logging errors returned for last hour"
    fi
  else
    info "Use --include-logs to print recent Cloud Logging errors"
  fi
}

print_summary() {
  section "Summary"
  printf 'Pass: %s\n' "$PASS_COUNT"
  printf 'Warn: %s\n' "$WARN_COUNT"
  printf 'Fail: %s\n' "$FAIL_COUNT"

  if [[ "$FAIL_COUNT" -gt 0 ]]; then
    printf '${RED}Health check finished with failures.${NC}\n'
    exit 1
  fi

  if [[ "$WARN_COUNT" -gt 0 ]]; then
    printf '${YELLOW}Health check finished with warnings.${NC}\n'
    exit 0
  fi

  printf '${GREEN}Health check finished cleanly.${NC}\n'
}

main() {
  parse_args "$@"
  require_cmd gcloud

  printf '==============================================\n'
  printf ' GCP Health Check — %s\n' "$(date)"
  printf ' Project: %s\n' "${PROJECT:-unset}"
  if [[ -n "$CLUSTER" ]]; then
    printf ' Cluster: %s\n' "$CLUSTER"
  fi
  printf '==============================================\n'

  check_auth
  check_services
  maybe_refresh_kubeconfig
  check_cluster_metadata
  check_kubectl_access
  check_monitoring_and_logging
  print_summary
}

main "$@"
