# pgOperate -  Tool Set to operate PostgreSQL Clusters
---

pgOperate is a tool that simplifies the operation of Community PostgreSQL clusters (versions 9.6+).

Check the [Change Log](CHANGELOG.md) for new features and changes introduced in new versions of the tool.

## Prerequisites

pgOperate requires pgBaseEnv.

First pgBasEnv must be installed. Minimum required version is 1.9.


## License
The pgOperate is released under the APACHE LICENSE, VERSION 2.0, that allows a collaborative open source software development.


## Examples

### Create new Cluster

If you want to create new cluster with alias sales:

```
cd $PGOPERATE_BASE/etc
cp parameters_mycls.conf.tpl parameters_sales.conf
vi parameters_sales.conf

pgoperate --create-cluster --alias sales
```

### Take a backup

```
pgoperate --backup

pgoperate --backup list

Current cluster: sales

Backup location: /u00/app/pgsql/test/sales/backup
=========================================================================
|Sub Dir|      Backup created|WALs count|Backup size(MB)|  WALs size(MB)|
=========================================================================
|      1| 2020-10-25 12:46:45|         4|              5|             81| <--- Oldest backup dir
|      2| 2020-10-25 13:10:43|         2|              5|             33| <--- Current backup dir
=========================================================================
Number backups: 2

```

### Restore

Execute point-in-time recovery

```
pgoperate --restore until_time="2020-10-25 13:05:00"
```

Correct backup subdirectory will be identified and Cluster will be restored to th specified time point.


### Create standby

If sales cluster runs on node1 and we want to create standby on node2, then execute add standby command on master host node1.

Defined first uniqname for master and standby and execute:

```
node1 $ pgoperate --standbymgr --add-standby --host node2 --uniqname site2 --master-host node1 --master-uniqname site1
```

Note: You can use any network interface with --host and --master-host. It can be hostname, FQDN or IP address.

### Switchover to standby

With pgOperate it is very easy to switchover to standby.

```
node1 $ pgoperate --standbymgr --switchover --target site2
``` 

### Failover to standby 

If you are on standby site site2, then

```
node2 $ pgoperate --standbymgr --failover
```

### Check standby configuration

```
$ pgoperate --standbymgr --status

Node_number Uniq_name        Node_name   Role     Mode     State WAL_receiver Apply_lag_MB Transfer_lag_MB Transfer_lag_Min
1           node1            site1       MASTER            UP
2           192.168.56.102   site2       STANDBY  async    UP    streaming             0               0                0
3           node3.pg.org     site3       STANDBY  sync     UP    streaming             0               0                0 

```

### Switch site2 to synchronous mode

```
$ pgoperate --standbymgr --set-sync --target site2
```


### Check the cluster

Execute `pgoperate --check` to check the main metrics of the cluster.

```
$ pgoperate --check

Current cluster: sales
Executing check PG_CHECK_DEAD_ROWS

SUCCESS: From check PG_CHECK_DEAD_ROWS: The autovacuum process is enabled and there are no tables with critical count of dead rows.

Executing check PG_CHECK_FSPACE

SUCCESS: From check PG_CHECK_FSPACE: The mount point / on which cluster data directory resides is 5% used. Threshold is 90%.

Executing check PG_CHECK_LOGFILES

SUCCESS: From check PG_CHECK_LOGFILES: There are no messages matching the search pattern ERROR|FATAL|PANIC in logfiles.

Executing check PG_CHECK_MAX_CONNECT

SUCCESS: From check PG_CHECK_MAX_CONNECT: Number of connections 6 is in range. Threshold value 87. Maximum allowed non-superuser is 97.

Executing check PG_CHECK_STDBY_AP_DELAY_MB

SUCCESS: From check PG_CHECK_STDBY_AP_DELAY_MB: Not a standby database.

Executing check PG_CHECK_STDBY_AP_LAG_MIN

SUCCESS: From check PG_CHECK_STDBY_AP_LAG_MIN: Not a standby database.

Executing check PG_CHECK_STDBY_STATUS

SUCCESS: From check PG_CHECK_STDBY_STATUS: Not a standby database.

Executing check PG_CHECK_STDBY_TR_DELAY_MB

SUCCESS: From check PG_CHECK_STDBY_TR_DELAY_MB: Not a standby database.

Executing check PG_CHECK_WAL_COUNT

SUCCESS: From check PG_CHECK_WAL_COUNT: WAL files count is 5, the current WAL size 80MB not exceed max_wal_size 1024MB more than 20% threshold.
```


## Installation and upgrade

To install pgOperate you need installer script `install_pgoperate.sh` and tar file with current version.

Both files can be downloaded from directory `bundle`.

Download both files on some location on the destination host and execute:

```
cd /var/lib/pgsql/bundle
./install_pgoperate.sh

...
Installation successfully completed.

Now execute /var/lib/pgsql/tvdtoolbox/pgoperate/bin/root.sh as root user.
```

