# pgOperate -  Tool Set to operate PostgreSQL Clusters
---

pgOperate is a tool that simplifies the operation of Community PostgreSQL cluster (versions 9.6+).


## Prerequisites

pgOperate requires pgBaseEnv.

First pgBasEnv must be installed.


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

### Make a backup

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

If sales cluster runs on node1 and we want to create standby on node2, then copy $PGOPERATE_BASE/etc/parameters_sales.conf from node1 to node2.

Then bootstrap empty cluster:
```
node2 $ pgoperate --create-cluster --alias sales
```

Then create standby cluster:
```
node2 $ pgoperate --create-slave --master node1
```

### Do a switch-over

Stop the master on node1:
```
node1 $ sudo systemctl stop postgresql-sales
```

Promote standby to master on node2:
```
node2 $ pgoperate --promote
```

Start old primary as new standby:
```
node1 $ pgoperate --reinstate -m node2 -f
```


### Switchover to standby

With pgOperate it is very easy to switchover to standby.

`pgoperate --switchover` can be executed from master and standby sites. Passwordless ssh connection must be preconfigured.

Execute as postgres user:

```
pgoperate --switchover
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




## PostgreSQL cluster management scripts developed to automate regular tasks.

| Script                  | Description                                                            |
| ----------------------- | ---------------------------------------------------------------------- |
| **create_cluster.sh**   | Creates new PostgreSQL cluster.                                        |
| **add_cluster.sh**      | Add existing Cluster to pgOperate environment.                         |
| **remove_cluster.sh**   | Removes PostgreSQL cluster.                                             |
| **prepare_master.sh**   | Prepares PostgreSQL cluster to master role.                            |
| **create_slave.sh**     | Creates standby cluster.                                               |
| **promote.sh**          | Promotes standby to master.                                            |
| **reinstate.sh**        | Starts old master as new standby.                                      |
| **switchover.sh**       | Automatic switchover to standby site.                                  |
| **backup.sh**           | Backs up PostgreSQL cluster.                                             |
| **restore.sh**          | Restore PostgreSQL cluster.                                            |
| **check.sh**            | Executes different monitoring checks.                                  |


## Libraries

| Libraries               | Description                                                            |
| ----------------------- | ---------------------------------------------------------------------- |
| **shared.lib**          | Generally used functions.                                              |
| **check.lib**           | Check function for check.sh.                                           |


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
                │        ├── prepare_master.sh
                │        ├── create_slave.sh
                │        ├── promote.sh
                │        ├── reinstate.sh
                │        ├── switchover.sh
                │        ├── backup.sh
                │        ├── restore.sh
                │        ├── check.sh
                │        ├── root.sh
                │        ├── install_pgoperate.sh
                │        ├── bundle.sh       
                │        └── VERSION
                │
                ├─── etc ┐
                │        ├── parameters_mycls.conf.tpl
                │        ├── parameters_<alias>.conf        
                │        └── ...
                │
                ├─── log
                │
                ├─── lib ┐
                │        ├── check.lib
                │        └── shared.lib
                │
                └─── bundle ┐
                            ├── install_pgoperate.sh
                            └── pgoperate-<version>.tar
````

Each installation will have its own single parameters file. The format of the parameter filename is important, it must be `parameters_<alias>.conf`. Where `alias` is the pgBasEnv alias of the PostgreSQL cluster. It will be used to set its environment.

The parameter file includes all parameters required for cluster creation, backup, replication and monitoring. Everything in one place. All pgOperate scripts will use this parameter file for the current alias to get required values. It is our single point of truth.

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

It will contain scripts related to current cluster.

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

We will create new empty directory to initialize 12 data directory.
```
mkdir data_new
```

Initialize new 12 data directory:
```
initdb -D $PGSQL_BASE/data_new
```

Now stop the cluster:
```
sudo systemctl stop postgresql-tt1
```

Now set variables and execute upgrade:
```
export PGDATAOLD=$PGSQL_BASE/data
export PGDATANEW=$PGSQL_BASE/data_new
export PGBINOLD=/usr/pgsql-11/bin
export PGBINNEW=/usr/pgsql-12/bin
pg_upgrade --old-port=$PGPORT --new-port=$PGPORT --old-options="--config_file=$PGSQL_BASE/etc/postgresql.conf" --new-options="--config_file=$PGSQL_BASE/etc/postgresql.conf"
```

After the upgrade, rename controlfile in old home. It will prevent the cluster from start and to be detected by pgBasEnv:
```
mv $PGSQL_BASE/data/global/pg_control $PGSQL_BASE/data/global/pg_control.old
```

Now replace directories:
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

Execute generate_unitfile.sh:
```
$PGOPERATE_BASE/bin/generate_unitfile.sh
...
INFO: Execute as root /u00/app/pgsql/tt1/scripts/update_unitfile.sh.
```

Switch to root and execute update_unitfile.sh to generate new unit file.
```
/u00/app/pgsql/tt1/scripts/update_unitfile.sh
```

Now we can start upgraded 12 cluster:
```
systemctl start postgresql-tt1
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
| **PG_START_SCRIPT**       |                      | Custom script to start the cluster. If defined, then it will be used to start the cluster.                                             |
| **PG_STOP_SCRIPT**       |                      | Custom script to stop the cluster. If defined, then it will be used to stop the cluster.                                             |
| **BACKUP_LOCATION**       | `$PGSQL_BASE/backup`                     | Directory to store backup files.                                             |
| **BACKUP_REDUNDANCY**     | `5`                                      | Backup redundancy. Count of backups to keep.                                                 |
| **BACKUP_RETENTION_DAYS**  | `7`                                      | Backup retention in days. Keeps backups required to restore so much days back.  This parameter, if set, overrides BACKUP_REDUNDANCY.                                                |
| **MASTER_HOST**           |                                          | Replication related. The name or ip address of the master cluster.           |
| **MASTER_PORT**           |                                          | Replication related. The PORT of the master cluster. If not specified then `$PGPORT` will be used.           |
| **REPLICATION_SLOT_NAME** | `slave001, slave002, slave003  | Replication related. Replication slot names to be created in master cluster. More than one replication slot separated by comma can be specified.|
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


## install_pgoperate.sh
---

Script to install pgOperate on the host.

Copy files from **bundle** folder to some location and execute **install_pgoperate.sh** to install pgOperate.



## root.sh
---

Script to execute root actions. It can be executed only one time after pgOperate installation.

It will add `01_postgres` file into `/etc/sudoers.d` to allow `postgres` user to `start/stop/status/reload` the `postgresql-<alias>` service with sudo privileges.





## pgoperate
---

`pgoperate` is main interface to call all the pgOperate scripts.

During installation the alias pointing to it will be created in pgBasEnv standard config file. That is why pgoperate can be called from any location.

But to call it from inside the scripts use full path like `$PGOPERATE_BASE/bin/pgoperate`

```
pgoperate --help


