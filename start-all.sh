#!/bin/bash

#stops the execution of a script if a command or pipeline has an error
set -e

# Check if Docker daemon is running
if ! docker info >/dev/null 2>&1; then
    echo "start-all.sh --> Error: Docker daemon is not running. Please start Docker and try again."
    exit 1
fi

# Kill other instances of this script
SCRIPT_NAME=$(basename "$0")
for pid in $(pgrep -f "$SCRIPT_NAME"); do
    if [ "$pid" != $$ ]; then
        echo "start-all.sh --> Killing other instance of $SCRIPT_NAME (PID: $pid)..."
        kill -9 "$pid" 2>/dev/null || true
    fi
done

# Change directory to the script's location
cd -- "${BASH_SOURCE%/*}/" || exit

echo "Activating virtual environment. (Modifies path to search virtual environment first)"
source ./.venv/bin/activate || exit
echo ""

# Kill any existing processes on port 3001
echo "start-all.sh --> Cleaning up existing conflicting processes..."
existing_pid=$(lsof -ti:3001 || true)
if [ -n "$existing_pid" ]; then
    echo "start-all.sh --> Killing existing process on port 3001..."
    kill -9 "$existing_pid" || true
fi

# Stop any running containers
echo "start-all.sh --> Stopping any running containers..."
./stop-all.sh || true

# Start all services
echo "start-all.sh --> Starting Kafka ecosystem..."
docker compose up -d

# Wait for the Kafka ecosystem to start
c3_url="http://localhost:9021"
explanation=" seconds have passed."
echo "start-all.sh --> Waiting for Kafka ecosystem to start."
duration_past=0
while ! curl --head --silent --fail "$c3_url" >/dev/null 2>&1; do
  echo -ne "start-all.sh --> $duration_past$explanation\r"
  ((duration_past+=1))
  sleep 1
  if [ "$duration_past" -gt 60 ]; then
    echo "start-all.sh --> Timeout waiting for Kafka to start"
    break
  fi
done
echo ""
echo "start-all.sh --> Kafka ecosystem started!"

# Open Control Center UI
open http://localhost:9021/clusters/LocalKafkaCluster/overview || true

echo "start-all.sh --> Building Lambda function using SAM..."
sam build --use-container

echo "start-all.sh --> Starting Lambda with debug output..."
sam local start-lambda \
  --docker-network bip-network \
  --warm-containers EAGER \
  --debug \
  --log-file lambda.log &

# Store the SAM process ID
SAM_PID=$!

# Give services time to initialize
echo "start-all.sh --> Waiting for Lambda to initialize..."
sleep 10

echo "start-all.sh --> Starting Kafka to Lambda bridge..."
python3 kafka_lambda_bridge.py &
BRIDGE_PID=$!

echo "start-all.sh --> Running producer to generate test events..."
python3 producer.py &
PRODUCER_PID=$!

# Show logs and keep script running
echo "start-all.sh --> Tailing Lambda logs..."
tail -f lambda.log

# Trap Ctrl+C to clean up processes
cleanup() {
    echo "start-all.sh --> Cleaning up processes..."
    kill $SAM_PID $BRIDGE_PID $PRODUCER_PID 2>/dev/null || true
    exit
}
trap cleanup INT TERM

# Wait for any process to exit
wait -n
