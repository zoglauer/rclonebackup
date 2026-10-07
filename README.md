# Tools to backup local home directories to raid, and raids to wasabi

## Section 1: Backing up home directories to a RAID 

### Usage examples:

```
sudo bash backup_homes.sh --name=atlas --folder=backups
```

### Cron entry

```
sudo crontab -e
```
```
30 */8 * * * bash /home/andreas/Science/Software/rclonebackup/backup_homes.sh --name=atlas --folder=backups >> /tmp/backup_homes_atlas_cron.log 2>&1
```

### Backing up homes to an NFS-mounted raid

Everything should work if the RAID is local.
If it is remote, we have to work around root squashing.
However, this will not preserve file ownership.


### Server setup

1. Create the default backup user if they do not exist yet:
```
   sudo groupadd -g 2100 data-backup
   sudo useradd -r -u 2100 -g 2100 -d / -s /usr/sbin/nologin data-backup
```
2. Create the backup folder for the machine which is backed up, private to that user:
```
   sudo mkdir -p /volumes/atlas/backups/galatea
   sudo chown 2100:2100 /volumes/atlas/backups/galatea
   sudo chmod 700 /volumes/atlas/backups/galatea
```
3. In /etc/exports (one line per client):
```
   /volumes/atlas    galatea(rw,sync,no_subtree_check,root_squash,anonuid=2100,anongid=2100)
```
4. Apply: `sudo exportfs -ra`

If the setup is wrong, backup_homes.sh should give an error message.


### Restoring a home directory

Copy it back as root, then restore ownership:
```
sudo rsync -ah /volumes/atlas/backups/galatea/andreas /home/
sudo chown -R andreas:andreas /home/andreas
```
Notes: group ownership and files owned by other users are lost. Read-only
directories come back writable (the backup forces u+rwx on directories).


## Section 2: Backing up with rclone to wasabi

## Usage examples:

```
sudo bash backup_rclone_wasabi.sh --name=[Volume NAME, not location]
```

## Assumptions:
1. rclone v1.51 or higher is installed
2. The local drive is mounted under /volumes/\<NAME\> where \<NAME\> is supplied at the command line via the --name option
3. The name of the target remote is \<NAME\>encrypted, where \<NAME\> is the name of the mounted directory supplied at the command line 
4. The rclone.conf file has been copied into this directory


## Data cleanup:
rclone will complain about dangling links and will not fully sync (i.e. delete any files) for that reason
To convert dangling links to empty files do:
```
for i in `find -L . -type l`; do rm ${i}; touch ${i}; done
```

## crontab:
```
sudo crontab -e
```

```
30 */8 * * * bash /home/andreas/Science/Software/rclonebackup/backup_homes.sh --name=atlas --folder=backups >> /tmp/backup_homes_atlas_cron.log 2>&1
```



