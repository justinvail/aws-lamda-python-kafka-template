#!/bin/bash
# combined-cleanup.sh - A comprehensive script to stop all services, containers, and processes
cd -- "${BASH_SOURCE%/*}/" || exit

echo "======================================================================"
echo "CLEANUP SCRIPT - Stopping all services, containers, processes"
echo "======================================================================"

# ----------------------------------------------------------------------
# FUNCTION DEFINITIONS
# ----------------------------------------------------------------------

# Function to check if Docker is running
check_docker() {
  if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed or not in PATH"
    return 1
  fi

  if ! docker info &> /dev/null; then
    echo "Error: Docker daemon is not running"
    return 1
  fi

  return 0
}

# Function to clean up specific processes by PID
cleanup_processes() {
  for pid in "$@"; do
    if [ -n "$pid" ]; then
      CMD=$(ps -p "$pid" -o command= 2>/dev/null || echo "Unknown process")
      echo "--> Stopping process $pid: $CMD"
      kill -15 "$pid" 2>/dev/null || true
      sleep 0.2

      # Check if process still exists, force kill if needed
      if ps -p "$pid" > /dev/null 2>&1; then
        echo "--> Force killing process $pid"
        kill -9 "$pid" 2>/dev/null || true
      fi
    fi
  done
}

# Function to stop and remove a Docker container
stop_and_remove_container() {
  local container_id=$1
  local container_name=$2

  echo "--> Stopping container ${container_id} (${container_name})..."
  docker stop "${container_id}" &> /dev/null

  if [ $? -eq 0 ]; then
    echo "--> Container ${container_id} stopped successfully."

    echo "--> Removing container ${container_id}..."
    docker rm "${container_id}" &> /dev/null

    if [ $? -eq 0 ]; then
      echo "--> Container ${container_id} removed successfully."
    else
      echo "--> Failed to remove container ${container_id}."
    fi
  else
    echo "--> Failed to stop container ${container_id}."
  fi
}

# Function to kill all Python processes
kill_all_python_processes() {
  echo "==> Forcefully terminating all Python processes..."

  # Get our own PID to exclude it
  OWN_PID=$

  # Find Python process IDs (case-insensitive search for both Python and python)
  # Exclude grep process and our own script process
  PYTHON_PIDS=$(ps aux | grep -i python | grep -v grep | grep -v "$OWN_PID" | awk '{print $2}')

  if [ -n "$PYTHON_PIDS" ]; then
    echo "--> Found Python processes: $PYTHON_PIDS"

    # First try SIGTERM
    for pid in $PYTHON_PIDS; do
      CMD=$(ps -p "$pid" -o command= 2>/dev/null || echo "Unknown process")
      echo "--> Sending SIGTERM to Python process $pid: $CMD"
      kill -15 "$pid" 2>/dev/null || true
    done

    # Wait a moment
    sleep 1

    # Then use SIGKILL for any remaining
    for pid in $PYTHON_PIDS; do
      if ps -p "$pid" > /dev/null 2>&1; then
        echo "--> Sending SIGKILL to Python process $pid"
        kill -9 "$pid" 2>/dev/null || true
      fi
    done

    # Try pkill as a final measure (case-insensitive)
    # Exclude our own script from being killed
    REMAINING=$(ps aux | grep -i python | grep -v grep | grep -v "$OWN_PID" | awk '{print $2}')
    if [ -n "$REMAINING" ]; then
      echo "--> Some Python processes still running, using pkill..."
      # Use pkill with process group exclusion to avoid killing our own script
      pkill -9 -fi "python" -g "$(ps -o pgid= $OWN_PID | tr -d ' ')" || true
      # Also try with capital P
      pkill -9 -f "Python" -g "$(ps -o pgid= $OWN_PID | tr -d ' ')" || true
    fi
  else
    echo "--> No Python processes found initially"
  fi

  # Wait another moment
  sleep 0.5

  # Final verification (case-insensitive)
  FINAL_CHECK=$(ps aux | grep -i python | grep -v grep | grep -v "$OWN_PID" | wc -l)
  if [ "$FINAL_CHECK" -gt 0 ]; then
    echo "--> WARNING: $FINAL_CHECK Python processes still running:"
    ps aux | grep -i python | grep -v grep | grep -v "$OWN_PID"
    echo "--> You may need to terminate these manually"
  else
    echo "--> All Python processes have been terminated."
  fi
}

# Function to cleanup lambda containers
cleanup_lambda_containers() {
  echo "==> Cleaning up Lambda containers..."

  # Verify Docker is running
  check_docker || return 1

  # Get lambda containers with image "public.ecr.aws/lambda/python:3.8-rapid-x86_64"
  echo "--> Searching for Lambda containers..."

  # Get container IDs and names
  containers=$(docker ps --filter "ancestor=public.ecr.aws/lambda/python:3.8-rapid-x86_64" --format "{{.ID}}:{{.Names}}")

  if [ -z "$containers" ]; then
    echo "--> No Lambda containers found."
    return 0
  fi

  # Loop through containers and remove them
  echo "--> Found matching containers. Processing..."

  IFS=$'\n'
  for container in $containers; do
    container_id=$(echo $container | cut -d: -f1)
    container_name=$(echo $container | cut -d: -f2)
    stop_and_remove_container "$container_id" "$container_name"
  done

  echo "--> Lambda container cleanup completed."
}

# ----------------------------------------------------------------------
# MAIN SCRIPT EXECUTION
# ----------------------------------------------------------------------

echo "==> Identifying specific processes..."
# Find specific process PIDs
SAM_PID=$(pgrep -f "sam local start-lambda" || true)
BRIDGE_PID=$(pgrep -f "kafka_lambda_bridge.py" || true)
PRODUCER_PID=$(pgrep -f "producer.py" || true)

echo "==> Cleaning up specific processes..."
cleanup_processes "$SAM_PID" "$BRIDGE_PID" "$PRODUCER_PID"

echo "==> Stopping docker containers with docker-compose..."
# Check Docker before trying docker-compose
if check_docker; then
  # Try to use docker compose (newer version)
  if command -v docker &> /dev/null && docker compose version &> /dev/null; then
    echo "--> Using docker compose..."
    docker compose down --volumes
  # Try to use docker-compose (older version)
  elif command -v docker-compose &> /dev/null; then
    echo "--> Using docker-compose..."
    docker-compose down --volumes
  else
    echo "--> docker-compose not found, skipping compose down."
  fi
else
  echo "--> Docker is not available, skipping docker-compose."
fi

# Clean up Lambda containers
cleanup_lambda_containers

# Kill all Python processes
kill_all_python_processes

echo "==> Checking for remaining containers..."
if check_docker; then
  docker container ls
else
  echo "--> Docker is not available, cannot list containers."
fi

echo "======================================================================"
echo "CLEANUP COMPLETED"
echo "======================================================================"
