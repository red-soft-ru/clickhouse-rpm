#
# Yandex ClickHouse DBMS build script for RHEL based distributions
#
# Important notes:
#  - build requires ~35 GB of disk space
#  - each build thread requires 2 GB of RAM - for example, if you
#    have dual-core CPU with 4 threads you need 8 GB of RAM
#  - build user needs to have sudo priviledges, preferrably with NOPASSWD
#
# Tested on:
#  - GosLinux IC4
#  - CentOS 6.8
#  - CentOS 7.2
#
# Copyright (C) 2016 Red Soft LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Git version of ClickHouse that we package
CH_VERSION=1.1.54236

# Git tag marker (stable/testing)
CH_TAG=stable

# SSH username used to publish built packages
REPO_USER=clickhouse

# Hostname of the server used to publish packages
REPO_SERVER=10.81.1.162

# Root directory for repositories on the remote server
REPO_ROOT=/var/www/html/repos/clickhouse

# Detect number of threads
export THREADS=$(grep -c ^processor /proc/cpuinfo)

# Build most libraries using default GCC
export PATH=${PATH/"/usr/local/bin:"/}:/opt/rh/devtoolset-6/root/usr/bin

# Determine RHEL major version
RHEL_VERSION=`rpm -qa --queryformat '%{VERSION}\n' '(redhat|sl|slf|centos|oraclelinux|goslinux)-release(|-server|-workstation|-client|-computenode)'`

function prepare_dependencies {

mkdir lib

sudo rm -rf lib/*

cd lib

if [ $RHEL_VERSION == 6 ]; then
  DISTRO_PACKAGES="scons"
fi

if [ $RHEL_VERSION == 7 ]; then
  DISTRO_PACKAGES=""
fi

# Install development packages
if ! sudo yum -y install $DISTRO_PACKAGES rpm-build redhat-rpm-config readline-devel mongo-cxx-driver centos-release-scl\
  unixODBC-devel subversion cmake python boost boost-devel python-devel git wget openssl-devel m4 createrepo glib2-devel\
  libicu-devel zlib-devel libtool-ltdl-devel openssl-devel && sudo yum -y install devtoolset-6-gcc*
then exit 1
fi

if [ $RHEL_VERSION == 7 ]; then
  # Connect EPEL repository for CentOS 7 (for scons)
  sudo yum -y install epel-release
  if ! sudo yum -y install scons; then exit 1; fi
fi

# Install MySQL client library from Oracle
wget http://dev.mysql.com/get/mysql57-community-release-el$RHEL_VERSION-9.noarch.rpm
sudo yum -y --nogpgcheck install mysql57-community-release-el$RHEL_VERSION-9.noarch.rpm
if ! sudo yum -y install mysql-community-devel; then exit 1; fi
sudo ln -s /usr/lib64/mysql/libmysqlclient.a /usr/lib64/libmysqlclient.a

# Use dev GCC 6 for builds
export CC=/opt/rh/devtoolset-6/root/usr/bin/gcc
export CXX=/opt/rh/devtoolset-6/root/usr/bin/g++

cd ..

}

function make_packages {

# Clean up after previous run
rm -f ~/rpmbuild/RPMS/x86_64/clickhouse*
rm -f ~/rpmbuild/SRPMS/clickhouse*
rm -f rpm/*.zip

# Configure RPM build environment
mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
echo '%_topdir %(echo $HOME)/rpmbuild
%_smp_mflags  -j'"$THREADS" > ~/.rpmmacros

# Create RPM packages
cd rpm
sed -e s/@CH_VERSION@/$CH_VERSION/ -e s/@CH_TAG@/$CH_TAG/ clickhouse.spec.in > clickhouse.spec
wget https://github.com/yandex/ClickHouse/archive/v$CH_VERSION-$CH_TAG.zip
mv v$CH_VERSION-$CH_TAG.zip ClickHouse-$CH_VERSION-$CH_TAG.zip
cp *.zip ~/rpmbuild/SOURCES
rpmbuild -bs clickhouse.spec
rpmbuild -bb clickhouse.spec

}

function publish_packages {
  mkdir /tmp/clickhouse-repo
  rm -rf /tmp/clickhouse-repo/*
  cp ~/rpmbuild/RPMS/x86_64/clickhouse*.rpm /tmp/clickhouse-repo
  if ! createrepo /tmp/clickhouse-repo; then exit 1; fi

  if ! scp -B -r /tmp/clickhouse-repo $REPO_USER@$REPO_SERVER:/tmp/clickhouse-repo; then exit 1; fi
  if ! ssh $REPO_USER@$REPO_SERVER "rm -rf $REPO_ROOT/$CH_TAG/el$RHEL_VERSION && mv /tmp/clickhouse-repo $REPO_ROOT/$CH_TAG/el$RHEL_VERSION"; then exit 1; fi
}

if [[ "$1" != "publish_only"  && "$1" != "build_only" ]]; then
  prepare_dependencies
fi
if [ "$1" != "publish_only" ]; then
  make_packages
fi
if [ "$1" == "publish_only" ]; then
  publish_packages
fi