PgOperate will be installed into `$TVDBASE/pgoperate` directory.

After installation execute `root.sh` as root. 

It will register and start `pgoperated-<postgres owner>` service.

File `01_<postgres owner>` will be created in `/etc/sudoers.d` to allow `postgres owner` user to `start/stop/status/reload` the `pgoperated-<postgres owner>` service with sudo privileges.

To upgrade to the new version, just download bundle directory and execute `install_pgoperate.sh`. It will not overwrite user
specific files.

If there will be special installation notes, they will be described in [Change Log](CHANGELOG.md).




## PostgreSQL cluster management scripts developed to automate regular tasks.

| Script                  | Description                                                            |
| ----------------------- | ---------------------------------------------------------------------- |
| **create_cluster.sh**   | Creates new PostgreSQL cluster.                                        |
| **add_cluster.sh**      | Add existing Cluster to pgOperate environment.                         |
| **remove_cluster.sh**   | Removes PostgreSQL cluster.                                            |
| **standbymgr.sh**       | Script to add and manage standby cluster.                              |
| **backup.sh**           | Backs up PostgreSQL cluster.                                           |
| **restore.sh**          | Restore PostgreSQL cluster.                                            |
| **check.sh**            | Executes different monitoring checks.                                  |
| **pgoperated**          | The main daemon script of the pgOperate.                               |
| **control.sh**          | The script to communicate ith daemon process to start/stop the cluster.|



## Libraries

| Libraries               | Description                                                            |
| ----------------------- | ---------------------------------------------------------------------- |
| **shared.lib**          | Generally used functions.                                              |
| **check.lib**           | Default check functions for check.sh (do not change this file).        |
| **custom_check.lib**    | Custom check functions for check.sh (add here your custom checks).     |


## Tool specific scripts

| Libraries                | Description                                                            |
| ------------------------ | ---------------------------------------------------------------------- |
| **pgoperate**            | Wrapper around all pgOperate scripts. Central execution point.         |
| **install_pgoperate.sh** | pgOperate installation script.                                         |
| **root.sh**              | Script to execute root actions after installation.                     |
| **bundle.sh**            | Generates installation bundle for pgOperate.                           |





## General concept

Each PostgreSQL cluster installation using pgOperate scripts will have following structure.

Like PostgreSQL itself, we create single directory, one level over `PGDATA`, which will act as the base for the cluster.

We call this directory `PGSQL_BASE`.

The directory structure of the pgOperate itself is as follows:

```
$PGOPERATE_BASE ┐
                │
                ├─── bin ┐
                │        ├── pgoperate
                │        ├── create_cluster.sh
                │        ├── remove_cluster.sh
                │        ├── standbymgr.sh
                │        ├── backup.sh
                │        ├── restore.sh
                │        ├── check.sh
                │        ├── root.sh
                │        ├── ...
                │        ├── install_pgoperate.sh
                │        ├── bundle.sh       
                │        └── VERSION
                │
                ├─── db ─┐
                │        ├── repconf_<alias>
                │        └── ...
                │
                ├─── etc ┐
                │        ├── parameters_mycls.conf.tpl
                │        ├── parameters_<alias>.conf        
                │        └── ...
                │
                ├─── log ┐
                │        ├── pgoperate-deamon.log
                │        ├── create_cluster.sh_YYYYMMDD_HHMMSS.log        
                │        └── ...
                │
                ├─── lib ┐
                │        ├── check.lib
                │        ├── custom_check.lib
                │        └── shared.lib
                │
                └─── bundle ┐
                            ├── install_pgoperate.sh
                            └── pgoperate-<version>.tar
```

Each installation will have its own single parameters file. The name format of the parameter filename is important, it must be `parameters_<alias>.conf`. Where `alias` is the pgBasEnv alias of the PostgreSQL cluster. It will be used to set its environment.

The parameter file includes all parameters required for cluster creation, backup, replication, monitoring and high availability. Everything in one place. All pgOperate scripts will use this parameter file for the current alias to get required values. It is our single point of truth.

The location of the cluster base directory `PGSQL_BASE` will be defined in the clusters `parameters_<alias>.conf` file as well.

After installation, base directory structure will look like this:

```
$PGSQL_BASE ┐
            │
            ├─── scripts ┐
            │            ├── start.sh
            │            └── root.sh
            │
            ├─── etc ┐
            │        ├── postgresql.conf
            │        ├── pg_ident.conf
            │        └── pg_hba.conf
            │
            ├─── data ┐
            │         └── $PGDATA
            │
            ├─── log ┐
            │        ├── server.log
            │        ├── postgresql-<n>.log
            │        ├── ...
            │        └── tools ┐
            │                  ├── <script name>_%Y%m%d_%H%M%S.log
            │                  └── ...
            ├─── cert
            │
            ├─── backup
            │
            └─── arch 

```

### Subdirectories

#### scripts

Contains scripts related to current cluster.

