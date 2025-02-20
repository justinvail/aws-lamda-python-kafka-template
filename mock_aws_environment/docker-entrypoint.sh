#!/bin/bash
set -e

# Function to cleanup SAM containers
cleanup() {
    echo "Cleaning up SAM containers..."
    docker ps -a | grep "public.ecr.aws/lambda/python" | awk '{print $1}' | xargs -r docker rm -f
    exit 0
}

# Trap SIGTERM and SIGINT
trap cleanup SIGTERM SIGINT

# Store the base directory
BASE_DIR=/app
AWS_DIR=$BASE_DIR/mock_aws_environment

# Wait for Kafka
c3_url="http://control-center:9021"
echo "docker-entrypoint.sh --> Waiting for Kafka ecosystem to start..."
duration_past=0
while ! curl --head --silent --fail "$c3_url" >/dev/null 2>&1; do
  echo "docker-entrypoint.sh --> Waiting for Kafka... $duration_past seconds"
  ((duration_past+=1))
  sleep 1
  if [ "$duration_past" -gt 60 ]; then
    echo "docker-entrypoint.sh --> Timeout waiting for Kafka to start"
    break
  fi
done

echo "docker-entrypoint.sh --> Creating Kafka topics..."
kafka-topics --create \
    --if-not-exists \
    --bootstrap-server broker:29092 \
    --topic user-id-change-topic \
    --partitions 1 \
    --replication-factor 1

echo "docker-entrypoint.sh --> Starting mock AWS environment..."

# =====================================================
# CREATE LAMBDA DEPLOYMENT PACKAGE
# =====================================================
echo "docker-entrypoint.sh --> Creating Lambda deployment package..."

# Create deployment package script
cat > /tmp/create_deployment_package.sh << 'EOF'
#!/bin/bash
# Script to create a proper Lambda deployment package

set -e
echo "create_deployment_package.sh --> Creating Lambda deployment package..."

# Set up directories
BASE_DIR=/app
PACKAGE_DIR=/tmp/lambda_package
BUILD_DIR=/tmp/lambda_build
ZIP_PATH=/tmp/lambda_function.zip

# Clean previous builds
rm -rf $PACKAGE_DIR $BUILD_DIR
mkdir -p $PACKAGE_DIR $BUILD_DIR

# Copy Lambda function and dependencies
echo "create_deployment_package.sh --> Copying Lambda function code..."
cp $BASE_DIR/lambda_function/lambda_function.py $BUILD_DIR/

# Add a debug helper to print environment
cat > $BUILD_DIR/debug_helper.py << 'INNEREOF'
import os
import sys

def debug_environment():
    """Helper function to debug Lambda environment"""
    debug_info = {
        "sys.path": sys.path,
        "current_dir": os.getcwd(),
        "dir_contents": os.listdir('.'),
        "env_vars": dict(os.environ),
        "python_version": sys.version
    }
    return debug_info
INNEREOF

# Modify lambda_function.py to include debug info
ORIGINAL_LAMBDA=$(cat $BUILD_DIR/lambda_function.py)
cat > $BUILD_DIR/lambda_function.py << INNEREOF
import json
import os
import sys
import logging

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.DEBUG)

# Import debug helper
try:
    from debug_helper import debug_environment
    logger.info("Debug helper imported successfully")
except ImportError as e:
    logger.error(f"Failed to import debug helper: {e}")
    def debug_environment():
        return {"error": "Debug helper not available"}

# Original lambda function code
$ORIGINAL_LAMBDA

# Wrap handler with debugging
_original_handler = handler
def handler(event, context):
    """Wrapper for original handler with debugging"""
    try:
        logger.info("Lambda function invoked with ZIP package")
        logger.info(f"Event: {json.dumps(event)}")
        logger.info(f"Debug info: {json.dumps(debug_environment(), default=str)}")

        # Call original handler
        return _original_handler(event, context)
    except Exception as e:
        logger.error(f"Error in handler: {str(e)}", exc_info=True)
        raise
INNEREOF

