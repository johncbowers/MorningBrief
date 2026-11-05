#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swiftc -module-cache-path /tmp/morning-brief-module-cache Sources/BriefingCore.swift Tests/main.swift -o /tmp/morning-brief-tests
/tmp/morning-brief-tests
