# MIT License
#
# (C) Copyright 2025 Hewlett Packard Enterprise Development LP
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

build-image-rh9()
{
    if [ -z "$1" ]; then
        echo 'Path to image config file required.' 1>&2;
        return 1;
    fi;
    if [ ! -f "$1" ]; then
        echo "$1 does not exist." 1>&2;
        return 1;
    fi;
    podman run \
            --rm \
            --device /dev/fuse \
            -e S3_ACCESS=admin \
            -e S3_SECRET=admin123 \
            -v "$(realpath $1)":/home/builder/config.yaml:Z \
            ${EXTRA_PODMAN_ARGS} \
            ghcr.io/openchami/image-build-el9:v0.1.1 \
            image-build \
                --config config.yaml \
                --log-level DEBUG
}

build-image-rh8()
{
    if [ -z "$1" ]; then
        echo 'Path to image config file required.' 1>&2;
        return 1;
    fi;
    if [ ! -f "$1" ]; then
        echo "$1 does not exist." 1>&2;
        return 1;
    fi;
    podman run \
           --rm \
           --device /dev/fuse \
           -e S3_ACCESS=admin \
           -e S3_SECRET=admin123 \
           -v "$(realpath $1)":/home/builder/config.yaml:Z \
           ${EXTRA_PODMAN_ARGS} \
           ghcr.io/openchami/image-build:v0.1.0 \
           image-build \
                --config config.yaml \
                --log-level DEBUG
}
alias build-image=build-image-rh9
