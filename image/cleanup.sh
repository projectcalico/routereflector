#!/bin/bash
set -e
set -x

# Remove any other junk created during installation that is not required.
apt-get clean
rm -rf /build
rm -rf /tmp/* /var/tmp/*
rm -rf /var/lib/apt/lists/*
rm -f /etc/dpkg/dpkg.cfg.d/02apt-speedup
