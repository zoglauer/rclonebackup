# Backing up local drives to google drive

## Usage:

```
sudo bash backup_rclone --name=[Volume NAME, not location]
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
30 */8 * * * bash /home/andreas/Science/Software/rclonebackup/backup_rclone.sh -n=atlas -b=backups &>> /tmp/BackupAtlas.log
```



