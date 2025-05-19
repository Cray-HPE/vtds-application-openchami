#! /usr/bin/bash
set -e -o pipefail

./OpenCHAMI-Prepare.sh
while ! ./OpenCHAMI-Deploy.sh; do
    ./OpenCHAMI-Remove.sh
done
./OpenCHAMI-Show.sh
