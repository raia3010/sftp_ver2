#!/bin/bash
# set -x
JSON_FILE="/home/ubuntu/sftp_ver2/data.json"

# if [ "$(id -u)" -ne 0 ]; then
#     echo "This script must be run as root"
#     exit 1
# fi


timestamp (){
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $1"
}
checkAndCreateDirectory() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        timestamp "Directory '$dir' does not exist. Creating..."
        mkdir -p "$dir"
        if [ $? -eq 0 ]; then
            timestamp "Directory '$dir' created successfully."
        else
            timestamp "Failed to create directory '$dir'."
        fi
    else
        timestamp "Directory '$dir' already exists."
    fi
}
getInfoBackupTaskAndBackupProject(){
    projectBackup=$(jq -r --arg projectId "$1" '.backupProjects[] | select((.projectId | tostring) == $projectId) | (.projectId | tostring) + "?" + (.hostname | tostring) + "?" + .username + "?" + .password' "$JSON_FILE")
    backupTask=$(jq -r --arg projectId "$1" --arg backupTaskId "$2" '.backupProjects[] | select((.projectId | tostring) == $projectId) |
    .backupTasks[] | select((.backupTaskId | tostring == $backupTaskId)) |
    (.localSchedular | tostring) + "?" + (.remoteSchedular | tostring) + "?" + (.localPath | tostring) + "?" + .remotePath + "?" + (.localRetention | tostring) + "?" + (.remoteRetention | tostring)' "$JSON_FILE")
    conn="$projectBackup"?"$backupTask"
    echo "$conn"
}


getFoldersByBackupTaskIdAndBackupProjectId(){
    folder=$(jq -r --arg projectId "$1" --arg backupTaskId "$2" '.backupProjects[] | select((.projectId | tostring) == $projectId) |
    .backupTasks[] | select((.backupTaskId | tostring) == $backupTaskId) |
    .backupfolders[] | 
    (.folderId | tostring) + "?" + (.folderPath | tostring)' "$JSON_FILE")
    echo "$folder"    
}

mgetSftp (){
    sshpass -p "$1" sftp -oStrictHostKeyChecking=no "$2@$3" <<EOF
mget $4/* $5/$6/$(basename $7)/$8
bye
EOF
}
cleanupLocal(){
    local id1=$1
    local id2=$2
    conn=$(getInfoBackupTaskAndBackupProject "$id1" "$id2")
    IFS='?' read -r projectId hostname username password localSchedular remoteSchedular localPath remotePath localRetention remoteRetention <<< "$conn"
    # echo "$projectId" "$hostname" "$username" "$password" "$localSchedular" "$remoteSchedular" "$localPath" "$remotePath" "$localRetention" "$remoteRetention"
    echo "-------------------------Start Cleanup Task ID "$id2" in Project ID "$id1" in Local Storage"
    
    folder=$(getFoldersByBackupTaskIdAndBackupProjectId "$id1" "$id2")
    readarray -t listFolders <<< "$folder"
    for element in "${listFolders[@]}";do
        IFS='?' read -r folderId folderPath <<< "$element"
        localFolderPath=$localPath/$hostname/$(basename $folderPath)
        echo "------------------------------------Begin cleanup directory "$localFolderPath" with "$localRetention" retention---------------" 
        count=$(ls -lt $localFolderPath | grep "^d" | tail -n +"$(($localRetention + 1))" | wc -l )
        if [ $count -gt 0 ];
        then
            timestamp "There are $count folders need to be deleted"
            ls -t -d $localFolderPath/*/ | tail -n +"$(($localRetention + 1))"
            timestamp "Deleting..."
            ls -t -d $localFolderPath/*/ | tail -n +"$(($localRetention + 1))" | xargs rm -rf
            timestamp "Done"
        else
            timestamp "There are no folders to delete" 
        fi
        echo "------------------------End cleanup directory "$localFolderPath" with "$localRetention" retention----------------" 
    done
    echo -e "-----------------------Finish Cleanup Task ID "$id2" in Project ID "$id1" in Local Storage \n"

}
backupLocal(){
    local id1=$1
    local id2=$2
    conn=$(getInfoBackupTaskAndBackupProject "$id1" "$id2")
    IFS='?' read -r projectId hostname username password localSchedular remoteSchedular localPath remotePath localRetention remoteRetention <<< "$conn"
    # echo "$projectId" "$hostname" "$username" "$password" "$localSchedular" "$remoteSchedular" "$localPath" "$remotePath" "$localRetention" "$remoteRetention"
    echo "-------------------------Start Backup Task ID "$id2" in Project ID "$id1" to Local Storage"
    folder=$(getFoldersByBackupTaskIdAndBackupProjectId "$id1" "$id2")
    readarray -t listFolders <<< "$folder"
    for element in "${listFolders[@]}";do
        IFS='?' read -r folderId folderPath <<< "$element"
        dirBackup=$(date +"%Y-%m-%d_%H:%M:%S")
        timestamp "Begin backup folder "$folderPath" to Localstorage"
        localFolderPath=$localPath/$hostname/$(basename $folderPath)/$dirBackup
        mkdir -p $localFolderPath
        mgetSftp "$password" "$username" "$hostname" "$folderPath" "$localPath" "$hostname" "$folderPath" "$dirBackup"  
        timestamp "End backup folder "$folderPath" to Localstorage"
        echo
    done
    echo -e "-----------------------Finish Backup Task ID "$id2" in Project ID "$id1" to Local Storage\n"

}

backupRemote(){
    local id1=$1
    local id2=$2
    conn=$(getInfoBackupTaskAndBackupProject "$id1" "$id2")
    IFS='?' read -r projectId hostname username password localSchedular remoteSchedular localPath remotePath localRetention remoteRetention <<< "$conn"
    driveConnect="${remotePath//\//:}"
    echo "-------------------------Start Backup Task ID "$id2" in Project ID "$id1" to Remote Storage"
    localFolderPath=$localPath/$hostname
    rclone -v copy $localFolderPath "$driveConnect"/$hostname
    echo -e "-------------------------Finish Backup Task ID "$id2" in Project ID "$id1" to Remote Storage \n"
    
}

cleanupRemote(){
    local id1=$1
    local id2=$2
    conn=$(getInfoBackupTaskAndBackupProject "$id1" "$id2")
    IFS='?' read -r projectId hostname username password localSchedular remoteSchedular localPath remotePath localRetention remoteRetention <<< "$conn"
    echo "-------------------------Start Cleanup Task ID "$id2" in Project ID "$id1" in Remote Storage"
    folder=$(getFoldersByBackupTaskIdAndBackupProjectId "$id1" "$id2")
    readarray -t listFolders <<< "$folder"
    for element in "${listFolders[@]}";do
        IFS='?' read -r folderId folderPath <<< "$element"
        dir=$hostname/$(basename $folderPath)
        driveConnect="${remotePath//\//:}"
        folders=$(rclone lsd $driveConnect/$dir | awk '{print $5}' | sort -r | tail -n +"$(($remoteRetention + 1))")
        readarray -t list <<< "$folders"
        length=$(rclone lsd $driveConnect/$dir | awk '{print $5}' | sort -r | tail -n +"$(($remoteRetention + 1))" | wc -l)
        echo "------------------------------------Begin cleanup directory "$driveConnect/$dir" with "$remoteRetention" retention---------------" 
        if [ $length -gt 0 ];
        then
            timestamp "There are $length folders need to be deleted"
            echo "${list[@]}"
            timestamp "Deleting..."
            for element in "${list[@]}"; do
                rclone purge $driveConnect/$dir/$element
            done
            timestamp "Done"
            # ls -t -d $1/*/ | tail -n +"$(($2 + 1))" | xargs rm -rf
        else
            timestamp "There are no folders to delete" 
        fi
        echo "------------------------------------End cleanup directory "$driveConnect/$dir" with "$remoteRetention" retention---------------" 
    done
    echo -e "-------------------------Finish Cleanup Task ID "$id2" in Project ID "$id1" in Remote Storage \n"

}
createFolderLog(){
    local id1=$1
    local id2=$2
    conn=$(getInfoBackupTaskAndBackupProject "$id1" "$id2")
    IFS='?' read -r projectId hostname username password localSchedular remoteSchedular localPath remotePath localRetention remoteRetention <<< "$conn"
    # folderLog="/home/ubuntu/sftp_ver2/log/"$projectId"_"$hostname"_"log""
    folderLog="/home/ubuntu/sftp_ver2/log/"
    # folder=$(getFoldersByBackupTaskIdAndBackupProjectId "$id1" "$id2")
    # readarray -t listFolders <<< "$folder"
    # for element in "${listFolders[@]}";do
    # done
    if [ ! -d "$folderLog" ]; then
        mkdir -p "$folderLog"
    fi
    echo ""$folderLog"/"$projectId"_"$hostname".log"
    # log=""$folderLog":"$(basename $folderPath)""
    # echo "$log"
}
opt=""
project_id=""
task_id=""
logfile=""
backup_local=false
backup_remote=false
cleanup_local=false
cleanup_remote=false
set_time=false
local_schedule=""
remote_schedule=""
setup_cron() {
    local schedule="$1"
    local command="$2"

    # Remove existing cron job for this script to avoid duplicates
    crontab -l | grep -v -F "$command" | crontab -

    # Add new cron job
    (crontab -l; echo "$schedule $command") | crontab -
}
extract_cron_schedules() {
    local json_file="$JSON_FILE"

    if [ ! -f "$json_file" ]; then
        echo "JSON file '$json_file' not found!"
        exit 1
    fi
    local id1="$1"
    local id2="$2"
    conn=$(getInfoBackupTaskAndBackupProject "$id1" "$id2")
    IFS='?' read -r projectId hostname username password localSchedular remoteSchedular localPath remotePath localRetention remoteRetention <<< "$conn"
    local_schedule="$localSchedular"
    remote_schedule="$remoteSchedular"
    echo "$local_schedule"
    echo "$remote_schedule"
    if [ -z "$local_schedule" ] || [ -z "$remote_schedule" ]; then
        echo "Cron schedules not found in JSON file!"
        exit 1
    fi
}


usage (){
    echo "Usage: $0 [--backup_local] [--backup_remote] [--cleanup_local] [--cleanup_remote] [--set_time] --project_id=<id> --task_id=<id>"
    # echo "$(realpath $0)"
    exit 1
}

for arg in "$@"
do
    case $arg in
        --backup_local)
        backup_local=true
        shift
        ;;
        --backup_remote)
        backup_remote=true
        shift
        ;;
        --cleanup_local)
        cleanup_local=true
        shift
        ;;
        --cleanup_remote)
        cleanup_remote=true
        shift
        ;;
        --set_time)
        set_time=true
        shift
        ;;
        --project_id=*)
        project_id="${arg#*=}"
        shift
        ;;
        --task_id=*)
        task_id="${arg#*=}"
        shift
        ;;
        *)
        usage
        ;;
    esac
