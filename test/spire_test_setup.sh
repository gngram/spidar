#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# spire_test_setup.sh
#
# Starts the Admin SPIRE Server + Agent (admin.app) and two federated test
# servers + agents (domain-a.test, domain-b.test), all using https_web for
# their federation bundle endpoints.
#
# A shared local CA is generated once and referenced directly in each server's
# TLS config — no system trust store modification required.
# =============================================================================

SCRIPT_NAME="$(basename "$0")"

# ── Defaults ──────────────────────────────────────────────────────────────────

DATA_ROOT=""
ADMIN_SERVER_PORT=8081
ADMIN_BUNDLE_PORT=8445
DOMAIN_A_SERVER_PORT=8082
DOMAIN_B_SERVER_PORT=8083
DOMAIN_A_BUNDLE_PORT=8446
DOMAIN_B_BUNDLE_PORT=8447
CLEAN_ONLY=false

# ── Help / Usage ─────────────────────────────────────────────────────────────

print_help() {
  cat <<EOF
Usage:
  $SCRIPT_NAME [DATA_DIRECTORY] [OPTIONS]
  $SCRIPT_NAME -d <DATA_DIRECTORY> [OPTIONS]

Starts a local multi-domain SPIRE testing environment with an Admin Server/Agent
(admin.app) and two federated servers/agents (domain-a.test and domain-b.test).

Arguments:
  DATA_DIRECTORY                   Path to the directory where runtime configs,
                                   databases, and socket files will be stored.
                                   Can be specified positionally or via -d/--data-dir.

Options:
  -d, --data-dir <path>            Directory path for test data and sockets
  --admin-server-port <port>       Admin server gRPC port         (default: 8081)
  --admin-bundle-port <port>       Admin bundle endpoint port     (default: 8445)
  --domain-a-server-port <port>    Domain A server gRPC port      (default: 8082)
  --domain-b-server-port <port>    Domain B server gRPC port      (default: 8083)
  --domain-a-bundle-port <port>    Domain A bundle endpoint port  (default: 8446)
  --domain-b-bundle-port <port>    Domain B bundle endpoint port  (default: 8447)
  -c, --clean                      Clean up existing test data & processes and exit
  -h, --help                       Display this help message and exit

Examples:
  # Start with default ports using positional data directory
  $SCRIPT_NAME /tmp/spire-data

  # Start with custom data directory and custom Admin port
  $SCRIPT_NAME --data-dir /tmp/spire-data --admin-server-port 9081

  # Customize federated domain ports
  $SCRIPT_NAME /tmp/spire-data --domain-a-server-port 8182 --domain-b-server-port 8183

  # Clean up test environment data and running SPIRE instances
  $SCRIPT_NAME -d /tmp/spire-data --clean
EOF
}

# ── Helper Functions ──────────────────────────────────────────────────────────

log() { echo "[$(date '+%H:%M:%S')] $*"; }
die() { echo "[ERROR] $*" >&2; exit 1; }

validate_port() {
  local port_val="$1"
  local port_name="$2"
  if ! [[ "$port_val" =~ ^[0-9]+$ ]] || [ "$port_val" -lt 1024 ] || [ "$port_val" -gt 65535 ]; then
    die "Invalid value for ${port_name}: '${port_val}'. Must be an integer between 1024 and 65535."
  fi
}