`root.sh` - Must be executed as root user after cluster creation. It will register `postgresql-<alias>` unit by systemctl daemon and finalize cluster creation.

`start.sh` - Script to start PostgreSQL with `pg_ctl` utility. Can be used for special cases, it is recommended to use `sudo systmctl` to manage PostgreSQL instance.

#### etc

All configuration files related to current cluster will be stored in this folder.

#### data

The `$PGDATA` folder of the current cluster.

#### log

Main location to all log files related to the current cluster.

`server.log` - Is the cluster main log file. Any problems during cluster startup will be logged here. After successful start logging will be handed over to logging collector.

`postgresql-<n>.log` - Logging collector output files. By default pgOperate will use day of the month in place of n.

Sub-folder `tools` will include output logs from all the pgOperate scripts. Any script executed will log its output into this directory. Log filename will include script name and timestamp. First two lines of the logfile will be the list of arguments used to execute script and the current user id.

#### cert

Is the folder to store all server side certificate files for ssl connections.

If `ENABLE_SSL` parameter was set to "on" in `parameters_<alias>.conf` file then during cluster creation, cert files will be copied to this folder.

#### backup

Is the default and recommended location for the backups. Backup script will create backups in this folder. It is recommended to link this folder to some network attached storage. Especially is case of primary/standby configuration.

#### arch

In case of archive log mode, WAL files will be archived to **backup** sub-folder. This **arch** directory must be local. It will be used as fail-over location if **backup** folder will not be available.




## If you want to upgrade PostgreSQL

Example of upgrade from version 11 to version 12.

First PostgreSQL version 12 must be installed. Lets say that pgBasEnv alias of the 12 home is pgh121. 

Cluster alias is tt1.

With pgBasEnv we can set cluster alias and non-default home alias.

Set tt1 cluster env and pgh121 as home:
```
$ tt1 pgh121
```

Go to base directory:
```
cd $PGSQL_BASE
```

We will create new empty directory to initialize 12 cluster.
```
mkdir data_new
```

Initialize new 12 data directory:
```
initdb -D $PGSQL_BASE/data_new
```

Now stop the cluster:
```
pgoperate --stop
```

Now set variables and execute upgrade:
```
export PGDATAOLD=$PGSQL_BASE/data
export PGDATANEW=$PGSQL_BASE/data_new
export PGBINOLD=/usr/pgsql-11/bin
export PGBINNEW=/usr/pgsql-12/bin
pg_upgrade --old-port=$PGPORT --new-port=$PGPORT --old-options="--config_file=$PGSQL_BASE/etc/postgresql.conf" --new-options="--config_file=$PGSQL_BASE/etc/postgresql.conf"
```

After the upgrade, rename controlfile in old home. It will prevent the cluster from startup and to be detected by pgBasEnv:
```
mv $PGSQL_BASE/data/global/pg_control $PGSQL_BASE/data/global/pg_control.old
```

Replace directories:
```
mv $PGSQL_BASE/data $PGSQL_BASE/data_old
mv $PGSQL_BASE/data_new $PGSQL_BASE/data
```

Modify pgclustertab to set new 12 home for tt1 and port if not set:
```
vi $PGBASENV_BASE/etc/pgclustertab
```

Now reset environment:
```
tt1
```

Start upgraded 12 cluster:
```
pgoperate --start
```




## High availability

To ensure the high availability of the clusters and minimize root privileged actions, pgOperate will use its own daemon process.

pgOperate daemon process `pgoperated` will run under postgres owner user. It will monitor all clusters registered with pgOperate.

There will be one systemd service `pgoperated-$user.service`, where $user is the postgres installation owner. This service will control
pgoperated daemon, which in his turn will control all postgresql instances.

If postgresql was installed under **postgres** user:
```
  ┌────────────────────────────────┐  ┌────────────────────────────────────────┐
  │ root                           │  │ postgres                               │
  │                                │  │                 ┌───> pg01 cluster     │
  │  pgoperated-postgres.service  ──────> pgoperated ───┼───> pg02 cluster     │
  │                                │  │                 └───> pg03 cluster     │
  │                                │  │                                        │
  └────────────────────────────────┘  └────────────────────────────────────────┘

```

This setup makes it possible to restore state of each particular instance after server crash or restart, as well as be flexible in adding new postgres clusters to configuration or removing existing ones. It is also possible to change cluster port or data directory without the need to update systemd serivce files. 

Daemon process `pgoperated` will monitor the configuration parameters of the registered clusters and try to keep postgres instaces aligned to their intended states. If `AUTOSTART` parameter is set to `YES` in the `parameters_<alias>.conf` file, then `pgoperated` will control its availability. 

Intended state can be defined by parameter `INTENDED_STATE` in `parameters_<alias>.conf` file. It can be set to `UP` or `DOWN`.
If it is set to `UP`, then daemon will try to keep the cluster up and running, it will be also started after host restart.

