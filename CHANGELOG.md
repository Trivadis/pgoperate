
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