Available options:

  --version                Show version.
  --create-cluster         Create new PostgreSQL Cluster
  --add-cluster            Add existing cluster to pgOperate environment
  --remove-cluster         Removes PostgreSQL Cluster
  --backup                 Backup PostgreSQL CLuster
  --restore                Restore PostgreSQL Cluster
  --check                  Execute monitoring checks
  --create-slave           Create Slave PostgreSQL Cluster and configure streaming replication
  --promote                Promote Slave cluster to Master
  --reinstate              Convert old Master to Slave and start streaming replication
  --prepare-master         Prepare PostgreSQL Cluster for Master role
  --switchover             Switchover to standby site.

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

At the end of installation script will offer to execute `root.sh` as root user.

Switch to root and execute `root.sh`. It will create `postgresql-<alias>` unit file in /etc/systemd/system for systemctl daemon. Cluster will be started with systemctl and in-cluster actions will be executed.

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

At the end of installation script will offer to execute `root.sh` as root user.

Switch to the root user and execute `root.sh` if you want. It will create `postgresql-<alias>` unit file in /etc/systemd/system for systemctl daemon.

If you already use some other systemctl unit file or some other way to control your PostgreSQL instance, then use `--start-script` and `--stop-script` parameters to specify custom scripts to control the instance.

These two parameters will set `PG_START_SCRIPT` and `PG_STOP_SCRIPT` in `parameters-<alias>.conf` file. You can set them also later.

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






## prepare_master.sh
---

Script to create replica user and configure PostgreSQL as master site.

All these commands will be executed by `create_cluster.sh`, this script can be used in some scenarios when standby fails to connect to master,
then it is good to execute this script to be sure that all replication parameters and objects are in place.

It will check `track_commit_timestamp` parameter, if it is set to 'on'. If this parameter is 'on', then script will just reload configuration.
If `track_commit_timestamp` parameter is not set, then it will be set to 'on' and cluster will be restarted!

It will set next parameters in `$PGSQL_BASE/etc/postgresql.conf`
```
wal_level             to "replica"
max_wal_senders       to "10"
max_replication_slots to "10"
```

It will check and update `$PGSQL_BASE/etc/pg_hba.conf` file to allow replica user to connect over TCP with `scram-sha-256` encrypted password over replication protocol.

It will create replication slot(s) listed in `$REPLICATION_SLOT_NAME`.

