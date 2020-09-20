# TVD-PgOperate Tool-set to operate PostgreSQL clusters
---

## Prerequisites

PgOperate requires PgBaseEnv.

First PgBaseEnv must be installed.


## PostgreSQL cluster management scripts developed to automate regular tasks.

| Script                  | Description                                                            |
| ----------------------- | ---------------------------------------------------------------------- |
| **create_cluster.sh**   | Creates new PostgreSQL cluster.                                        |
| **prepare_master.sh**   | Prepares PostgreSQL cluster to master role.                            |
| **create_slave.sh**     | Creates standby cluster.                                               |
| **promote.sh**          | Promotes standby to master.                                            |
| **reinstate.sh**        | Starts old master as new standby.                                      |
| **backup.sh**           | Backup PostgreSQL cluster.                                             |
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
| **pgoperate**            | Wrapper around all PgOperate scripts. Central execution point.         |
| **install_pgoperate.sh** | PgOperate installation script.                                         |
| **root.sh**              | Script to execute root actions after installation.                     |
| **bundle.sh**            | Generates installation bundle for PgOperate.                           |




## General concept

Each PostgreSQL cluster installation using PgOperate scripts will have following structure.

Like postgresql itself, we create single directory, one level over `PGDATA`, which will act as the base for the cluster.

We call this directory `PGSQL_BASE`.

The directory structure of the PgOperate itself is as follows:

