#!/bin/bash
cd -- "${BASH_SOURCE%/*}/" || exit
./stop-all.sh
# Check if LOCALSTACK_API_KEY is set
if [ -z "$LOCALSTACK_API_KEY" ]; then
  echo "Error: LOCALSTACK_API_KEY environment variable is not set.  Please obtain a localstack pro key and set the environment variable."
  exit 1
else
  echo "LOCALSTACK_API_KEY is set to $LOCALSTACK_API_KEY"
fi
docker compose up -d
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
export AWS_ENDPOINT_URL=http://localhost:4566
c3_url="http://localhost:9021"
explanation=" seconds have past."
echo "Waiting for Kafka ecosystem to start."
duration_past=0
while ! curl --head --silent --fail "$c3_url" >/dev/null; do
  echo -ne " -> $duration_past$explanation\r"
  ((duration_past+=1))
  sleep 1
done
echo ""
echo "Kafka ecosystem started!"
docker container ls
open http://localhost:9021/clusters/LocalKafkaCluster/overview
echo ""
echo "Creating python lambda function and deploying to localstack within docker"

## Variables
LAMBDA_DIR="./lambda_function"
LAMBDA_NAME="lambda_function"
LAMBDA_FILE="$LAMBDA_NAME.py"
AVRO_FILE="user.avsc"
LAMBDA_ZIP="$LAMBDA_NAME.zip"
KAFKA_TOPIC="user-id-change-topic"
AWS_ACCOUNT="000000000000"

# Package the Lambda function
echo "Packaging Lambda function..."
cd $LAMBDA_DIR
zip -r "../$LAMBDA_ZIP" .
cd -- "${BASH_SOURCE%/*}/" || exit
# Create the Lambda function
echo "Creating Lambda function..."

awslocal iam create-role --role-name lambda-role --assume-role-policy-document \
'{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}' \
>/dev/null

awslocal iam create-policy --policy-name LambdaKafkaPolicy --policy-document \
'{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "lambda:InvokeFunction",
        "lambda:CreateEventSourceMapping"
      ],
      "Resource": "arn:aws:lambda:us-east-1:000000000000:function:KafkaConsumerFunction"
    },
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:us-east-1:000000000000:secret:localstack-FtaAYP"
    },
    {
      "Effect": "Allow",
      "Action": [
        "kafka:DescribeCluster",
        "kafka:Consume"
      ],
      "Resource": "arn:aws:kafka:us-east-1:000000000000:cluster/your-cluster-name/*"
    }
  ]
}'

awslocal iam attach-role-policy --role-name lambda-role --policy-arn arn:aws:iam::000000000000:policy/LambdaKafkaPolicy

awslocal iam list-attached-role-policies --role-name lambda-role

ARN=$(awslocal secretsmanager create-secret --name localstack | jq -r '.ARN')
echo "Scraping output of secretsmanager to get token"
echo "$ARN"

#https://docs.localstack.cloud/user-guide/integrations/kafka/
#https://aws.amazon.com/blogs/compute/using-self-hosted-apache-kafka-as-an-event-source-for-aws-lambda/
#Seems like the only way to setup the event source mapping is through awslocal cli.  I can't get sam + cloudformation template to work

#This would be how you use a cloudformation template.yml with sam
#sam validate --region us-east-1
#sam build --use-container
#sam deploy --region us-east-1 --stack-name lambda_function --resolve-s3 --no-confirm-changeset

awslocal lambda create-function \
    --function-name KafkaConsumerFunction \
    --handler lambda_function.handler \
    --runtime python3.8 \
    --role arn:aws:iam::000000000000:role/lambda-role \
    --zip-file fileb://lambda_function.zip \
    >/dev/null

# Get the function name and store it in a variable
FUNCTION_NAME=$(awslocal lambda list-functions | jq -r '.Functions[0].FunctionName')
echo "Function Name: $FUNCTION_NAME"

awslocal logs create-log-group --log-group-name "/aws/lambda/$FUNCTION_NAME"

# Run the create-event-source-mapping command using the function name
awslocal lambda create-event-source-mapping \
    --topics "$KAFKA_TOPIC" \
    --source-access-configuration Type=PLAINTEXT,URI="$ARN" \
    --function-name arn:aws:lambda:us-east-1:000000000000:function:"$FUNCTION_NAME" \
    --self-managed-event-source '{"Endpoints":{"KAFKA_BOOTSTRAP_SERVERS":["broker:29092"]}}' \
    >/dev/null

echo "Running producer.py to simulate events"
python3 producer.py

# Cleanup
echo "Cleaning up temporary files..."
rm -f "lambda_function.zip"