The commands `pgoperate --start` and `pgoperate --stop` can be used to start or stop the cluster manually. If `AUTOSTART` for the current cluster set to `YES`, then these commands will signal daemon to start or stop the claster. If `AUTOSTART` is set to any other values, then local commands will be used to start or stop the cluster.

pgoperated can automatically failover the monitored instance after `FAILCOUNT` failed attempts to restart it. The target for the failover will be next available and healthy standby with lowest node number. To see node numbers use `pgoperate --standbymgr --status`. To enable this behaviour `AUTOFAILOVER` parameter must be set to `yes`, which is default value.

After failover will be initiated, old master will be left in `REINSTATE` state. If there will be attempt to start it using `pgoperate --start` or automatically by pgoperated, then reintate will be tried.

### SELinux
If SELinux is enabled on your system you might face some issues starting the pgoperated-postgres daemon. 

The following steps shoud fix the issue.

```bash
# install semanage utility
sudo yum install policycoreutils-python-utils

# Set and restore the context (adapt the paths to your needs)
semanage fcontext -a -t bin_t "/var/lib/pgsql/tvdtoolbox/pgbasenv/bin(/.*)?"
semanage fcontext -a -t bin_t "/var/lib/pgsql/tvdtoolbox/pgoperate/bin(/.*)?"

restorecon -R -v /var/lib/pgsql/tvdtoolbox/pgbasenv/bin

# daemon startup should work now
systemctl start pgoperated-postgres.service

# check the new context (adapt the path to your needs)
ls -lZ /var/lib/pgsql/tvdtoolbox/pgbasenv/bin
```

## About parameters_\<alias\>.conf
---

It is a single parameter file which includes variables used by all management scripts.

Some parameters will be used only during cluster creation time, some will be used regularly.

It must be located in `$PGOPERATE_HOME/etc` folder.

Permissions of the config file must be `0600`.

There is `parameters_mycls.conf.tpl` template file with description of all the available parameters.

Parameters:

| Parameter                 | Default value                            | Description                                                                  |
| ------------------------- | ---------------------------------------- | ---------------------------------------------------------------------------- |
| **TVD_PGHOME_ALIAS**      |                                          | The pgBasEnv alias for the PostgreSQL binaries home to be used for this cluster creation.            |
| **PGSQL_BASE**            |                                          | Cluster base directory.            |
| **TOOLS_LOG_RETENTION_DAYS** | `30`                                  | Retention in days of the log files generated by the pgOperate scripts in `$PGSQL_BASE/log/tools` location.                                   |
| **PG_PORT**               |                                          | Cluster port to create the cluster. It will be also registered in pgBasEnv.                                   |
| **AUTOSTART**           | `YES`                                   | If set to YES, then PgOperate daemon process "pgoperated" will monitor this instance and try to keep it aligned to its intended state.                                   |
| **INTENDED_STATE**           | `DOWN`                                   | Inteded state of the instance. Will have effect only if AUTOSTART=YES. If intended state is UP, then pgoperated will try to keep it up and running.          |
| **ADDITIONAL_START_OPTIONS**   |                                    | Additional options to pass to postgres (PostgreSQL server executable) during startup.                                   |
| **PG_ENCODING**           | `UTF8`                                   | The character set of the cluster. Used only during creation.                                   |
| **PG_DATABASE**           |                                          | Database name which will be created after installation. If empty, then no database will be created                     |
| **PG_ENABLE_CHECKSUM**    | `yes`                                    | Checksums on data pages. |
| **PG_SUPERUSER**          | `postgres`                               | The name of the superuser to create during setup.                            |
| **PG_SUPERUSER_PWD**  |                                          | The password for the superuser account.                             | 
| **PCTMEM**                | `30`                                     | The percent of the host memory to use for PostgreSQL shared buffers.         |
| **ENABLE_SSL**            | `no`                                    | Will try to copy `CA_CERT`, `SERVER_CERT` and `SERVER_KEY` to the `$PGSQL_BASE/cert` directory and then enable SSL connections to cluster. If some of these certificates will not be found then `ENABLE_SSL` will be forced to "no".                                                                 |
| **CA_CERT**               |                                          | File with CA certificate. Usually called root.crt.                           |
| **SERVER_CERT**           |                                          | File with SSL server certificate. Usually called server.crt.                 |
| **SERVER_KEY**            |                                          | File with SSL server private key. Usually called server.key.                 |
| **PG_DEF_PARAMS**         | Default value is below                   | String variable which includes the init parameters separated by new line. These parameters will be set in postgresql.conf during installation. If `shared_buffers` will be set here, then it will be overridden by `PCTMEM` if defined. If `PCTMEM` is null then absolute value will be set. |
| **MINIMIZE_CONF_FILE**       | `no`                     | If set to "yes" then all commented parameters will be removed from postgresql.conf          |
| **PG_START_SCRIPT**       |                      | Custom script to start the cluster. If defined, then it will be used to start the cluster.                                             |
| **PG_STOP_SCRIPT**       |                      | Custom script to stop the cluster. If defined, then it will be used to stop the cluster.                                             |
| **DISABLE_BACKUP_SCRIPTS**       | `no`                     | If third party backup tools will be used. Then disable default backup/recovery scripts with this variable.                                             |
| **BACKUP_LOCATION**       | `$PGSQL_BASE/backup`                     | Directory to store backup files.                                             |
| **BACKUP_REDUNDANCY**     | `5`                                      | Backup redundancy. Count of backups to keep.                                                 |
| **BACKUP_RETENTION_DAYS**  | `7`                                      | Backup retention in days. Keeps backups required to restore so much days back.  This parameter, if set, overrides BACKUP_REDUNDANCY.                                                |
| **RESTORE_COMMAND**  |                                       | Custom restore command, will be written to postgresql.conf on standby site if `DISABLE_BACKUP_SCRIPTS` is set to `yes`        |
| **MASTER_HOST**           |                                          | !DEPRECATED! Replication related. The name or ip address of the master cluster.           |
| **MASTER_PORT**           |                                          | !DEPRECATED! Replication related. The PORT of the master cluster. If not specified then `$PGPORT` will be used.           |
| **REPLICATION_SLOT_NAME** | `slave001, slave002, slave003  | !DEPRECATED! Replication related. Replication slot names to be created in master cluster. More than one replication slot separated by comma can be specified.|
| **AUTOFAILOVER**           | `yes`                                   | Enable automatic faiover in standby configuration.           |
| **FAILCOUNT**           | `3`                                   | If automatic failover enabled, then define after how meny failed attempts to start the instance to initiate failover.           |
| **REPLICA_USER_PASSWORD** |                                          | Replication related. Password for user REPLICA which will be created on master site. Slave will use this credential to connect to master.|


`PG_CHECK_%` parameters described in `check.sh` section.

**PG_DEF_PARAMS** default value is 
```
    "max_connections=1000
     huge_pages=off
     password_encryption=scram-sha-256
     logging_collector = on
     log_directory = '$PGSQL_BASE/log'
     log_filename = 'postgresql-%d.log'
     log_truncate_on_rotation = on
     log_rotation_age = 1d
     log_rotation_size = 0"
 ```



# Scripts


## bundle.sh
---

This script can be used to create a bundle for the installation.

Execute it after modifications in some of the scripts.

It will create the bundle by default in `$PGOPERATE_BASE/bundle` folder.

If you want to create bundle in some other location, then provide target folder as first argument.




## pgoperate
---

`pgoperate` is main interface to call all the pgOperate scripts.

During installation the alias pointing to it will be created in pgBasEnv standard config file. That is why pgoperate can be called from any location.

But to call it from inside the scripts use full path like `$PGOPERATE_BASE/bin/pgoperate`

```
pgoperate --help

