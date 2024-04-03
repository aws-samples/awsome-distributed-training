#!/bin/bash

set -exuo pipefail

# Don't let new lustre client module brings in new kernel.
echo "lustre-client-modules-aws hold" | sudo dpkg --set-selections
