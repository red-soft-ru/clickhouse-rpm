# clickhouse-rpm
ClickHouse DBMS build script for RHEL based distributions

Run build_packages.sh on any RHEL 6 or RHEL 7 based distribution and it shall produce ClickHouse source and binary RPM packages for your system.

You can also install packages built with these scripts from public YUM repository.

To connect repository on CentOS 6/GosLinux:

`yum-config-manager --add-repo http://repo.red-soft.biz/repos/clickhouse/repo/clickhouse-el6.repo`

For CentOS 7:

`yum-config-manager --add-repo http://repo.red-soft.biz/repos/clickhouse/repo/clickhouse-el7.repo`

To install ClickHouse client and server:

`yum install clickhouse-server clickhouse-client clickhouse-server-common clickhouse-compressor`