```
$PGOPERATE_BASE ┐
                │
                ├─── bin ┐
                │        ├── pgoperate
                │        ├── create_cluster.sh
                │        ├── prepare_master.sh
                │        ├── create_slave.sh
                │        ├── promote.sh
                │        ├── reinstate.sh
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
                ├─── lib ┐
                │        ├── check.lib
                │        └── shared.lib
                │
                └─── bundle ┐
                            ├── install_pgoperate.sh
                            └── pgoperate-<version>.tar
````

Each installation will have its own single parameters file. The format of the parameter filename is important, it must be `parameters_<alias>.conf`. Where `alias` is the PgBaseEnv alias of the PostgreSQL cluster. It will be used to set its environment.

Parameter file includes all parameters required for cluster creation, backup, replication and monitoring. Everything in one place. All PgOperate scripts will use this parameter file for the current alias to get required values. It is our single point of truth.

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

`postgresql-<n>.log` - Logging collector output files. By default PgOperate will use day of the month in place of n.

Sub-folder `tools` will include output logs from all the PgOperate scripts. Any script executed will log its output into this directory. Log filename will include script name and timestamp. First two lines of the logfile will be the list of arguments used to execute script and the current user id.

#### cert

Is the folder to store all server side certificate files for ssl connections.

If `ENABLE_SSL` parameter was set to "on" in `parameters_<alias>.conf` file then during cluster creation, cert files will be copied to this folder.

#### backup

Is the default and recommended location for the backups. Backup script will create backups in this folder. It is recommended to link this folder to some network attached storage. Especially is case of primary/standby configuration.

#### arch

In case of archive log mode, WAL files will be archived to **backup** sub-folder. This **arch** directory must be local. It will be used as fail-over location if **backup** folder will not be available.








## parameters.conf
---

It is a single parameter file which includes variables used by all management scripts.

`parameters.conf` must be in the same directory as the script to be executed.

Script can be called from any other location, it will always look to its base directory and not to the current directory to find parameters.conf.

Permissions of the `parameters.conf` is `0600` and must not be changed.

Parameters:

| Parameter                 | Default value                            | Description                                                                  |
| ------------------------- | ---------------------------------------- | ---------------------------------------------------------------------------- |
| **PGSQL_BASE**            | `/u00/app/pgsql`                         | Base directory under which all other directories will be created.            |
| **PG_ENCODING**           | `UTF8`                                   | The character set of the database cluster.                                   |
| **PG_DATABASE**           | `defdb`                                  | Database name which will be created after installation.                      |
| **PG_ENABLE_CHECKSUM**    | `yes`                                    | Checksums on data pages. Performance penalty. Cannot be changed after setup. |
| **PG_SUPERUSER**          | `postgres`                               | The name of the superuser to create during setup.                            |
| **PG_SUPERUSER_PWDFILE**  |                                          | The file name which contains the password of superuser in it. It must be file without path. File must be in the scripts directory. After `install.sh` file permissions will be updated so that only postgres can access it. If not specified, then install.sh will fail.                             | 
| **PCTMEM**                | `30`                                     | The percent of the host memory to use for PostgreSQL shared buffers.         |
| **PACKAGE_VERSION**       | `10`                                     | PostgreSQL package version to be installed.                                  |
| **PG_SERVICE_FILE**       | `/etc/systemd/system/postgresql.service` | Service file name which will be created during setup.                        |
| **ENABLE_SSL**            | `yes`                                    | Will try to copy `CA_CERT`, `SERVER_CERT` and `SERVER_KEY` to the `$PGSQL_BASE/cert` directory and then enable SSL connections to cluster. If some of these certificates will not be found then `ENABLE_SSL` will be forced to "no".                                                                 |
| **CA_CERT**               |                                          | File with CA certificate. Usually called root.crt.                           |
| **SERVER_CERT**           |                                          | File with SSL server certificate. Usually called server.crt.                 |
| **SERVER_KEY**            |                                          | File with SSL server private key. Usually called server.key.                 |
| **PG_DEF_PARAMS**         | Default value is below                   | String variable which includes the init parameters separated by new line. These parameters will be set in postgresql.conf during installation. `shared_buffers` is set absolute value `200MB`, it will be overwritten by `PCTMEM` if defined. If `PCTMEM` is null then this absolute value will be set. |
| **BACKUP_LOCATION**       | `$PGSQL_BASE/backup`                     | Directory to store backup files.                                             |
| **BACKUP_REDUNDANCY**     | `5`                                      | Not used by current version.                                                 |
| **MASTER_HOST**           |                                          | Replication related. The name or ip address of the master cluster.           |
| **REPLICATION_SLOT_NAME** | `slave001`                               | Replication related. Replication slot name to be created in master cluster. More than one replication slot separated by comma can be specified.|
| **REPLICA_USER_PASSWORD** |                                          | Replication related. Password for user REPLICA which will be created on master site. Slave will use this credential to connect to master.|


`PG_CHECK_%` parameters described in `check.sh` section.

**PG_DEF_PARAMS** default value is 
```
    "max_connections=1000
     shared_buffers=200MB
     huge_pages=off
     password_encryption=scram-sha-256
     logging_collector = on
     log_directory = '$PGSQL_BASE/log'
     log_filename = 'postgresql-%d.log'
     log_truncate_on_rotation = on
     log_rotation_age = 1d
     log_rotation_size = 0"
 ```




## install.sh
---

*MUST BE EXECUTED AS ROOT*

Script to install PostgreSQL and create new cluster.

There are different ways to install postgresql binaries. To not update `install.sh` for different installation methodes,
there is `install_package.lib` file. It includes `install_package()` function. This function will be called to install binaries.
By default it uses "yum install". You can use variables from parameters.conf in this function. The most useful one is 
`${PACKAGE_VERSION}`, it defines postgresql major version.

Cluster will be created with properties defined in parameters.conf file.

`/etc/systemd/system/postgresql.service` file will be created to allow cluster management over systemctl.

Next steps will be performed after binaries installation and cluster setup:

* Database `$PG_DATABASE` will be created.
* Schema with same name `$PG_DATABASE` will be created.
* User with same name `$PG_DATABASE` and without password will be created. This user will be owner of `$PG_DATABASE` schema.
* Replication related parameter will be adjusted
* Replication user and replication slot(s) will be create
* `pg_hba.conf` file will be updated
* `01_postgres` file will be added into `/etc/sudoers.d` to allow `postgres` user to `start/stop/status` the `postgresql` service with sudo

Local connection without password will be possible only by postgres user and root.

Execute as root:

```
# Create text file with superuser password:
cd <Scripts directory>
vi passwd.file