# Copy Avro schemas if they exist
if [ -d "$BASE_DIR/schemas" ]; then
    echo "create_deployment_package.sh --> Copying Avro schemas..."
    mkdir -p $BUILD_DIR/schemas
    cp -r $BASE_DIR/schemas/* $BUILD_DIR/schemas/
fi

# Install dependencies (minimal set for diagnostics)
cd $BUILD_DIR
echo "create_deployment_package.sh --> Installing core dependencies..."
pip install avro-python3 -t . --upgrade

# Create the ZIP package
echo "create_deployment_package.sh --> Creating ZIP package..."
zip -r $ZIP_PATH . -x "*.pyc" "__pycache__/*" "*.dist-info/*" "*.egg-info/*"

echo "create_deployment_package.sh --> Lambda deployment package created at $ZIP_PATH"
echo "create_deployment_package.sh --> Package contents:"
unzip -l $ZIP_PATH | tail -n +4 | head -n -2 | awk '{print $4}'

# Copy to a location accessible by SAM
mkdir -p $PACKAGE_DIR
cp $ZIP_PATH $PACKAGE_DIR/
echo "create_deployment_package.sh --> Deployment package copied to $PACKAGE_DIR/lambda_function.zip"
EOF

# Make the script executable
chmod +x /tmp/create_deployment_package.sh

# Run the deployment package creation script
/tmp/create_deployment_package.sh

# =====================================================
# Update SAM template to use ZIP package
# =====================================================
echo "docker-entrypoint.sh --> Updating SAM template..."
cat > $AWS_DIR/template.yml << EOF
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31

Resources:
  KafkaConsumerFunction:
    Type: AWS::Serverless::Function
    Properties:
      FunctionName: KafkaConsumerFunction
      Handler: lambda_function.handler
      Runtime: python3.9
      CodeUri: /tmp/lambda_package/lambda_function.zip
      Environment:
        Variables:
          KAFKA_BOOTSTRAP_SERVERS: "broker:29092"
          KAFKA_TOPIC: "user-id-change-topic"
          DEBUG_MODE: "true"
      Events:
        KafkaEvent:
          Type: SelfManagedKafka
          Properties:
            StartingPosition: TRIM_HORIZON
            BatchSize: 10
            Topics:
              - user-id-change-topic
            KafkaBootstrapServers:
              - "broker:29092"
            ConsumerGroupId: "sam-local-consumer-group"
EOF

# =====================================================
# Start SAM Local
# =====================================================
echo "docker-entrypoint.sh --> Starting SAM Local..."
cd $AWS_DIR
sam local start-lambda \
    --host 0.0.0.0 \
    --port 3001 \
    --template template.yml \
    --docker-network bip-network \
    --container-host host.docker.internal \
    --skip-pull-image \
    --debug \
    --log-file $BASE_DIR/lambda.log &

# Give SAM more time to initialize
echo "docker-entrypoint.sh --> Waiting for Lambda to initialize..."
sleep 15

# Test the Lambda function with a simple invocation
echo "docker-entrypoint.sh --> Testing Lambda invocation..."
echo '{"Records":[]}' > /tmp/test_event.json
sam local invoke -t $AWS_DIR/template.yml -e /tmp/test_event.json KafkaConsumerFunction || echo "Initial invoke test failed, but continuing"

# Check if SAM Lambda is running
echo "docker-entrypoint.sh --> Checking if Lambda is running..."
curl -s http://localhost:3001/2015-03-31/functions/KafkaConsumerFunction/invocations -d '{"Records":[]}' | grep -i error || echo "Lambda seems to be running correctly"

echo "docker-entrypoint.sh --> Starting Kafka Lambda bridge..."
cd $AWS_DIR
python3 -u kafka_lambda_bridge.py 2>&1 | tee $BASE_DIR/bridge.log &

echo "docker-entrypoint.sh --> Starting producer..."
python3 -u producer.py 2>&1 | tee $BASE_DIR/producer.log &

echo "docker-entrypoint.sh --> Tailing logs..."
cd $BASE_DIR
touch lambda.log bridge.log producer.log
tail -f lambda.log bridge.log producer.log &

# Wait for any signal that signals termination
wait
