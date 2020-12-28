#!/bin/sh -eux

# should output one of 'redhat' 'centos' 'oraclelinux'
distro="$(rpm -qf --queryformat '%{NAME}' /etc/redhat-release | cut -f 1 -d '-')"

# should output one of '7' '8'
major_version="$(sed 's/^.\+ release \([.0-9]\+\).*/\1/' /etc/redhat-release | awk -F. '{print $1}')"

# make sure we use dnf on EL 8+
if [ "$major_version" -ge 8 ]; then
  pkg_cmd="dnf"
else
  pkg_cmd="yum"
fi

# remove orphaned & oldkernels
if [ "$major_version" -ge 8 ]; then
  echo "Remove orphaned packages"
  dnf -y autoremove
  echo "Remove previous kernels that preserved for rollbacks"
  dnf -y remove -y $(dnf repoquery --installonly --latest-limit=-1 -q)
else
  echo "Remove previous kernels that preserved for rollbacks"
  if ! command -v package-cleanup >/dev/null 2>&1; then
    yum -y install yum-utils
  fi
  package-cleanup --oldkernels --count=1 -y
fi

if [ "$distro" != 'redhat' ]; then
  echo "Clean all package cache information"
  $pkg_cmd -y clean all --enablerepo=\*
fi

# clean up network interface persistence
rm -f /lib/udev/rules.d/75-persistent-net-generator.rules
rm -rf /dev/.udev/

for ndev in $(ls -1 /etc/sysconfig/network-scripts/ifcfg-*); do
  if [ "$(basename $ndev)" != "ifcfg-lo" ]; then
    sed -i '/^HWADDR/d' "$ndev"
    sed -i '/^UUID/d' "$ndev"
  fi
done

echo "Truncate any logs that have built up during the install"
find /var/log -type f -exec truncate --size=0 {} \;

echo "Remove the install log"
rm -f /root/anaconda-ks.cfg /root/original-ks.cfg

echo "Remove the contents of /tmp and /var/tmp"
rm -rf /tmp/* /var/tmp/*

if [ "$major_version" -ge 7 ]; then
  echo "Force a new random seed to be generated"
  rm -f /var/lib/systemd/random-seed

  echo "Wipe netplan machine-id (DUID) so machines get unique ID generated on boot"
  truncate -s 0 /etc/machine-id
fi

echo "Clear the history so our install commands aren't there"
rm -f /root/.wget-hsts
export HISTSIZE=0

# reboot
