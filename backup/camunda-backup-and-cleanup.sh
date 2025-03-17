#!/bin/bash

# Function to retrieve existing backups for a given service
get_existing_backups() {
  local service_name=$1
  local service_port=$2
  local path_prefix=$3
  curl -s "http://$service_name:$service_port$path_prefix/actuator/backups" || echo "[]"
}

# Function to generate a unique backup ID based on the current timestamp
generate_backup_id() {
  date +"%Y%m%d%H%M%S"
}

# Function to create a backup for a given service
create_backup() {
  local service_name=$1
  local service_port=$2
  local path_prefix=$3
  local backup_id=$4
  echo -e "\n🔹 Creating backup for $service_name with backup id: $backup_id."
  curl --fail -s -X POST "http://$service_name:$service_port$path_prefix/actuator/backups" \
    -H 'Content-Type: application/json' \
    -d "{\"backupId\": \"$backup_id\"}" || echo "⚠️ Failed to initiate backup."
  sleep 5
}

# Function to validate the status of a backup
validate_backup() {
  local service_name=$1
  local service_port=$2
  local path_prefix=$3
  local backup_id=$4
  local fail_count=0

  echo -e "\n🔹 Validating backup for $service_name with backup id: $backup_id."
  while true; do
    response=$(curl --fail -s "http://$service_name:$service_port$path_prefix/actuator/backups/$backup_id" || echo "{}")
    echo "$response"
    if echo "$response" | grep -q '"COMPLETED"'; then
      echo "✅ Backup for $service_name completed successfully."
      break
    elif echo "$response" | grep -q '"IN_PROGRESS"'; then
      echo "⏳ Backup for $service_name in progress, checking again in 30s."
      sleep 30
    else
      echo "⚠️ Backup for $service_name failed or in an unknown state."
      fail_count=$((fail_count + 1))
      if [ $fail_count -ge 3 ]; then
        echo "❌ Failed 3 times for $service_name, exiting."
        exit 1
      else
        echo "🔄 Retrying for $service_name, attempt $fail_count of 3."
        sleep 30
      fi
    fi
  done
}

# Function to delete previous backups
delete_previous_backups() {
  local service_name=$1
  local service_port=$2
  local path_prefix=$3
  local existing_backups=$4

  backup_count=$(echo "$existing_backups" | jq length 2>/dev/null || echo 0)
  if [ "$backup_count" -gt 0 ]; then
    echo -e "\n🗑️ Deleting previous backups for $service_name..."
    ids=$(echo "$existing_backups" | jq -r '.[].backupId' 2>/dev/null)
    for id in $ids; do
      curl -s -X DELETE "http://$service_name:$service_port$path_prefix/actuator/backups/$id" || echo "⚠️ Failed to delete backup $id."
      echo "✅ Deleted backup with id: $id."
    done
  else
    echo "ℹ️ No previous backups to delete for $service_name."
  fi
}

# Main function to perform backup and cleanup operations
perform_backup_and_cleanup() {
  echo -e "\n------------------------------------------------"
  local service_name=$1
  local service_port=$2
  local path_prefix=$3

  echo -e "\n🚀 Performing backup and cleanup for $service_name."

  # Retrieve existing backups
  echo -e "\n🔍 Checking existing backups..."
  existing_backups=$(get_existing_backups "$service_name" "$service_port" "$path_prefix" | jq -c '.' 2>/dev/null || echo "[]")

  # Check if backups exist properly
  backup_count=$(echo "$existing_backups" | jq length 2>/dev/null || echo 0)
  if [ "$backup_count" -gt 0 ]; then
    echo "📂 Existing backups for $service_name:"
    echo "$existing_backups" | jq '.[] | {backupId, state}'
  else
    echo "ℹ️ No existing backups for $service_name."
  fi

  # Generate a unique backup ID
  backup_id=$(generate_backup_id)
  echo -e "\n🆕 Generated backup id: $backup_id."

  # Create new backup
  create_backup "$service_name" "$service_port" "$path_prefix" "$backup_id"

  # Validate the backup
  validate_backup "$service_name" "$service_port" "$path_prefix" "$backup_id"

  # Delete previous backups
  delete_previous_backups "$service_name" "$service_port" "$path_prefix" "$existing_backups"

  echo -e "\n✅ Completed backup and cleanup for $service_name."
  echo "------------------------------------------------"
}

# Ensure 'jq' is installed for JSON parsing
if ! command -v jq &>/dev/null; then
  echo "❌ 'jq' is required but not installed. Please install 'jq' and rerun the script."
  exit 1
fi

# Perform backup and then cleanup (delete all previously created backups)
# You can execute this for Tasklist and Operate from your local machine
# Please port-forward Tasklist/Operate to be accessible on the given port
perform_backup_and_cleanup "localhost" "9600" ""
