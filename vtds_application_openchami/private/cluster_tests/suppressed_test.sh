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
set -e -o pipefail

main() {
    # Arguments are 'name' is the test name from the config,
    # 'description' is the test description from the config, 'timeout'
    # is the timeout in seconds from the config, 'config' is the path
    # to the application layer configuration file used for this
    # deployment.
    local test_name="${1}"; shift || usage "missing test name"
    local test_description="${1}"; shift || usage "missing test description"

    echo "TEST_NAME: ${test_name}"
    echo "TEST_DESCRIPTION: ${test_description}"
    echo "TEST_RESULT: SUPPRESSED"
    echo "TEST_DEPENDENCIES_FAILED: $@"
}

main "$@"
