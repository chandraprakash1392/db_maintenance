#!/bin/bash

logdir="/opt/scripts/logs"
logfile="$logdir/db_maint.log"
if [[ -d $logdir ]]
then
   truncate -s 0 $logfile
else
   mkdir $logdir
   touch $logfile
fi

# Checking the volume on which database is running
dbvol=`df -h /var/lib/couchdb | tail -1 | awk '{print $6}'`

#dbdisk=`lsblk | grep -B 1 "/var/lib/couchdb" | head -1 | awk '{print $1}'`
dbdisk=`df -h | grep "/var/lib/couchdb" | head -1 | awk '{print $1}'`
#dbdisk=/dev/$dbdisk

echo -en "Writing the volume and mount information about CouchDB...\n" > $logfile
echo -en "The database volume is $dbdisk\n" >> $logfile
echo -en "The database mount point is $dbvol\n" >> $logfile

# Storing the mount information of database volume
mount_info=`cat /etc/fstab | grep "/var/lib/couchdb"`
if [[ -z $mount_info ]]
then
    mount_info=`cat /etc/mtab | grep "/var/lib/couchdb"`
    echo $mount_info >> /etc/fstab
fi


# Stopping the database service
echo -en "Stopping database service at `date`... \n" > $logfile
server_name=`hostname`
if [[ $server_name == "couchdb1" ]] || [[ $server_name == "couchdb2" ]]
then
   service couchdb stop
   for pid in `ps aux | grep couch | grep -v "grep" | awk '{print $2}'`
   do
      kill -9 $pid
   done

else
   container_id=`docker ps | grep "couch" | awk '{print $1}'`
   docker stop $container_id
fi


# Checking type of FileSystem that's running the DB
echo -en "Checking filesystem type on the running database ...\n" >> $logfile
vol_type=`cat /etc/mtab | grep "/var/lib/couchdb" | awk '{print $3}'`
echo -en "The volume type in the current database server is $vol_type.\n" >> $logfile

echo -en "Unmounting the database volume now and starting the volume check at `date`...\n" >> $logfile
umount $dbvol

if [[ $vol_type == "xfs" ]]
then
    xfs_repair -m 8192 $dbdisk
else
    fsck -vy $dbdisk
fi


# Disk check completed. Mounting disks back and starting the services

echo -en "Mounting back the db volume at `date`...\n" >> $logfile
mount -av >> $logfile
if [[ $vol_type == "xfs" ]]
then
   xfs_fsr $dbvol
else
   e4defrag $dbvol
fi

server_name=`hostname`
if [[ $server_name == "couchdb1" ]] || [[ $server_name == "couchdb2" ]]
then
   service couchdb start

else
   container_id=`docker ps | tail -1 | awk '{print $1}'`
   docker start $container_id

fi

echo -en "Maintenance is now complete!!! Mounting back the volumes and starting database service at `date`...\n" >> $logfile