It will create `REPLICA` user with replication permission and password `$REPLICA_USER_PASSWORD`.

Execute as postgres:
```
pgoperate --prepare-master
```



## create_slave.sh
---

Script to create standby PostgreSQL cluster.

This script requires `MASTER_HOST`, `REPLICATION_SLOT_NAME` and `REPLICA_USER_PASSWORD` parameters to be set in `$PGSQL_BASE/etc/parameters_<alias>.conf` file.

Note that, if `REPLICATION_SLOT_NAME` has more than one slot, then first one will be used in master connection string in `recovery.conf` or postgresql.conf file.

Script will set parameter `hot_standby` to "on" in `postgresql.conf`.

It will also set master related parameters, as a preparation for possible master role.

`pg_basebackup` utility will be used to duplicate all data files from master site.

It will also update `recovery.conf` or `postgresql.conf` file with related parameters.

If `$PGDATA` will not be empty, then error message will displayed. `$PGDATA` must be emptied or `--force` option must be used.


Execute as postgres:
```
sudo systemctl stop postgresql-<alias>
rm -Rf $PGDATA/*
pgoperate --create-slave

- or -

pgoperate --create-slave --force

```

At the end, script will check the status of WAL receiver, if it is "Streaming" then success message will be displayed.




## promote.sh
---


Can be executed to promote standby to master.

Master status will be checked, if it is still running, then database will not be promoted.

Can be used for Failover and Switchover operations.

For Switchover:

1. Stop master site:
  `sudo systemctl stop postgresql-<alias>`
2. Execute promote.sh on standby site
  `pgoperate --promote`
3. Start old master as new standby 
  `pgoperate --reinstate`  
  

Execute as postgres:
```
pgoperate --promote
```



## reinstate.sh
---

Script to start old primary as new standby server.
   
Script will try to start as standby in next order:

1. Start old primary as new standby
2. If it fails to sync with master, then sync with `pg_rewind`
3. If it again fails then script will recreate standby from master if `-f` option was specified

Available options:
```
    `-m <hostname>`   Master host. If not specified master host from parameters_<alias>.conf will be used.
    `-f`              Force to recreate standby from master if everything else fails.
    `-r`              Execute only `pg_rewind` to synchronize primary and standby.
    `-d`              Recreate standby from master.
```

Execute as postgres:
```
pgoperate --reinstate -f
```


## switchover.sh
---

With this script you can perform fully automatic switchover to standby.

Script can be executed on master or standby site.

If it will be executed on standby site, then script will identify master and execute on master site.

If there is more than one standby configured then following rules will be used:
1. If there is synchronous standby configured, then it will be used.
2. Asynchronous standbys will be sorted by lag, the standby with smallest lag will be used.

Available options:
```
    `-f`            Force to recreate new standby from scratch if old master will not be able to sync with new master.
                    Check the help of the reinstate.sh script.
```

Execute as postgres:
```
pgoperate --switchover
```



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

Then check function must be defined in `check.lib` file.

If check defined then function with the specified name will be executed from `check.lib` library.

Function must return 0 on check success and not 0 on check not passed.

Number of times check was not passed will be counted by check.sh, check function do not require to implement this logic.
If `PG_CHECK_<CHECK NAME>_OCCURRENCE` is defined, then `check.sh` will alarm only after defined number of negative checks.


There are special input and output variables that can be used in check functions:

Input variables:
    `<function_name>_THRESHOLD`   - Input variable, if there was threshold defined, it will be assigned to this variable.
    `<function_name>_OCCURRENCE`  - Input variable, if there was occurrence defined, it will be assigned to this variables.
 
    `$PG_BIN_HOME`  - Points to the bin directory of the postgresql.
    `$SCRIPTDIR`    - The directory of the check script location. Can be used to create temporary invisible files for example. 
    `$PG_AVAILABLE` - Will be true if database cluster available and false if not available.

Next functions can be called from check functions:
    `exec_pg <cmd>`   - Will execute cmd in postgres and return psql return code, output will go to stdout.
    `get_fail_count` - Will get the number of times this function returned unsuccessful result. It will be assigned to `<function_name>_FAILCOUNT` variable.

Output variables:
    `<function name>_PAYLOAD`     - Output variable, assign output text to it.
    `<function name>_PAYLOADLONG` - Output variable, assign extra output text to it. \n can be used to divide text to new lines.


When function returns 0 or 1, then it is also good to return some information to the user. This information can be passed over `<function name>_PAYLOAD` variable.
If some big amount of data, extra information must be displayed, then pass it over `<function name>_PAYLOADLONG` variable.

Check `check.lib` file for check function examples.

There are already few predefined checks.


