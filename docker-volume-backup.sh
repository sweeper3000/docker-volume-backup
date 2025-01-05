#!/bin/bash

set -e  # Exit on error

# Helper function for docker run command
docker_volume_operation() {
    local volume=$1
    local operation=$2
    local backup_path=$3
    local target_dir=${PWD}

    if ! docker run --rm \
        --mount "source=$volume,target=$target_dir" \
        -v "$backup_path:/backup" \
        busybox \
        tar $operation; then
        echo "Docker operation failed for volume: $volume"
        return 1
    fi
}

backup() {
    echo "Available Docker volumes:"
    docker volume ls
    echo
    read -p "Enter the volume name to backup: " volume_name
    
    if [ -z "$volume_name" ]; then
        echo "Volume name cannot be empty"
        return 1
    fi
    
    # Check if volume exists
    if ! docker volume inspect "$volume_name" >/dev/null 2>&1; then
        echo "Volume $volume_name does not exist"
        return 1
    fi
    
    backup_file="${volume_name}_$(date +%Y%m%d_%H%M%S)_$(openssl rand -hex 4).tar.gz"
    
    if [ -f "$backup_file" ]; then
        echo "Backup file already exists. Please try again."
        return 1
    fi
    
    if ! docker_volume_operation "$volume_name" "-czvf /backup/$backup_file ${PWD}" "${PWD}"; then
        return 1
    fi
    
    chmod 600 "$backup_file"  # Restrict permissions
    echo "Backup completed: $backup_file"
}

restore() {
    echo "Available Docker volumes:"
    docker volume ls
    echo
    read -p "Enter the volume name to restore: " volume_name
    
    if [ -z "$volume_name" ]; then
        echo "Volume name cannot be empty"
        return 1
    fi
    
    # List available backup files
    echo "Available backup files:"
    ls -1 *.tar.gz 2>/dev/null || { echo "No backup files found"; return 1; }
    echo
    read -p "Enter the backup filename to restore from: " backup_file
    
    if [ ! -f "$backup_file" ]; then
        echo "Backup file not found"
        return 1
    fi
    
    if ! docker_volume_operation "$volume_name" "-xzvf /backup/$backup_file -C /" "${PWD}"; then
        return 1
    fi
    
    echo "Restore completed from $backup_file"
}

backupAll() {
    backup_dir="docker_volumes_backup_$(date +%Y%m%d_%H%M%S)_$(openssl rand -hex 4)"
    
    if [ -d "$backup_dir" ]; then
        echo "Backup directory already exists. Please try again."
        return 1
    fi
    
    if ! mkdir -p "$backup_dir"; then
        echo "Failed to create backup directory"
        return 1
    fi
    
    volumes=$(docker volume ls --format "{{.Name}}") || { echo "Failed to list volumes"; rm -rf "$backup_dir"; return 1; }
    
    if [ -z "$volumes" ]; then
        echo "No Docker volumes found"
        rm -rf "$backup_dir"
        return 1
    fi
    
    for volume in $volumes; do
        echo "Backing up volume: $volume"
        backup_file="$backup_dir/${volume}.tar.gz"
        
        if ! docker_volume_operation "$volume" "-czvf /backup/$(basename $backup_file) ${PWD}" "${PWD}/$backup_dir"; then
            echo "Failed to backup volume: $volume"
            rm -rf "$backup_dir"
            return 1
        fi
    done
    
    if ! tar -czf "${backup_dir}.tar.gz" "$backup_dir"; then
        echo "Failed to create final archive"
        rm -rf "$backup_dir"
        return 1
    fi
    
    chmod 600 "${backup_dir}.tar.gz"  # Restrict permissions
    rm -rf "$backup_dir"
    
    echo "All volumes backed up to: ${backup_dir}.tar.gz"
}

restoreAll() {
    # List available backup archives
    echo "Available backup archives:"
    ls -1 docker_volumes_backup_*.tar.gz 2>/dev/null || { echo "No backup archives found"; return 1; }
    echo
    read -p "Enter the backup archive to restore from: " archive_file
    
    if [ ! -f "$archive_file" ]; then
        echo "Backup archive not found"
        return 1
    fi
    
    temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' EXIT ERR
    
    if ! tar -xzf "$archive_file" -C "$temp_dir"; then
        echo "Failed to extract archive"
        return 1
    fi
    
    backup_dir=$(ls "$temp_dir")
    
    for backup_file in "$temp_dir/$backup_dir"/*.tar.gz; do
        volume_name=$(basename "$backup_file" .tar.gz)
        echo "Restoring volume: $volume_name"
        
        # Create volume if it doesn't exist
        if ! docker volume create "$volume_name" >/dev/null 2>&1; then
            echo "Failed to create volume: $volume_name"
            return 1
        fi
        
        if ! docker_volume_operation "$volume_name" "-xzvf /backup/$(basename $backup_file) -C /" "$temp_dir/$backup_dir"; then
            echo "Failed to restore volume: $volume_name"
            return 1
        fi
    done
    
    echo "All volumes restored from $archive_file"
}

# Main menu
while true; do
    echo
    echo "Docker Volume Backup/Restore Utility"
    echo "1. Backup single volume"
    echo "2. Restore single volume"
    echo "3. Backup all volumes"
    echo "4. Restore all volumes"
    echo "5. Exit"
    echo
    read -p "Select an option (1-5): " choice
    
    case $choice in
        1) backup ;;
        2) restore ;;
        3) backupAll ;;
        4) restoreAll ;;
        5) exit 0 ;;
        *) echo "Invalid option" ;;
    esac
done
