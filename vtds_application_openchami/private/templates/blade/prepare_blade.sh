#! /usr/bin/bash
#
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
set -e -o pipefail

# Create the directory in /etc where all of the Sushy Tools setup will
# go.
mkdir -p /etc/sushy-emulator
chmod 700 /etc/sushy-emulator

# Make self-signed X509 cert / key for the sushy-emulator
openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
        -keyout /etc/sushy-emulator/key.pem \
        -out /etc/sushy-emulator/cert.pem \
        -subj "/C=US/ST=SushyTools/L=Vtds/O=vTDS/CN=vtds"

# Create an htpasswd file for the sushy-emulator to use
{% for network in discovery_networks %}
{% if network.external %}
htpasswd -B -b -c /etc/sushy-emulator/users \
         {{ network.redfish_username }} \
         {{ network.redfish_password }}
{% endif %}
{% endfor %}

# Put the nginx HTTPS reverse proxy configuration into
# the nginx configuration directory
cp /root/nginx-default-site-config /etc/nginx/sites-available/default

# Put the sushy-emulator config away where it belongs...
cp /root/sushy-emulator.conf /etc/sushy-emulator/config

# Put the systemd unit file for sushy-emulator where it belongs
cp /root/sushy-emulator.service /etc/systemd/system/sushy-emulator.service

# Start up the sushy-emulator
systemctl daemon-reload
systemctl enable --now sushy-emulator
systemctl enable --now nginx
