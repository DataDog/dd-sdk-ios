#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TLA_JAR="${1:-${TLA_TOOLS_JAR:-}}"

if [[ -z "${TLA_JAR}" || ! -f "${TLA_JAR}" ]]; then
  echo "usage: $0 /path/to/tla2tools.jar" >&2
  exit 2
fi

run_known_counterexample() {
  local module="$1"
  local config="$2"
  local output
  local status
  local metadata_dir

  metadata_dir="$(mktemp -d)"

  set +e
  output="$(java -XX:+UseParallelGC -cp "${TLA_JAR}" tlc2.TLC \
    -workers 1 -noGenerateSpecTE -metadir "${metadata_dir}" \
    -config "${SCRIPT_DIR}/${config}" "${SCRIPT_DIR}/${module}" 2>&1)"
  status=$?
  set -e
  rm -rf "${metadata_dir}"

  if [[ ${status} -eq 0 ]]; then
    echo "ERROR: ${config} unexpectedly satisfied its contract" >&2
    echo "${output}" >&2
    return 1
  fi

  if [[ "${output}" != *"Error: Invariant"* && "${output}" != *"Error: Temporal properties were violated"* ]]; then
    echo "ERROR: ${config} failed for the wrong reason" >&2
    echo "${output}" >&2
    return 1
  fi

  echo "known counterexample confirmed: ${config}"
}

run_known_counterexample MessageBusLifecycle.tla MessageBusLateConfiguration.cfg
run_known_counterexample MessageBusLifecycle.tla MessageBusMissingCoreFallback.cfg
run_known_counterexample DataStoreCallback.tla DataStoreCallback.cfg
run_known_counterexample UploadTeardown.tla UploadTeardownRetry.cfg
run_known_counterexample ClientStatsFlush.tla ClientStatsFlush.cfg
run_known_counterexample RemoteConfigurationLifecycle.tla RemoteConfigurationStop.cfg
run_known_counterexample RemoteConfigurationLifecycle.tla RemoteConfigurationOutOfOrder.cfg
run_known_counterexample CoreFlushBound.tla CoreFlushFifthRound.cfg
run_known_counterexample TimeseriesFlush.tla TimeseriesFlush.cfg
run_known_counterexample UploadRetryIdentity.tla UploadRetryIdentity.cfg