Available options:

  --version                Show version.
  --stop                   Stop current cluster. (Signal will be sent to daemon and operation status received)
  --start                  Start current cluster. (Signal will be sent to daemon and operation status received)
  --reload                 Reload all running clusters. (pg_ctl reload)
  --daemon-status          Check the status of the pgoperated.
  --create-cluster         Create new PostgreSQL Cluster
  --add-cluster            Add existing cluster to pgOperate environment
  --remove-cluster         Removes PostgreSQL Cluster
  --backup                 Backup PostgreSQL CLuster
  --restore                Restore PostgreSQL Cluster
  --check                  Execute monitoring checks
  --standbymgr             Interface to standby manager. Use "--standbymgr help" to get available options.


  For each option you can get help by adding "help" keyword after the argument, like:
    pgoperate --backup help

```




## create_cluster.sh
---

This script will create a new PostgreSQL cluster.

Logs of the **create_cluster.sh** will be saved into $PGOPERATE_BASE/log folder.

Arguments:
   `-a|--alias <alias_name>` -  Alias name of the cluster to be created.

Alias name of the cluster to be created must be provided.

Parameters file for this alias must exist in `$PGOPERATE_BASE/etc` before executing the script.

The `$PGSQL_BASE` directory will be created. All subdirectories will be also created.

Cluster will be registered with pgBasEnv. 

Next steps will be performed:

* Database `$PG_DATABASE` will be created if set.
* Schema with same name `$PG_DATABASE` will be created.
* User with same name `$PG_DATABASE` and without password will be created. This user will be owner of `$PG_DATABASE` schema.
* Replication related parameters will be adjusted
* Replication user and replication slot(s) will be created
* `pg_hba.conf` file will be updated

Script must be executed as postgres user.

Local connection without password will be possible only by postgres user and root.

Example for cluster with alias cls1:

```
# Create parameters file for cls1
cd $PGOPERATE_BASE
cp parameters_mycls.conf.tpl parameters_cls1.conf

# Modify parameter file as required
vi parameters_cls1.conf

