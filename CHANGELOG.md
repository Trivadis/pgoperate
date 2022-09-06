## 4.4
* Improved replication slot and primary connect info handling during switchover/failover/reinstate operation

## 4.3
* New parameter `LINK_CERT` added to control if SSL certificates must be copied or linked
* Bug fixed related to deletion of obsolete backups in `pgoperate --backup` command

## 4.2 
* New parameter `PG_WAL_SEGSIZE` to define a custom WAL segment size [(issue #20)](https://github.com/Trivadis/pgoperate/issues/20)
* Changed the path for the pgoperate daemon PID file from $PGOPERATE_BASE/bin to $PGOPERATE_BASE/run/pgoperate-deamon.pid [(issue #16)](https://github.com/Trivadis/pgoperate/issues/16)
* Enhanced the documentation about [SELinux](https://github.com/Trivadis/pgoperate/#selinux) considerations related to pgoperate daemon [(issue #2)](https://github.com/Trivadis/pgoperate/issues/2)
* Bug fixed related to `pgoperate --standbymgr --check` command (consider new parameter names `--local-host` and `--remote-host`) [(issue #13)](https://github.com/Trivadis/pgoperate/issues/13)

## 4.1
* New parameter `RESTORE_COMMAND` added to conf file. If `DISABLE_BACKUP_SCRIPTS` is activated, `restore_command` will be set to `RESTORE_COMMAND` in postgresql.conf on standby sites [(issue #14)](https://github.com/Trivadis/pgoperate/issues/14)
* Added two new aliases for pgOperate to pgBasEnv configuration:
  * cdpo : change to $PGOPERATE_BASE
  * cdpo.etc: change to $PGOPERATE_BASE/etc
* Fixed an issue with standbymgr tool and repslots [(issue #15)](https://github.com/Trivadis/pgoperate/issues/15)

## 4.0

Minimum required pgBaseEnv version is 1.9.

This version introduces new concept for standby management. Now each cluster in the configuration must be assigned a uniqname, which will identify the cluster in the configuration.

In all standby related operation the uniqname will be used.

Each cluster will have following properties:
* Node number
* Uniqname
* Host

Host will be defined at standby creation, it can be any hostname, including FQDN or IP address. Host will be used for ssh communication and to establish replication connection. It will be used in `primary_conninfo`.

The uniqname will be used in replication slot names and as standby names.

Switchover and all other commands accept now only uniqname as a target.

If you add your first standby, then uniqname must be defined also for master node. To add fisrt standby use command like this:
```
pgoperate --standbymgr --add-standby --uniqname site2 --host 192.168.56.102 --master-uniqname site1 --master-host node1
```

As you can see, we provide `--master-uniqname` and `--master-host` arguments. It is required only fisrt time.

We also used IP for site2 and nodename for site1.

To switchover to site2 we will execute now:
```
pgoperate --standbymgr --switchover --target site2
```

The pgOperate deamon process was also modified according this new concept.

### Upgrade to v4.0

First update pgBaseEnv to version 1.9.

If you dont have any standby clusters yet, then do the update as usual.

If you already have a standby cluster managed by pgOperate, then you have two options:
1. Remove the standby and then clear the $PGOPERATE_BASE/db folder on master site. After installing v4.0 create your standby again with assigning uniqnames to master and standby.
2. Update pgOperate to 4.0 and do manual updates.

If you will go with option 2, then you will need:
1. Install new pgOperate 4.0
2. On master site. Go to $PGOPERATE_BASE/db/repconf_<alias> of your cluster. Go into each subdirectory and create files `4_uniqname`, write uniqname into it. Then execute `pgoperate --standbymgr --sync-config`.
3. Recreate replication slots on master. New replication slot names must include uniqname, like `slot_<uniqname>`.
4. Update `primary_conninfo` on all standbys, change `application_name` to the uniqname of each modified standby.
5. Update `primary_slot_name` on all standbys, change it to `site_<uniqname>`, where uniqname is the uniqname of the corresponding standby.




## 3.5
* check.sh supports text (-t|--text) and json output (-j|--json)
* check.sh supports specific metric checks (-c|--check)
* check.sh output contains the current value
* custom check.sh metrics moved from check.lib to custom_check.lib. Do not use check.lib for your custom metrics anymore because it will be overwritten by the update


## 3.0

New features added in this release:
* pgoperated now able to initiate failover of the master instance after predefined failed attempts to restart the instance.
* New parameters in conf file, AUTOFAILOVER and FAILCOUNT. If AUTOFAILOVER enabled then after FAILCOUNT attempts failover will be initiated. Failover target will be next healthy and available standby with lowest node number. Old primary will be left in REINSTATE status. Pgoperated will try to reinstate old master periodically.
* New options added to standbymgr, --set-sync and --set-async. We can easily set any target standby to synchronous replication mode or to asynchronous mode. The --status option will also output sync mode of the standby.
* New parameter DISABLE_BACKUP_SCRIPTS to disable all backup/restore related scripts if any third party backup tool will be used.
* Other minor changes and improvement.


## 2.0

Major change in this version is a new script `standbymgr.sh` which replaces all previous standby management scrips `prepare_master.sh`, `promote.sh`, `reinstate.sh` and `switchover.sh`.

`standbymgr.sh` is integrated into wrapper script `pgoperate` and can be executed using `--standbymgr` argument.

Now it is possible to have more than one standby cluster in the configuration. Adding new standby databases is very simple and requires single call on master site.

Available options are:

```
 --check --target <hostname>          Check the SSH connection from local host to target host and back.
 --status                             Show current configuration and status.
 --sync-config                        Synchronize config with real-time information and distribute on all configured nodes.
 --add-standby --target <hostname>    Add new standby cluster on spevified host. Must be executed on master host.
 --switchover [--target <hostname>]   Switchover to standby. If target was not provided, then local host will be a target.
 --failover [--target <hostname>]     Failover to standby. If target was not provided, then local host will be a target.
                                        Old master will be stopped and marked as REINSTATE in configuration.
 --reinstate [--target <hostname>]    Reinstate old primary as new standby.
 --prepare-master [--target <hostname>]  Can be used to prepare the hostname for master role.
```


## 1.9

*   Version 1.9 brings new high availability solution for the clusters managed by pgOperate. Usualy each postgresql instance has its own associated systemd unit file, which controls its availability. The `PGPORT` and `PGDATA` parameters are hard coded into it. Adding or removing the clusters require corresponding actions on root side. PgOperate will use its own daemon process `pgoperated` which will run under postgres owner user. It will have its assosiated systemd service file to survive host restarts, this systemd service will be set only one time with root.sh. Daemon will then control and provide high availability to all postgres clusters. In parameters.conf file of each cluster you can set inteded state of it, should it be `UP` or `DOWN`. For more details check "High availability" section in README.md file.

To upgrate to this version, next steps must be followed:

Download install script and tar file as usual, execute `intall_pgoperate.sh` to install new scripts.

Switch to root and deconfigure serivces for each of your cluster:

```
systemctl stop postgresql-pg13.service
systemctl disable postgresql-pg13.service
rm /etc/systemd/system/postgresql-pg13.service
systemctl daemon-reload
```

After all deconfigured, execute root.sh as root:
```
/var/lib/pgsql/tvdtoolbox/pgoperate/bin/root.sh
```

Then switch to postgres owner user and update your existing parameters.conf file of each cluster. Add next two parameters:
```
AUTOSTART=YES
INTENDED_STATE=UP
```

After you will save the file, daemon process will start all instances with intended state UP.

*   All scripts was updated to support new high availability model.
*   Different improvements. 
