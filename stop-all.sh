#!/bin/bash
cd -- "${BASH_SOURCE%/*}/" || exit

# Source the shared functions
source ./cleanup-functions.sh

echo "stop-all.sh --> Stopping all services..."

# Find and kill the relevant processes
SAM_PID=$(pgrep -f "sam local start-lambda" || true)
BRIDGE_PID=$(pgrep -f "kafka_lambda_bridge.py" || true)
PRODUCER_PID=$(pgrep -f "producer.py" || true)

# Call the cleanup function with the PIDs
cleanup_processes "$SAM_PID" "$BRIDGE_PID" "$PRODUCER_PID"

# Stop docker containers
echo "stop-all.sh --> Stopping docker containers..."
docker compose down --volumes

# List remaining containers
echo "stop-all.sh --> Remaining containers:"
docker container ls