# Then execute install.sh
./install.sh
```

If some problems will happen during `install.sh` then it is possible to remove all and try again. To remove execute `removepgsql.sh` script.




## preparemaster.sh
---

*CAN BE EXECUTED AS ROOT OR POSTGRES*

Script to create replica user and configure PostgreSQL as master site.

All these commands will be executed by `install.sh`, this script can be used in some scenarios when standby fails to connect to master,
then it is good to execute this script to be sure that all replication parameter and objects are in place.

It will check `track_commit_timestamp` parameter, it must be 'on'. If this parameter is already set, then script will just reload configuration.
If `track_commit_timestamp` parameter is not set, then it will be set to on and cluster will be restarted!

It will set next parameters in `$PGSQL_BASE/etc/postgresql.conf`
```
wal_level             to "replica"
max_wal_senders       to "8"
max_wal_size          to "1GB"
max_replication_slots to "10"
```

It will check and update `$PGSQL_BASE/etc/pg_hba.conf` file to allow replica user to connect over TCP with `scram-sha-256` encrypted password for replication purposes.

It will create replication slot(s) listed in `$REPLICATION_SLOT_NAME`.

It will create `REPLICA` user with replication permission and password `$REPLICA_USER_PASSWORD`.

Execute as root:
```
cd <Scripts directory>
./preparemaster.sh
```



## createslave.sh
---

*CAN BE EXECUTED AS ROOT OR POSTGRES*

Script to create standby PostgreSQL cluster.

This script requires `MASTER_HOST`, `REPLICATION_SLOT_NAME` and `REPLICA_USER_PASSWORD` parameters to be set in `parameters.conf` file.

Note that, if `REPLICATION_SLOT_NAME` has more than one slot, then first one will be used in master connection string in `recovery.conf` file.

Script will set init parameter `hot_standby` to "on" in `postgresql.conf`.

It will do also same parameter settings as in `preparemaster.sh`.

It will stop the PostgreSQL service.

Then it will use `pg_basebackup` utility to duplicate all data files from master site.

It will also update `$PGSQL_BASE/data/recovery.conf` file. This file instructs PostgreSQL to do non-stop recovery by streaming WAL entires from Master site. 

Execute as root:
```
cd <Scripts directory>
./createslave.sh
```

At the end, script will show the status of wal receiver, it must be "Streaming"




## createuser.sh
---

*CAN BE EXECUTED AS ROOT OR POSTGRES*

Script to create user in PostgreSQL.

* User will be created.
* Schema with same name will be created. User will be assigned all privileges on this schema. User will not be
  set as owner of this schema, to prevent him granting privileges on it to others. Only this user can create objects in it.
* All privileges will be granted on `$PG_DATABASE` schema.


Arguments:

1 - `USERNAME` - PostgreSQL Role (User) name

2 - `PASSWORD` - Optional Password. If not provided Role will be created without password.


Execute as root:
```
cd <Scripts directory>
./createuser.sh myuser mypassword
```




## backup.sh
---

*CAN BE EXECUTED AS ROOT OR POSTGRES*

Script to backup PostgreSQL cluster on Primary or Standby site.

The tar.gz archive will be generated and saved in `$BACKUP_LOCATION` directory structure.

Please check the script header for detailed information.

Backup will be made from online running cluster, it is hot full backup.

Following backup strategies possible:
 * Database backup on master site and archived WAL backup on master site
 * Database backup on standby site and archived WAL backup on standby site
 * Database backup on standby site and archive WAL backup on primary site (Recommended)

Backups can be made also in no-archivelog mode, then restore will be possible only on backup end time.

To implement backup on standby and archived WAL on master strategy:
  1. Enable WAL archiving on master by executing:
           `./backup.sh enable_arch`
     Archive location will be `$PGSQL_BASE/arch`, it can be NFS mount point, link to NFS directory or local directory.
  2. Execute regular backups on standby site. Do not enable archive mode on standby:
           `./backup.sh`

In such scenario if primary fails then execute `restore.sh` on primary it will use `$PGSQL_BASE/arch` as well as WAL source.
If `BACKUP_LOCATION` is not shared between master and standby, then copy it to primary before restore.

```
./backup.sh help
```

Arguments:
                     list -  Script will list the contents of the `BACKUP_LOCATION`.
              enable_arch -  Sets the database cluster into archive mode. Archive location will be set to `PGSQL_BASE/arch`.
                             No backup will taken. Cluster will be restarted!
  backup_dir=<directory>  -  One time backup location. Archive log location will not be switched on this destination.

 To make backup, execute without any arguments.







## restore.sh
---

*CAN BE EXECUTED AS ROOT OR POSTGRES*

Script to restore PostgreSQL cluster from backup.

It will stop running PostgreSQL cluster.

Will remove contents of `PGSQL_BASE/data`.

If any external tablespaces exists in backup then their locations will be also cleared before restore.


Script can be executed without any parameters. In this case it will restore from the latest available backup.

 Arguments:
 ```
    list                        - Script will list the contents of the `BACKUP_LOCATION`.
    backup_dir=<directory>      - One time backup location. Will be used as restore source.
    from_subdir=<subdir>        - Execute restore from specified sub-directory number. Use 'list' to check all sub directory numbers. It must be number without date part.
    until_time=<date and time>  - To execute Point in Time recovery. Specify target time. Time must be in `\"YYYY-MM-DD HH24:MI:SS\"` format.
    pause                       - Will set `recovery_target_action` to pause in `recovery.conf`. When Point In Time will be reached, recovery will pause.
    shutdown                    - Will set `recovery_target_action` to shutdown in `recovery.conf`. When Point In Time will be reached, database will shutdown.
    verify                      - If this argument specified, then no actual restore will be execute. Use to check which subfolder will be used to restore.