# ── Argument Parsing ──────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      print_help
      exit 0
      ;;
    -d|--data-dir)
      if [[ -z "${2:-}" || "$2" == -* ]]; then
        die "Option '$1' requires a directory path argument."
      fi
      DATA_ROOT="$2"
      shift 2
      ;;
    --admin-server-port)
      if [[ -z "${2:-}" || "$2" == -* ]]; then
        die "Option '$1' requires a port argument."
      fi
      ADMIN_SERVER_PORT="$2"
      shift 2
      ;;
    --admin-bundle-port)
      if [[ -z "${2:-}" || "$2" == -* ]]; then
        die "Option '$1' requires a port argument."
      fi
      ADMIN_BUNDLE_PORT="$2"
      shift 2
      ;;
    --domain-a-server-port)
      if [[ -z "${2:-}" || "$2" == -* ]]; then
        die "Option '$1' requires a port argument."
      fi
      DOMAIN_A_SERVER_PORT="$2"
      shift 2
      ;;
    --domain-b-server-port)
      if [[ -z "${2:-}" || "$2" == -* ]]; then
        die "Option '$1' requires a port argument."
      fi
      DOMAIN_B_SERVER_PORT="$2"
      shift 2
      ;;
    --domain-a-bundle-port)
      if [[ -z "${2:-}" || "$2" == -* ]]; then
        die "Option '$1' requires a port argument."
      fi
      DOMAIN_A_BUNDLE_PORT="$2"
      shift 2
      ;;
    --domain-b-bundle-port)
      if [[ -z "${2:-}" || "$2" == -* ]]; then
        die "Option '$1' requires a port argument."
      fi
      DOMAIN_B_BUNDLE_PORT="$2"
      shift 2
      ;;
    -c|--clean)
      CLEAN_ONLY=true
      shift 1
      ;;
    -*)
      echo "Unknown option: $1" >&2
      echo "Run '$SCRIPT_NAME --help' for usage." >&2
      exit 1
      ;;
    *)
      if [[ -z "$DATA_ROOT" ]]; then
        DATA_ROOT="$1"
        shift 1
      else
        die "Unexpected positional argument: '$1'. Data directory already set to '$DATA_ROOT'."
      fi
      ;;
  esac
done

# ── Validation ────────────────────────────────────────────────────────────────

if [[ -z "$DATA_ROOT" ]]; then
  echo "Error: Data directory path is required." >&2
  echo "Run '$SCRIPT_NAME --help' for usage." >&2
  exit 1
fi

validate_port "$ADMIN_SERVER_PORT"   "--admin-server-port"
validate_port "$ADMIN_BUNDLE_PORT"   "--admin-bundle-port"
validate_port "$DOMAIN_A_SERVER_PORT" "--domain-a-server-port"
validate_port "$DOMAIN_B_SERVER_PORT" "--domain-b-server-port"
validate_port "$DOMAIN_A_BUNDLE_PORT" "--domain-a-bundle-port"
validate_port "$DOMAIN_B_BUNDLE_PORT" "--domain-b-bundle-port"

# Check for duplicate port assignments
declare -A PORT_MAP
for p in "$ADMIN_SERVER_PORT:admin-server" \
         "$ADMIN_BUNDLE_PORT:admin-bundle" \
         "$DOMAIN_A_SERVER_PORT:domain-a-server" \
         "$DOMAIN_B_SERVER_PORT:domain-b-server" \
         "$DOMAIN_A_BUNDLE_PORT:domain-a-bundle" \
         "$DOMAIN_B_BUNDLE_PORT:domain-b-bundle"; do
  port="${p%%:*}"
  service="${p##*:}"
  if [[ -n "${PORT_MAP[$port]:-}" ]]; then
    die "Port collision detected: port $port is assigned to both '${PORT_MAP[$port]}' and '$service'."
  fi
  PORT_MAP["$port"]="$service"
done

# ── Derived paths ─────────────────────────────────────────────────────────────

