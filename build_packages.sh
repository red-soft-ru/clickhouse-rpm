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
CH_VERSION=1.1.54198

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
export PATH=${PATH/"/usr/local/bin:"/}:/usr/local/bin

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
if ! sudo yum -y install $DISTRO_PACKAGES rpm-build redhat-rpm-config gcc-c++ readline-devel\
  unixODBC-devel subversion python-devel git wget openssl-devel m4 createrepo glib2-devel\
  libicu-devel zlib-devel libtool-ltdl-devel openssl-devel
then exit 1
fi

if [ $RHEL_VERSION == 7 ]; then
  # Connect EPEL repository for CentOS 7 (for scons)
  wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
  sudo yum -y --nogpgcheck install epel-release-latest-7.noarch.rpm
  if ! sudo yum -y install scons; then exit 1; fi
fi

# Install MySQL client library from Oracle
wget http://dev.mysql.com/get/mysql57-community-release-el$RHEL_VERSION-9.noarch.rpm
sudo yum -y --nogpgcheck install mysql57-community-release-el$RHEL_VERSION-9.noarch.rpm
if ! sudo yum -y install mysql-community-devel; then exit 1; fi
sudo ln -s /usr/lib64/mysql/libmysqlclient.a /usr/lib64/libmysqlclient.a

# Install cmake
wget https://cmake.org/files/v3.7/cmake-3.7.0.tar.gz
tar xf cmake-3.7.0.tar.gz
cd cmake-3.7.0
./configure
if ! make -j $THREADS; then exit 1; fi
sudo make install
cd ..

# Install Python 2.7
if [ $RHEL_VERSION == 6 ]; then
  wget https://www.python.org/ftp/python/2.7.12/Python-2.7.12.tar.xz
  tar xf Python-2.7.12.tar.xz
  cd Python-2.7.12
  ./configure
  if ! make -j $THREADS; then exit 1; fi
  sudo make altinstall
  cd ..
fi

# Install GCC 6
wget ftp://ftp.fu-berlin.de/unix/languages/gcc/releases/gcc-6.2.0/gcc-6.2.0.tar.bz2
tar xf gcc-6.2.0.tar.bz2
cd gcc-6.2.0
./contrib/download_prerequisites
cd ..
mkdir gcc-build
cd gcc-build
../gcc-6.2.0/configure --enable-languages=c,c++ --enable-linker-build-id --with-default-libstdcxx-abi=gcc4-compatible --disable-multilib
if ! make -j $THREADS; then exit 1; fi
sudo make install
hash gcc g++
gcc --version
sudo ln -s /usr/local/bin/gcc /usr/local/bin/gcc-6
sudo ln -s /usr/local/bin/g++ /usr/local/bin/g++-6
sudo ln -s /usr/local/bin/gcc /usr/local/bin/cc
sudo ln -s /usr/local/bin/g++ /usr/local/bin/c++
cd ..

# Use GCC 6 for builds
export CC=gcc-6
export CXX=g++-6

# Install Boost
wget http://downloads.sourceforge.net/project/boost/boost/1.62.0/boost_1_62_0.tar.bz2
tar xf boost_1_62_0.tar.bz2
cd boost_1_62_0
if ! ./bootstrap.sh; then exit 1; fi
if ! ./b2 --toolset=gcc-6 -j $THREADS; then exit 1; fi
sudo PATH=$PATH ./b2 install --toolset=gcc-6 -j $THREADS
cd ..

# Install mongoclient from Git repo
git clone -b legacy https://github.com/mongodb/mongo-cxx-driver.git
cd mongo-cxx-driver
if ! sudo PATH=$PATH scons --c++11 --release --cc=$CC --cxx=$CXX --ssl=0 --disable-warnings-as-errors -j $THREADS --prefix=/usr/local install; then exit 1; fi
cd ..

# Install Clang from Subversion repo
mkdir llvm
cd llvm
svn co http://llvm.org/svn/llvm-project/llvm/tags/RELEASE_390/final llvm
cd llvm/tools
svn co http://llvm.org/svn/llvm-project/cfe/tags/RELEASE_390/final clang
cd ..
cd projects/
svn co http://llvm.org/svn/llvm-project/compiler-rt/tags/RELEASE_390/final compiler-rt
cd ../..
mkdir build
cd build/
cmake -D CMAKE_BUILD_TYPE:STRING=Release ../llvm -DCMAKE_CXX_LINK_FLAGS="-Wl,-rpath,/usr/local/lib64 -L/usr/local/lib64"
if ! make -j $THREADS; then exit 1; fi
sudo make install
hash clang
cd ../..

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
CC=gcc-6 CXX=g++-6 rpmbuild -bb clickhouse.spec

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