done

logfile=$(createFolderLog "$project_id" "$task_id")

if [ -z "$project_id" ] || [ -z "$task_id" ]; then
    usage
fi
if [ "$set_time" = true ]; then
    extract_cron_schedules "$project_id" "$task_id"

    script_path=$(realpath "$0")

    if [ "$backup_local" = true ]; then
        backup_cron_command="$script_path --backup_local --project_id=$project_id --task_id=$task_id"
        setup_cron "$local_schedule" "$backup_cron_command"
        echo "Cron job for backup set up with schedule: $local_schedule"
    fi

    if [ "$backup_remote" = true ]; then
        backup_cron_command="$script_path --backup_remote --project_id=$project_id --task_id=$task_id"
        setup_cron "$remote_schedule" "$backup_cron_command"
        echo "Cron job for backup set up with schedule: $local_schedule"
    fi
    if [ "$cleanup_local" = true ]; then
        backup_cron_command="$script_path --cleanup_local --project_id=$project_id --task_id=$task_id"
        setup_cron "$local_schedule" "$backup_cron_command"
        echo "Cron job for backup set up with schedule: $local_schedule"
    fi
    if [ "$cleanup_remote" = true ]; then
        backup_cron_command="$script_path --cleanup_remote --project_id=$project_id --task_id=$task_id"
        setup_cron "$remote_schedule" "$backup_cron_command"
        echo "Cron job for backup set up with schedule: $local_schedule"
    fi
    exit 
fi


if [ "$backup_local" = true ]; then
    backupLocal "$project_id" "$task_id" >> "$logfile" 2>&1
fi

if [ "$backup_remote" = true ]; then
    backupRemote "$project_id" "$task_id" >> "$logfile" 2>&1
fi

if [ "$cleanup_local" = true ]; then
    cleanupLocal "$project_id" "$task_id" >> "$logfile" 2>&1
fi

if [ "$cleanup_remote" = true ]; then
    cleanupRemote "$project_id" "$task_id" >> "$logfile" 2>&1
fi
