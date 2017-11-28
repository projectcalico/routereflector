#!/usr/bin/env bash
set -e
source /build/buildconfig
set -x

# Upgrade all packages.
apt-get update
apt-get dist-upgrade -y --no-install-recommends

# Determine the list of packages required for the base image.
dpkg -l | grep ^ii | sed 's_  _\t_g' | cut -f 2 >/tmp/base.txt

# Install HTTPS support for APT.
$minimal_apt_get_install apt-transport-https ca-certificates

# Install add-apt-repository
$minimal_apt_get_install software-properties-common

# Add new repos and update again
LC_ALL=C.UTF-8 LANG=C.UTF-8 add-apt-repository -y ppa:cz.nic-labs/bird
apt-get update

# Install packages that should not be removed in the cleanup processing.
# - bird and bird6 are both included with the bird package.
# - packages required by felix
# - pip (which includes various setuptools package discovery).

$minimal_apt_get_install \
	bird

# Create the config directory for confd
mkdir config