# Then execute as postgres
pgoperate --create-cluster --alias cls1
```



## add_cluster.sh
---

In situations when there is already a running cluster which you want to use with pgOperate, add_cluster-sh can be used to create PGSQL_BASE directory and parameters file for your cluster.

Logs of the **add_cluster.sh** will be saved into $PGOPERATE_BASE/log folder.

Arguments:
```
              -a|--alias <alias_name> -  Alias name of the running cluster to be added.
              -s|--silent             -  Silent mode.

              Parameters for silent mode:
                 -b|--base                   - (Mandatory) Base directory name
                 -s|--superuser <username>   - (Optional) Cluster superuser. Default is postgres.
                 -w|--password               - (Optional) Superuser password.
                 -l|--backup-dir <dirname>   - (Optional) Directory for backups. Default is /u00/app/pgsql/test/pgd11/backup
                 -c|--arch-dir <dirname>     - (Optional) Directory for archived logs. Default is /u00/app/pgsql/test/pgd11/arch
                 -k|--start-script           - (Optional) Script to start Cluster.
                 -n|--stop-script            - (Optional) Script to stop Cluster.
```

Alias name of the cluster to be added must be provided.

Parameters file for this alias will be created in `$PGOPERATE_BASE/etc`.

The `$PGSQL_BASE` directory will be created. All subdirectories will be created or symbolic links will be added.

Script must be executed as postgres user.

If you already use systemd service to control your PostgreSQL instance, then you can continue to use it or switch to pgOperates HA model. If you deside to switch, then deconfigure your serivce. If you prefer to use your service, then prepare custom start and stop scripts to use with pgoperate. You can set them during cluster add operation with `--start-script` and `--stop-script` parameters.
These two parameters will set `PG_START_SCRIPT` and `PG_STOP_SCRIPT` in `parameters-<alias>.conf` file. You can change them later.

Example for cluster with alias cls1:

```
pgoperate --add-cluster --alias sales --silent --base /u00/app/pgsql/clusters
```





## remove_cluster.sh
---

This script will remove a PostgreSQL cluster.

Logs of the **remove_cluster.sh** will be saved into $PGOPERATE_BASE/log folder.

Arguments:
              `-a|--alias <alias_name>` -  Alias name of the cluster to be removed.

Alias name of the cluster to be deleted must be provided.

Parameters file for this alias must exist in `$PGOPERATE_BASE/etc` before executing the script.

The `$PGSQL_BASE` directory will be removed.

Cluster will be unregistered from pgBasEnv. 

Next steps will be performed:

* Cluster will be stopped.
* `$PGSQL_BASE` will be removed.
* Script will be generated to remove service file for this cluster.

Script must be executed as postgres user.

At the end of execution, script will offer to run `/tmp/pg_rm_service.sh` as root user.

Switch to root and execute it. It will remove `postgresql-<alias>` unit file from /etc/systemd/system.

Example for cluster with alias cls1:

```
# Execute as postgres
pgoperate --remove-cluster --alias cls1
Cluster pg12 will be deleted. Cluster base directory including $PGDATA will be removed. Continue? [y/n]
```



## standbymgr.sh
---

Script to add and manage standby clusters.

Each cluster in the configuration must be assigned a uniqname, which will identify the cluster in the configuration.

In all standby related operation the uniqname will be used.

Each cluster will have following properties:
* Node number
* Uniqname
* Host

Host will be defined at standby creation, it can be any hostname, including FQDN or IP address. Host will be used for ssh communication and to establish replication connection. It will be used in `primary_conninfo`.

The uniqname will be used in replication slot names and as standby names.

Switchover and all other commands accept uniqname as a target.

Can be executed over `pgoperate --standbymgr`.

Available options:
```
 --check --host <hostname> --master-host <hostname>  Check the SSH connection from local host to target host and back.
 --status                             Show current configuration and status.
 --sync-config                        Synchronize config with real-time information and distribute on all configured nodes.
 --add-standby --uniqname <name> --host <hostname> [--master-uniqname <master name> --master-host <master hostname>]    Add new standby cluster on specified host.
                                          Provide uniq name and hostname to connect. If there was no configuration, then also master uniqname and hostname are required.
                                          Must be executed on master host.
 --show-uniqname                      Get the uniqname of the local site.
 --set-sync --target <uniqname> [--bidirectional]  Set target standby to synchronous replication mode.
 --set-async --target <uniqname> [--bidirectional]  Set target standby to asynchronous replication mode.
                                      If bidirectional option specified, then current master will be added as synchronous
                                      standby to the target standbys configuration. To maintain synchronous replication after switchover.
 --switchover [--target <uniqname>]   Switchover to standby. If target was not provided, then local site will be a target.
 --failover [--target <uniqname>]     Failover to standby. If target was not provided, then local site will be a target.
                                        Old master will be stopped and marked as REINSTATE in configuration.
 --reinstate [--target <uniqname>]    Reinstate old primary as new standby.
 --prepare-master [--target <uniqname>]  Can be used to prepare the hostname for master role.

 --force     Can be used with any option to force some operations.

