#!/bin/bash
# set -x
JSON_FILE="/home/ubuntu/sftp_ver2/data.json"
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

# cleanupLocal(){
#     local id1=$1
#     local id2=$2
#     conn=$(getOneBackupTaskByFolderIdAndBackupProjectId "$id1" "$id2")
#     IFS=':' read -r projectId hostname username password folderId folderPath localSchedular localPath localRetention remoteSchedular remotePath remoteRetention <<< "$conn"
#     echo "-------------------------Start Cleanup Task ID "$id2" in Project ID "$id1""
#     localFolderPath=$localPath/$hostname/$(basename $folderPath)
#     timestamp "Cleanup directory "$localFolderPath" with "$localRetention" retention" 
#     count=$(ls -lt $localFolderPath | grep "^d" | tail -n +"$(($localRetention + 1))" | wc -l )
#     if [ $count -gt 0 ];
#     then
#         timestamp "There are $count folders need to be deleted"
#         ls -t -d $localFolderPath/*/ | tail -n +"$(($localRetention + 1))"
#         timestamp "Deleting..."
#         ls -t -d $localFolderPath/*/ | tail -n +"$(($localRetention + 1))" | xargs rm -rf
#         timestamp "Done"
#     else
#         timestamp "There are no folders to delete" 
#     fi
#     echo -e "-----------------------Finish Cleanup Task ID "$id2" in Project ID "$id1" \n"
# }
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
setTime(){
    local id1=$1
    local id2=$2
    conn=$(getInfoBackupTaskAndBackupProject "$id1" "$id2")
    IFS='?' read -r projectId hostname username password localSchedular remoteSchedular localPath remotePath localRetention remoteRetention <<< "$conn"
    folder=$(getFoldersByBackupTaskIdAndBackupProjectId "$id1" "$id2")
    readarray -t listFolders <<< "$folder"
    echo "$localSchedular"
    echo "$remoteSchedular"
    
}
# usage() {                                
#     echo "Usage $0" 1>&2 
#     echo "Options:"
#     echo "  --backup_local --project_id=number1 --backup_task_id=number2,  Backup to local storage"
#     echo "  --backup_remote --project_id=number1 --backup_task_id=number2,  Backup to remote storage"
#     echo "  --cleanup_local --project_id=number1 --backup_task_id=number2,  Clean up local storage with number retention"
#     echo "  --cleanup_remote --project_id=number1 --backup_task_id=number2,  Clean up remote storage with number retention"
#     echo "  --set_time --project_id=number1 --backup_task_id=number2,  Set Schedular"
#    exit 0
# }

usage (){
    echo "Usage: $0 [--backup_local] [--backup_remote] [--cleanup_local] [--cleanup_remote] --project_id=<id> --backup_task_id=<id>"
    exit 1
}
opt=""
project_id=""
backup_task_id=""
logfile=""
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --backup_local)
        opt="backup_local"
        shift 
        ;;
        --backup_remote)
        opt="backup_remote"
        shift 
        ;;
        --cleanup_local)
        opt="cleanup_local"
        shift 
        ;;
        --cleanup_remote)
        opt="cleanup_remote"
        shift 
        ;;     
        --set_time)
        opt="set_time"
        shift 
        ;;
        --project_id=*)
        project_id="${key#*=}"
        shift # past argument=value
        ;;
        --backup_task_id=*)
        backup_task_id="${key#*=}"
        shift # past argument=value
        ;;
        *)  
        # unknown option
        echo "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
done

if [ -z "$opt" ]; then
    usage
fi

if [ -z "$project_id" ]; then
    echo "Please specify project ID using --project_id."
    usage
    exit 1
fi

if [ -z "$backup_task_id" ]; then
    echo "Please specify backup task ID using --backup_task_id."
    usage
    exit 1
fi
logfile=$(createFolderLog "$project_id" "$backup_task_id")
case $opt in
    backup_local)
    backupLocal "$project_id" "$backup_task_id" >> "$logfile" 2>&1
    # backupLocal "$project_id" "$backup_task_id"
    ;;
    backup_remote)
    backupRemote "$project_id" "$backup_task_id" >> "$logfile" 2>&1
    ;;
    cleanup_local)
    cleanupLocal "$project_id" "$backup_task_id" >> "$logfile" 2>&1
    ;;
    cleanup_remote)
    cleanupRemote "$project_id" "$backup_task_id" >> "$logfile" 2>&1
    ;;
    set_time)
    
    ;;
    *)  
    echo "Unknown option: $opt"
    usage
    exit 1
    ;;
esac