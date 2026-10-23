#!/bin/bash
set -euo pipefail
exec python3 scripts/capture-iphone-ui.py "${1:?Use before or after}"