```

Prerequisites for `standbymgr` are:
* pgBaseEnv (minimum 1.9) and pgOperate must be installed on remote host
* Passwordless ssh connection must be configured between all members of the configuration over the interface used in the `--host` or `--master-host` parameters.

All commands except `--add-standby` can be executed on any host of the configuration.

During switchover, last checkpoint location and next XID will be compared between master and standby. If there will be risk of data loss, then switchover will not happen. In such cases the reason of the lag must be detected and eliminated or `--failover` option must be used to execute failover.

After failover previous master will be stopped if accessable and its status will be set to REINSTATE. You must execute `--reinstate` on this cluster to convert it to new standby.


## backup.sh
---

Script to backup PostgreSQL cluster on Primary or Standby site.

Please check the script header for detailed information.

Backup will be made from online running cluster, it is hot full backup.

Backup can be execute on primary or standby.

Following backup strategies are possible:
 * Database backup on master site and archived WAL backup on master site
 * Database backup on standby site and archived WAL backup on standby site
 * Database backup on standby site and archive WAL backup on primary site (Recommended)

Backups can be made also in no-archivelog mode, then restore will be possible only to backup end time.

Arguments:
                     `list` -  Script will list the contents of the BACKUP_LOCATION.
              `enable_arch` -  Sets the database cluster into archive mode. Archive location will be set to PGSQL_BASE/arch.
                               No backup will taken. Cluster will be restarted!
  `backup_dir=<directory>`  -  One time backup location. Archive log location will not be switched on this destination.


With parameters `BACKUP_REDUNDANCY` and `BACKUP_RETENTION_DAYS` in parameters_<alias>.conf, you can specify backups retention logic.

`BACKUP_REDUNDANCY` - Will define the number of backups to retain.

`BACKUP_RETENTION_DAYS` - Will define the number of the days you want to retain. If you will specify 7 for example, then backup script will guarantee that backups required to restore 7 days back will not be overwritten.

If both parameters specified, then `BACKUP_RETENTION_DAYS` overrides redundancy.

To make backup, execute without any arguments.

Execute as postgres:
```
pgoperate --backup
```

Use `list` to show all backups:
```
pgoperate --backup list
```


## restore.sh
---

Script to restore PostgreSQL cluster from backup.

If any external tablespaces exists in backup then their locations will be also cleared before restore.

Script can be executed without any parameters. In this case it will restore from the latest available backup.

 Arguments:
 ```
    list                        - Script will list the contents of the `BACKUP_LOCATION`.
    backup_dir=<directory>      - One time backup location. Will be used as restore source.
    from_subdir=<subdir>        - Execute restore from specified sub-directory number. Use 'list' to check all sub directory numbers. It must be number without date part.
    until_time=<date and time>  - To execute Point in Time recovery. Specify target time. Time must be in `\"YYYY-MM-DD HH24:MI:SS\"` format.
    pause                       - Will set `recovery_target_action` to pause in `recovery.conf` or `postgresql.conf`. When Point-In-Time will be reached, recovery will pause.
    shutdown                    - Will set `recovery_target_action` to shutdown in `recovery.conf` or `postgresql.conf`. When Point In Time will be reached, database will shutdown.
    verify                      - If this argument specified, then no actual restore will be execute. Use to check which sub-folder will be used to restore.
```

 Examples:
  Restore from last (Current) backup location:
```
    pgoperate --restore
```
  Restore from subdirectory 3:
```
    pgoperate --restore from_subdir=3
```

  First verify then restore to Point in Time `"2018-10-17 11:25:00"`:
```
    pgoperate --restore until_time="2018-10-17 11:25:00" verify
    pgoperate --restore until_time="2018-10-17 11:25:00"
```

Script by default looks to `BACKUP_LOCATION` from `parameters_<alias>.conf` for backups.

To restore from some other location, use `backup_dir` argument.

You can also list all backups from non-default location:
```
pgoperate --restore list backup_dir=/tmp/pgbackup

