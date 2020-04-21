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

