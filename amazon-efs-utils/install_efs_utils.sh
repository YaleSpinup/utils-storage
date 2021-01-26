#!/usr/bin/env bash
# Script to install amazon-efs-utils and prerequisites on non-Amazon Linux distributions

export PATH=/bin:/usr/bin:/sbin:/usr/sbin
exec 2>&1

EFSUTILS_PKG="amazon-efs-utils"
TMPDIR="/tmp"

install_efsutils_amazon () {
  # check if installed
  if rpm -q ${EFSUTILS_PKG} > /dev/null; then
    echo "${EFSUTILS_PKG} already installed"
    return 1
  fi

  # install rpm package
  echo "Installing package ${EFSUTILS_PKG} ..."
  yum -y install ${EFSUTILS_PKG}
}

install_efsutils_centos () {
  # check if installed
  if rpm -q ${EFSUTILS_PKG} > /dev/null; then
    echo "${EFSUTILS_PKG} already installed"
    return 1
  fi

  # install rpm package
  echo "Installing package ${EFSUTILS_PKG} ..."
  yum -y install git rpm-build make nfs-utils
  cd ${TMPDIR}
  git clone https://github.com/aws/efs-utils
  cd efs-utils && \
  make rpm && \
  yum -y install build/${EFSUTILS_PKG}*rpm
}

install_efsutils_ubuntu () {
  # check if installed
  if [ $(dpkg-query -W -f='${Status}' ${EFSUTILS_PKG} 2>/dev/null | grep -c "ok installed") -eq 1 ]; then
    echo "${EFSUTILS_PKG} already installed"
    return 1
  fi

  # install deb package
  echo "Installing package ${EFSUTILS_PKG} ..."
  apt-get update
  apt-get -y install git binutils nfs-common
  cd ${TMPDIR}
  git clone https://github.com/aws/efs-utils
  cd efs-utils && \
  ./build-deb.sh && \
  apt-get -y install ./build/${EFSUTILS_PKG}*deb
}

install_stunnel_centos () {
  if rpm -q stunnel > /dev/null; then
    echo "stunnel already installed"
    stunnel -version 2>&1 | grep "stunnel "
    return 1
  fi

  echo "Installing package stunnel ..."
  yum -y install stunnel
}

install_stunnel_ubuntu () {
  if [ $(dpkg-query -W -f='${Status}' stunnel 2>/dev/null | grep -c "ok installed") -eq 1 ]; then
    echo "stunnel already installed"
    stunnel -version 2>&1 | grep "stunnel "
    return 1
  fi

  echo "Installing package stunnel ..."
  apt-get -y install stunnel
}

# patch the stunnel binary to support NFS TLS (only required for CentOS 7)
patch_stunnel () {
  PATCHVER="5.57"
  STUNNEL="stunnel-${PATCHVER}"
  CURVER=$(stunnel -version 2>&1 | grep "stunnel " | awk '{print $2}')
  if [[ ${CURVER} == ${PATCHVER} ]]; then
    echo "No need to patch stunnel, version ${PATCHVER} already installed"
    return 1
  fi

  echo "Patching stunnel to version ${PATCHVER} ..."
  yum install -y gcc openssl-devel tcp_wrappers-devel
  cd ${TMPDIR}
  curl -o ${STUNNEL}.tar.gz https://www.stunnel.org/downloads/${STUNNEL}.tar.gz && \
  tar xvfz ${STUNNEL}.tar.gz && \
  cd ${STUNNEL}
  ./configure
  make
  if [[ -f /bin/stunnel ]]; then
    mv /bin/stunnel /root
  fi
  make install
  ln -s /usr/local/bin/stunnel /bin/stunnel
}


# check root privileges
if [ $(id -u) != 0 ]; then
  echo "You need to run this script with sudo"
  exit
fi

# determine distro
if [ -n "$(command -v lsb_release)" ]; then
  distroname=$(lsb_release -s -d)
elif [ -f "/etc/os-release" ]; then
  distroname=$(grep PRETTY_NAME /etc/os-release | sed 's/PRETTY_NAME=//g' | tr -d '="')
elif [ -f "/etc/debian_version" ]; then
  distroname="Debian $(cat /etc/debian_version)"
elif [ -f "/etc/redhat-release" ]; then
  distroname=$(cat /etc/redhat-release)
else
  distroname="$(uname -s) $(uname -r)"
fi

echo "Detected OS: ${distroname}"

if [[ "${distroname}" == "Ubuntu"* ]]; then
  install_efsutils_ubuntu
  install_stunnel_ubuntu

elif [[ "${distroname}" == "CentOS"* ]]; then
  install_efsutils_centos
  install_stunnel_centos

  if [[ "${distroname}" == "CentOS Linux 7"* ]]; then
    # need to patch stunnel in CentOS 7
    patch_stunnel
  fi

elif [[ "${distroname}" == "Amazon"* ]]; then
  install_efsutils_amazon
  install_stunnel_centos

else
  echo "Unsupported Linux distro"
fi