Backup location: /tmp/pgbackup
=========================================================================
|Sub Dir|      Backup created|WALs count|Backup size(MB)|  WALs size(MB)|
=========================================================================
|      4| 2019-08-03 12:09:09|         0|              5|              1| <--- Oldest backup dir
|      5| 2019-08-03 12:09:14|         0|              5|              1| <--- Current backup dir
=========================================================================
Number backups: 2
```

You can also restore from `subdir` or by specifying `until_time`:
```
pgoperate --restore backup_dir=/tmp/pgbackup from_subdir=4
```



## check.sh
---


Check script for PostgreSQL.

It is small framework to create custom checks.

As fist step check must be defined in `parameters_<alias>.conf` file with next parameters:
```
PG_CHECK_<CHECK NAME>=<check function name>
PG_CHECK_<CHECK NAME>_THRESHOLD=
PG_CHECK_<CHECK NAME>_OCCURRENCE=
```

Then custom check function must be defined in `custom_check.lib` file.

If check defined then function with the specified name will be executed from `custom_check.lib` library.

Function must return 0 on check success and not 0 on check not passed.

Number of times check was not passed will be counted by check.sh, check function do not require to implement this logic.
If `PG_CHECK_<CHECK NAME>_OCCURRENCE` is defined, then `check.sh` will alarm only after defined number of negative checks.


There are special input and output variables that can be used in check functions:

Input variables:
* `<function_name>_THRESHOLD`   - Input variable, if there was threshold defined, it will be assigned to this variable.
* `<function_name>_OCCURRENCE`  - Input variable, if there was occurrence defined, it will be assigned to this variables.
* `$PG_BIN_HOME`  - Points to the bin directory of the postgresql.
* `$SCRIPTDIR`    - The directory of the check script location. Can be used to create temporary invisible files for example. 
* `$PG_AVAILABLE` - Will be true if database cluster available and false if not available.

Next functions can be called from check functions:
* `exec_pg <cmd>`   - Will execute cmd in postgres and return psql return code, output will go to stdout.
* `get_fail_count` - Will get the number of times this function returned unsuccessful result. It will be assigned to `<function_name>_FAILCOUNT` variable.

Output variables:
* `<function name>_PAYLOAD`     - Output variable, assign output text to it.
* `<function name>_PAYLOADLONG` - Output variable, assign extra output text to it. \n can be used to divide text to new lines.
* `<function name>_CURVAL`      - Output Variable, assign current value to it.

When function returns 0 or 1, then it is also good to return some information to the user. This information can be passed over `<function name>_PAYLOAD` variable.
If some big amount of data, extra information must be displayed, then pass it over `<function name>_PAYLOADLONG` variable.

Check `custom_check.lib` file for check function examples.

There are already few predefined checks.


There is also the possibility to generate a text or json based output.

For a text formatted output execute `pgoperate --check -t `
```
pgoperate --check -t

Current cluster: mycls
PG_CHECK_DEAD_ROWS | ok | false | 30
PG_CHECK_FSPACE | ok | 27 | 90
PG_CHECK_LOGFILES | ok | 0 | ERROR|FATAL|PANIC
PG_CHECK_MAX_CONNECT | ok | 6 | 90
PG_CHECK_STDBY_AP_DELAY_MB | ok |  | 100
PG_CHECK_STDBY_AP_LAG_MIN | ok |  | 10
PG_CHECK_STDBY_STATUS | ok |  |
PG_CHECK_STDBY_TR_DELAY_MB | ok |  | 10
PG_CHECK_WAL_COUNT | ok | 16MB | 20
```

For a json formatted output execute `pgoperate --check -j `

```
{"check":"PG_CHECK_DEAD_ROWS","status":"ok","curval":"false","treshold":"30"}
{"check":"PG_CHECK_FSPACE","status":"ok","curval":"27","treshold":"90"}
{"check":"PG_CHECK_LOGFILES","status":"ok","curval":"0","treshold":"ERROR|FATAL|PANIC"}
{"check":"PG_CHECK_MAX_CONNECT","status":"ok","curval":"6","treshold":"90"}
{"check":"PG_CHECK_STDBY_AP_DELAY_MB","status":"ok","curval":"n/a","treshold":"100"}
{"check":"PG_CHECK_STDBY_AP_LAG_MIN","status":"ok","curval":"","treshold":"10"}
{"check":"PG_CHECK_STDBY_STATUS","status":"ok","curval":"","treshold":""}
{"check":"PG_CHECK_STDBY_TR_DELAY_MB","status":"ok","curval":"","treshold":"10"}
{"check":"PG_CHECK_WAL_COUNT","status":"ok","curval":"16MB","treshold":"20"}
```

Another useful feature is the possibility to execute only one check at a time.

To use this feature execute `pgoperate --check -c=<your_desired_check>` or `pgoperate --check --check=<your_desired_check>` 

Keep in mind that the check needs to be defined in the parameter file in '$PGOPERATE_BASE/etc'

```
pgoperate --check -c=PG_CHECK_WAL_COUNT

Current cluster: mycls
Executing check PG_CHECK_WAL_COUNT

SUCCESS: From check PG_CHECK_WAL_COUNT: WAL files count is 1, the current WAL size 16MB not exceed max_wal_size 1024MB more than 20% threshold.
```

Combination with text-based output `pgoperate --check -c=<your_desired_check> -t` or json-based output `pgoperate --check -c=<your_desired_check> -j` is also possible.

```
pgoperate --check -c=PG_CHECK_WAL_COUNT -j

Current cluster: mycls
{"check":"PG_CHECK_WAL_COUNT","status":"ok","curval":"16MB","treshold":"20"}
```

```
pgoperate --check -c=PG_CHECK_WAL_COUNT -t

Current cluster: d01pg
PG_CHECK_WAL_COUNT | ok | 16MB | 20
```
