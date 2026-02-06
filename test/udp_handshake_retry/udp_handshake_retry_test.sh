#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${TEST_DIR}/../.." && pwd)"
IPERF3="${ROOT_DIR}/src/iperf3"

if [[ ! -x "${IPERF3}" ]]; then
  echo "Missing built binary: ${IPERF3}" >&2
  echo "Run: make -j\$(nproc)" >&2
  exit 1
fi

have_timeout() { command -v timeout >/dev/null 2>&1; }

TIMEOUT_SECS="${IPERF_TEST_TIMEOUT_SECS:-35}"

pick_port() {
  local start end port
  start=$(( (RANDOM % 10000) + 40000 ))
  end=$(( start + 200 ))
  for ((port=start; port<=end; port++)); do
    if command -v ss >/dev/null 2>&1; then
      if ! ss -lntu "( sport = :${port} )" | tail -n +2 | grep -q .; then
        echo "${port}"
        return 0
      fi
    else
      echo "${port}"
      return 0
    fi
  done
  echo "Failed to find free port" >&2
  return 1
}

TMPDIR="$(mktemp -d)"
cleanup() { rm -rf "${TMPDIR}"; }
trap cleanup EXIT

SHIM_SO="${TMPDIR}/udp_connect_shim.so"
cc -shared -fPIC -O2 -Wall -Wextra -o "${SHIM_SO}" "${TEST_DIR}/udp_connect_shim.c" -ldl

PORT="$(pick_port)"

run_server_client() {
  local server_env client_env client_args server_pid
  server_env="$1"
  client_env="$2"
  client_args="$3"

  # shellcheck disable=SC2086
  eval ${server_env} "${IPERF3}" -s -1 -p "${PORT}" >"${TMPDIR}/server.out" 2>&1 &
  server_pid=$!
  sleep 0.2

  if have_timeout; then
    # shellcheck disable=SC2086
    set +e
    eval ${client_env} timeout "${TIMEOUT_SECS}"s "${IPERF3}" -c 127.0.0.1 -p "${PORT}" ${client_args} >"${TMPDIR}/client.out" 2>&1
    client_rc=$?
    set -e
  else
    # shellcheck disable=SC2086
    set +e
    eval ${client_env} "${IPERF3}" -c 127.0.0.1 -p "${PORT}" ${client_args} >"${TMPDIR}/client.out" 2>&1
    client_rc=$?
    set -e
  fi

  wait "${server_pid}" || true

  if [[ ${client_rc} -ne 0 ]]; then
    echo "FAIL: client exit code ${client_rc}" >&2
    echo "--- client.out ---" >&2
    sed -n '1,200p' "${TMPDIR}/client.out" >&2
    echo "--- server.out ---" >&2
    sed -n '1,200p' "${TMPDIR}/server.out" >&2
    exit 1
  fi

  if grep -q "unable to read from stream socket" "${TMPDIR}/client.out"; then
    echo "FAIL: client saw stream socket read error" >&2
    sed -n '1,200p' "${TMPDIR}/client.out" >&2
    sed -n '1,200p' "${TMPDIR}/server.out" >&2
    exit 1
  fi
}

echo "== baseline UDP -P4 =="
run_server_client "" "" "-u -b 10M -t 1 -P 4"

echo "== drop first CONNECT_MSG (client) =="
run_server_client "" \
  "IPERF_SHIM_DROP_FIRST_UDP_4B_WRITE=1 LD_PRELOAD=${SHIM_SO}" \
  "-u -b 10M -t 1 -P 4"

echo "== drop first CONNECT_REPLY (server) =="
run_server_client \
  "IPERF_SHIM_DROP_FIRST_UDP_4B_WRITE=1 LD_PRELOAD=${SHIM_SO}" \
  "" \
  "-u -b 10M -t 1 -P 4"

echo "== inject late CONNECT_MSG during test =="
run_server_client "" \
  "IPERF_SHIM_INJECT_UDP_CONNECT_MSG_AFTER_FIRST_DATA_WRITE=1 LD_PRELOAD=${SHIM_SO}" \
  "-u -b 10M -t 1 -P 1"

echo "== reverse UDP -R -P4 =="
run_server_client "" "" "-u -R -b 10M -t 1 -P 4"

echo "PASS: UDP handshake retry tests"