# Convert DATA_ROOT to absolute path if relative
if [[ ! "$DATA_ROOT" = /* ]]; then
  DATA_ROOT="$(pwd)/$DATA_ROOT"
fi

ADMIN_DIR="${DATA_ROOT}/spire-admin"
TEST_DIR="${DATA_ROOT}/spire-test-servers"
BUNDLES_DIR="${TEST_DIR}/trust_bundles"
ADMIN_SOCK="${ADMIN_DIR}/server.sock"

# ── Clean-Only Handling ───────────────────────────────────────────────────────

if [ "$CLEAN_ONLY" = true ]; then
  log "Stopping any running SPIRE processes..."
  killall spire-server spire-agent 2>/dev/null || true
  log "Removing data directory: ${DATA_ROOT}"
  rm -rf "${ADMIN_DIR}" "${TEST_DIR}"
  log "Cleanup complete."
  exit 0
fi

# =============================================================================
# SHARED HELPERS
# =============================================================================

check_deps() {
  command -v spire-server &>/dev/null || die "spire-server not found in PATH"
  command -v spire-agent  &>/dev/null || die "spire-agent not found in PATH"
  command -v openssl      &>/dev/null || die "openssl not found in PATH"
}

wait_for_server() {
  local sock="$1" label="$2"
  local output
  log "Waiting for ${label} to be ready..."
  for i in $(seq 1 20); do
    output=$(spire-server bundle show -socketPath "$sock" 2>/dev/null) || true
    if [[ -n "$output" ]]; then
      return 0
    fi
    sleep 1
  done
  die "${label} did not become ready — check logs in ${DATA_ROOT}"
}

# =============================================================================
# ADMIN — admin.app server + agent
# =============================================================================

cleanup_admin() {
  log "Cleaning up previous admin data..."
  killall spire-server spire-agent 2>/dev/null || true
  rm -rf "${ADMIN_DIR}" 
  mkdir -p "${ADMIN_DIR}"
}

write_admin_server_config() {
  cat <<EOF > "${ADMIN_DIR}/admin-server.conf"
server {
    bind_address = "127.0.0.1"
    bind_port = ${ADMIN_SERVER_PORT}
    socket_path = "${ADMIN_SOCK}"
    trust_domain = "admin.app"
    admin_ids = ["spiffe://admin.app/spire_admin"]
    data_dir = "${ADMIN_DIR}/admin-server-data"
    log_level = "INFO"
    federation {
        bundle_endpoint {
            address = "127.0.0.1"
            port = ${ADMIN_BUNDLE_PORT}
        }
        federates_with "domain-a.test" {
            bundle_endpoint_url = "https://127.0.0.1:${DOMAIN_A_BUNDLE_PORT}"
            bundle_endpoint_profile "https_spiffe" {
                endpoint_spiffe_id = "spiffe://domain-a.test/spire/server"
            }
        }
        federates_with "domain-b.test" {
            bundle_endpoint_url = "https://127.0.0.1:${DOMAIN_B_BUNDLE_PORT}"
            bundle_endpoint_profile "https_spiffe" {
                endpoint_spiffe_id = "spiffe://domain-b.test/spire/server"
            }
        }
    }
}
plugins {
    DataStore "sql" { plugin_data { database_type = "sqlite3", connection_string = "${ADMIN_DIR}/admin-server-data/datastore.sqlite3" } }
    KeyManager "disk" { plugin_data { keys_path = "${ADMIN_DIR}/admin-server-data/keys.json" } }
    NodeAttestor "join_token" { plugin_data {} }
}
EOF
}

write_admin_agent_config() {
  cat <<EOF > "${ADMIN_DIR}/admin-agent.conf"
agent {
    data_dir = "${ADMIN_DIR}/admin-agent-data"
    log_level = "INFO"
    server_address = "127.0.0.1"
    server_port = ${ADMIN_SERVER_PORT}
    socket_path = "${ADMIN_DIR}/agent.sock"
    trust_domain = "admin.app"
    trust_bundle_path = "${BUNDLES_DIR}/admin-server.pem"
}
plugins {
    NodeAttestor "join_token" { plugin_data {} }
    KeyManager "disk" { plugin_data { directory = "${ADMIN_DIR}/admin-agent-data" } }
    WorkloadAttestor "unix" { plugin_data {} }
}
EOF
}

start_admin_server() {
  log "Starting Admin SPIRE Server..."
  spire-server run -config "${ADMIN_DIR}/admin-server.conf" \
    > "${ADMIN_DIR}/admin-server.log" 2>&1 &
  PID_ADMIN=$!

  wait_for_server "$ADMIN_SOCK" "Admin Server (admin.app)"
}

start_admin_agent() {
  log "Starting Admin Agent..."
  local token
  token=$(spire-server token generate \
    -socketPath "$ADMIN_SOCK" \
    -spiffeID   "spiffe://admin.app/admin-agent" \
    | awk '{print $2}')

  log "Creating workload entry for spire_admin..."
  spire-server entry create \
    -socketPath "$ADMIN_SOCK" \
    -parentID   spiffe://admin.app/admin-agent \
    -spiffeID   spiffe://admin.app/spire_admin \
    -selector   "unix:uid:$(id -u)" \
    -admin \
    -federatesWith spiffe://domain-a.test \
    -federatesWith spiffe://domain-b.test \
    > /dev/null

  spire-agent run \
    -config    "${ADMIN_DIR}/admin-agent.conf" \
    -joinToken "$token" \
    > "${ADMIN_DIR}/admin-agent.log" 2>&1 &
}

# =============================================================================
# TEST — domain-a.test + domain-b.test servers and agents
# =============================================================================

cleanup_test() {
  log "Cleaning up previous test data..."
  rm -rf "${TEST_DIR}/test-server-a"* \
         "${TEST_DIR}/test-server-b"* \
         "${TEST_DIR}/test-agent-a"*  \
         "${TEST_DIR}/test-agent-b"*  \
         "${BUNDLES_DIR}"
  mkdir -p "${TEST_DIR}" "${BUNDLES_DIR}"
}

write_test_server_config() {
  local letter="$1" server_port="$2" bundle_port="$3"
  local domain="domain-${letter}.test"

  cat <<EOF > "${TEST_DIR}/test-server-${letter}.conf"
server {
    bind_address = "127.0.0.1"
    bind_port = ${server_port}
    socket_path = "${TEST_DIR}/test-server-${letter}.sock"
    trust_domain = "${domain}"
    admin_ids = ["spiffe://admin.app/spire_admin"]
    data_dir = "${TEST_DIR}/test-server-${letter}-data"
    log_level = "INFO"
    federation {
        bundle_endpoint {
            address = "127.0.0.1"
            port = ${bundle_port}
        }
        federates_with "admin.app" {
            bundle_endpoint_url = "https://127.0.0.1:${ADMIN_BUNDLE_PORT}"
            bundle_endpoint_profile "https_spiffe" {
                endpoint_spiffe_id = "spiffe://admin.app/spire/server"
            }
        }
    }
}
plugins {
    DataStore "sql" { plugin_data { database_type = "sqlite3", connection_string = "${TEST_DIR}/test-server-${letter}-data/datastore.sqlite3" } }
    KeyManager "disk" { plugin_data { keys_path = "${TEST_DIR}/test-server-${letter}-data/keys.json" } }
    NodeAttestor "join_token" { plugin_data {} }
}
EOF
}

write_test_agent_config() {
  local letter="$1" server_port="$2"
  local domain="domain-${letter}.test"

  cat <<EOF > "${TEST_DIR}/test-agent-${letter}.conf"
agent {
    data_dir = "${TEST_DIR}/test-agent-${letter}-data"
    log_level = "INFO"
    server_address = "127.0.0.1"
    server_port = ${server_port}
    socket_path = "${TEST_DIR}/test-agent-${letter}.sock"
    trust_domain = "${domain}"
    trust_bundle_path = "${BUNDLES_DIR}/test-server-${letter}.pem"
}
plugins {
    NodeAttestor "join_token" { plugin_data {} }
    KeyManager "disk" { plugin_data { directory = "${TEST_DIR}/test-agent-${letter}-data" } }
    WorkloadAttestor "unix" { plugin_data {} }
}
EOF
}

start_test_servers() {
  log "Starting federated SPIRE Servers..."
  spire-server run -config "${TEST_DIR}/test-server-a.conf" \
    > "${TEST_DIR}/test-server-a.log" 2>&1 &
  spire-server run -config "${TEST_DIR}/test-server-b.conf" \
    > "${TEST_DIR}/test-server-b.log" 2>&1 &

  wait_for_server "${TEST_DIR}/test-server-a.sock" "Server A (domain-a.test)"
  wait_for_server "${TEST_DIR}/test-server-b.sock" "Server B (domain-b.test)"
}

generate_trust_bundle() {
  spire-server bundle show -socketPath "${TEST_DIR}/test-server-a.sock" \
    > "${BUNDLES_DIR}/test-server-a.pem"
  spire-server bundle show -socketPath "${TEST_DIR}/test-server-b.sock" \
    > "${BUNDLES_DIR}/test-server-b.pem"
  spire-server bundle show -socketPath "${ADMIN_SOCK}" \
    > "${BUNDLES_DIR}/admin-server.pem"
}

bootstrap_federation() {
  # test-server-a and test-server-b have `federates_with "admin.app"` in their
  # config and share the same local CA for TLS, so they fetch admin.app's
  # bundle automatically on startup — no manual seeding needed in that direction.
  #
  # Admin server has no `federates_with` entries for the test domains, so it
  # has no way to auto-discover them. We push their bundles in manually once.
  log "Pushing admin server bundles into domain-a.test and domain-b.test ..."
  spire-server bundle set \
    -socketPath "${TEST_DIR}/test-server-a.sock" \
    -id         "spiffe://admin.app" \
    -format     pem \
    -path       "${BUNDLES_DIR}/admin-server.pem"

  spire-server bundle set \
    -socketPath "${TEST_DIR}/test-server-b.sock" \
    -id         "spiffe://admin.app" \
    -format     pem \
    -path       "${BUNDLES_DIR}/admin-server.pem"

  log "Pushing domain-a.test and domain-b.test bundles into admin server..."
  spire-server bundle set \
    -socketPath "$ADMIN_SOCK" \
    -id         "spiffe://domain-a.test" \
    -format     pem \
    -path       "${BUNDLES_DIR}/test-server-a.pem"

  spire-server bundle set \
    -socketPath "$ADMIN_SOCK" \
    -id         "spiffe://domain-b.test" \
    -format     pem \
    -path       "${BUNDLES_DIR}/test-server-b.pem"
}

start_test_agents() {
  log "Registering workloads and starting test agents..."
  for letter in a b; do
    local sock="${TEST_DIR}/test-server-${letter}.sock"
    local domain="domain-${letter}.test"

    spire-server entry create \
      -socketPath "$sock" \
      -parentID   "spiffe://$domain/test-agent-${letter}" \
      -spiffeID   "spiffe://$domain/workload-${letter}" \
      -selector   "unix:uid:$(id -u)" \
      > /dev/null

    local token
    token=$(spire-server token generate \
      -socketPath "$sock" \
      -spiffeID   "spiffe://$domain/test-agent-${letter}" \
      | awk '{print $2}')

    spire-agent run \
      -config    "${TEST_DIR}/test-agent-${letter}.conf" \
      -joinToken "$token" \
      > "${TEST_DIR}/test-agent-${letter}.log" 2>&1 &
  done
}

setup_admin_server() {
  log "=== Setting up Admin (admin.app) ==="
  write_admin_server_config
  start_admin_server
}

setup_admin_agent() {
  log "=== Setting up Admin Agent ==="
  write_admin_agent_config
  start_admin_agent
}

setup_test_server() {
  log "=== Setting up Test Servers (domain-a.test, domain-b.test) ==="
  write_test_server_config "a" "${DOMAIN_A_SERVER_PORT}" "${DOMAIN_A_BUNDLE_PORT}"
  write_test_server_config "b" "${DOMAIN_B_SERVER_PORT}" "${DOMAIN_B_BUNDLE_PORT}"
  start_test_servers
}

setup_test_agents() {
  log "=== Setting up Test Agents (domain-a.test, domain-b.test) ==="
  write_test_agent_config  "a" "${DOMAIN_A_SERVER_PORT}"
  write_test_agent_config  "b" "${DOMAIN_B_SERVER_PORT}"
  start_test_agents
}

# =============================================================================
# SUMMARY
# =============================================================================

print_summary() {
  echo ""
  echo "======================================================================="
  echo "✅ SPIRE environment is up and running!"
  echo ""
  echo "  Admin (admin.app)"
  echo "    gRPC:            127.0.0.1:${ADMIN_SERVER_PORT}"
  echo "    Bundle endpoint: https://127.0.0.1:${ADMIN_BUNDLE_PORT}  (https_web)"
  echo "    Workload:        spiffe://admin.app/spire_admin"
  echo "    Logs:            ${ADMIN_DIR}/admin-server.log"
  echo "                     ${ADMIN_DIR}/admin-agent.log"
  echo ""
  echo "  Server A (domain-a.test)"
  echo "    gRPC:            127.0.0.1:${DOMAIN_A_SERVER_PORT}"
  echo "    Bundle endpoint: https://127.0.0.1:${DOMAIN_A_BUNDLE_PORT}  (https_web)"
  echo "    Workload:        spiffe://domain-a.test/workload-a"
  echo "    Logs:            ${TEST_DIR}/test-server-a.log"
  echo "                     ${TEST_DIR}/test-agent-a.log"
  echo ""
  echo "  Server B (domain-b.test)"
  echo "    gRPC:            127.0.0.1:${DOMAIN_B_SERVER_PORT}"
  echo "    Bundle endpoint: https://127.0.0.1:${DOMAIN_B_BUNDLE_PORT}  (https_web)"
  echo "    Workload:        spiffe://domain-b.test/workload-b"
  echo "    Logs:            ${TEST_DIR}/test-server-b.log"
  echo "                     ${TEST_DIR}/test-agent-b.log"
  echo ""
  echo "======================================================================="
}

# =============================================================================
# ENTRYPOINT
# =============================================================================

main() {
  check_deps

  trap "
    log 'Shutting down all SPIRE processes...'
    kill \$(jobs -p) 2>/dev/null || true
  " EXIT INT TERM

  cleanup_admin
  setup_admin_server
  cleanup_test
  setup_test_server
  generate_trust_bundle
  bootstrap_federation
  setup_admin_agent
  setup_test_agents
  print_summary
  wait
}

main "$@"
