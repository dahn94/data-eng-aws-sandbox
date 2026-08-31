#!/usr/bin/env bash
# Destrói o cluster local. Os PVCs vão junto — é o `terraform destroy` deste lado.
set -euo pipefail
kind delete cluster --name dataeng
