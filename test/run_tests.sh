#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -x "${ROOT_DIR}/src/iperf3" ]]; then
  echo "Building iperf3..." >&2
  make -C "${ROOT_DIR}" -j"$(nproc)"
fi

status=0
while IFS= read -r -d '' t; do
  rel="${t#${ROOT_DIR}/}"
  echo "Running ${rel}"
  if ! bash "${t}"; then
    status=1
  fi
done < <(find "${ROOT_DIR}/test" -type f -name '*_test.sh' -print0 | sort -z)

exit "${status}"