```

 Examples:
  Restore from last (Current) backup location:
```
    ./restore.sh
```
  Restore from subdirectory 3:
```
    ./restore.sh from_subdir=3
```

  First verify then restore to Point in Time `\"2018-10-17 11:25:00\"`:
```
    ./restore.sh until_time=\"2018-10-17 11:25:00\" verify
    ./restore.sh until_time=\"2018-10-17 11:25:00\"
```

Script by default looks to `BACKUP_LOCATION` from `parameters.conf` for backups.

To restore from some other location, use `backup_dir` argument.

You can also list first its contents:
```
./restore.sh list backup_dir=/tmp/pgbackup

Backup location: /tmp/pgbackup
=========================================================================
|Sub Dir|      Backup created|WALs count|Backup size(MB)|  WALs size(MB)|
=========================================================================
|      4| 2019-08-03 12:09:09|         0|              5|              1| <--- Oldest backup dir
|      5| 2019-08-03 12:09:14|         0|              5|              1| <--- Current backup dir
=========================================================================
Number backups: 2
```

Then you can restore from `subdir` or by specifying `until_time`:
```
./restore.sh backup_dir=/tmp/pgbackup from_subdir=4
```




## promote.sh
---

*CAN BE EXECUTED AS ROOT OR POSTGRES*

Can be executed to promote standby to master.

Master status will be checked, if it is still running, then database will not be promoted.

Can be used for Failover and Switchover.

For Switchover:

1. Stop normal master site:
  `sudo systemctl stop postgresql`
2. Execute promote.sh on standby
  `./promote.sh`
3. Reinstate old master as new standbykmjn 
  `./reinstate.sh` 
  
  



## reinstate.sh
---

*CAN BE EXECUTED AS ROOT OR POSTGRES*

Script to start old primary as new standby server.
   
Script will try to start as standby in next oder:

1. Start old primary as new stanbdy
2. If it fails to sync with master, then sync with `pg_rewind`
3. If it again fails then script will recreate standby from master if `-f` option was specified

Available options:
```
    `-m <hostname>`   Master host. If not specified master host from parameters.conf will be used.
    `-f`              Force to recreate standby from master if everything else fails.
    `-r`              Execute only `pg_rewind` to synchronise primary and standby.
    `-d`              Recreate standby from master.
```





## check.sh
---

*CAN BE EXECUTED AS ROOT OR POSTGRES*

Check script for PostgreSQL.

It is small framework to create custom checks.

As fist step check must be defined in `parameters.conf` file with next parameters:
```
PG_CHECK_<CHECK NAME>=<check function name>
PG_CHECK_<CHECK NAME>_THRESHOLD=
PG_CHECK_<CHECK NAME>_OCCURRENCE=
```

Then check function must be defined in `check.lib` file.

If check defined then function with the specified name will be executed from `check.lib` library.

Function must return 0 on check success and 0 on check not passed.

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

There are already few predefined base checks.







## removepgsql.sh
---

*MUST BE EXECUTED AS ROOT*

Script to completely remove PostgreSQL installation from the server.

PostgreSQL installation will be completely removed from the server, including postgresql OS user and all databases.

Use this script with caution, it will ask before for the confirmation.


