#
# MIT License
#
# (C) Copyright 2026 Hewlett Packard Enterprise Development LP
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
source ~/openchami-files/prep_setup.sh

# Get the directory the script resides in so we can find other test
# files.
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    msg="${1}\n"; shift || msg=""
    printf "$msg" >&2
    echo "usage: driver.sh entrypoint name desc timeout" >&2
    echo "    where:" >&2
    echo "       'entrypoint' is the path to the test entrypoint" >&2
    echo "       'name' is the test name" >&2
    echo "       'desc' is the test description" >&2
    echo "       'timeout' is a timeout value in seconds for the test run" >&2
    exit 1
}

function start() {
    local entry="${1}"; shift || usage "missing test entrypoint"
    local name="${1}"; shift || usage "missing test name"
    local desc="${1}"; shift || usage "missing test description"
    local timeout="${1}"; shift || usage "missing test timeout value"

    # Capture test (combined) output in a temporary file for later
    # presentation.
    output=$(mktemp)
    
    echo "TEST_NAME: ${name}"
    echo "TEST_DESCRIPTION: ${desc}"
    echo "TEST_ENTRYPOINT: ${entry}"
    # Okay, this is some weirdly ugly bash code. What it does is run
    # "main" under "timeout" in an explicit sub-bash process and
    # capture the exit status of the bash command so we can tell if it
    # exited with a timeout or not.
    if timeout "${timeout}" "${entry}" "${name}" "${desc}" > ${output} 2>&1
       local retval="$?"; [ "${retval}" -eq 124 ]; then
	echo "TEST_RESULT: FAILURE"
    elif [ "${retval}" -ne 0 ]; then
	echo "TEST_RESULT: FAILURE"
    else
        echo "TEST_RESULT: SUCCESS"
    fi
    if [ "${retval}" -eq 124 ]; then
        echo "TEST_TIMEOUT: '${name}' timed out after ${timeout} seconds"
    fi
    echo "======== Test Output ========"
    cat "${output}"
    return "${retval}"
}

start "${@}"
