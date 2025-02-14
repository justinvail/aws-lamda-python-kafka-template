#!/bin/bash
set -e

c3_url="http://control-center:9021"
echo "start-all.sh --> Waiting for Kafka ecosystem to start..."
duration_past=0
while ! curl --head --silent --fail "$c3_url" >/dev/null 2>&1; do
  echo "start-all.sh --> Waiting for Kafka... $duration_past seconds"
  ((duration_past+=1))
  sleep 1
  if [ "$duration_past" -gt 60 ]; then
    echo "start-all.sh --> Timeout waiting for Kafka to start"
    break
  fi
done

echo "Creating Kafka topics..."
kafka-topics --create \
    --if-not-exists \
    --bootstrap-server broker:29092 \
    --topic user-id-change-topic \
    --partitions 1 \
    --replication-factor 1

echo "Starting mock AWS environment..."

cd /app/mock_aws_environment

echo "Lambda function directory contents:"
ls -la /var/task

echo "Python path:"
echo $PYTHONPATH

echo "Starting SAM Local..."
sam local start-lambda \
    --host 0.0.0.0 \
    --port 3001 \
    --template template.yml \
    --docker-network bip-network \
    --container-host host.docker.internal \
    --warm-containers EAGER \
    --debug \
    --log-file /app/lambda.log &

# Give SAM more time to initialize
echo "Waiting for Lambda to initialize..."
sleep 10

# Check if SAM Lambda is running
echo "Checking if Lambda is running..."
curl -v http://localhost:3001/2015-03-31/functions/KafkaConsumerFunction/invocations

echo "Starting Kafka Lambda bridge..."
cd /app/mock_aws_environment
python3 -u kafka_lambda_bridge.py 2>&1 | tee /app/bridge.log &

echo "Starting producer..."
cd /app/mock_aws_environment
python3 -u producer.py 2>&1 | tee /app/producer.log &

echo "Tailing logs..."
cd /app
touch lambda.log bridge.log producer.log
tail -f lambda.log bridge.log producer.log
