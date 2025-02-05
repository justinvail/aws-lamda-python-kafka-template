# Confluent Kafka & AWS Lambda Demo

## Overview
This project demonstrates the integration of a **self-managed Confluent Kafka** with **AWS Lambda**, using **AWS SAM** for local development. The entire setup runs in **Docker** and is intended to be **forked, updated, and deployed** by others.

## Features
- **Confluent Kafka** environment running in Docker
- **AWS Lambda** function written in Python, running locally via SAM
- **Automated setup** via `setup.sh`
- **Automated deployment** via `start-all.sh`
- **Message producer** (`producer.py`) generates **10,000 randomized messages** at a time
- **Local Kafka-Lambda bridge** that mimics AWS Event Source Mapping behavior
- **Production-identical infrastructure code** using SAM templates

## Prerequisites
Ensure you have the following installed before proceeding:
- **Docker**
- **Brew**
- **Python3** (via `brew` or manually installed)
- **AWS SAM CLI**

## Local Development Architecture
This project uses a lightweight bridge connector approach for local development:
- **AWS SAM** runs the Lambda function locally
- **Confluent Kafka** runs in Docker
- A simple **Python bridge** connects Kafka to the local Lambda, mimicking AWS Event Source Mapping
- **Important:** The bridge is purely for local development and doesn't affect your production code or infrastructure

### Why Bridge Instead of LocalStack Pro?
We moved from LocalStack Pro to a bridge connector approach because:
1. **No paid dependencies** - Eliminates the need for LocalStack Pro licensing
2. **Production parity** - Your Lambda function and SAM template remain exactly as they would be in production
3. **Simplicity** - The bridge is lightweight and transparent in its operation
4. **Easy debugging** - Direct visibility into the message flow between Kafka and Lambda

## Setup Instructions
1. Clone this repository:
   ```sh
   git clone https://github.com/yourusername/confluent-kafka-lambda-demo.git
   cd confluent-kafka-lambda-demo
   ```
2. Give permission to setup scripts (if your system requires it):
   ```sh
   chmod 755 setup.sh
   chmod 755 start-all.sh
   chmod 755 stop-all.sh
   ```
3. Run the **setup script** to install dependencies:
   ```sh
   ./setup.sh
   ```
4. Start all services and the Lambda:
   ```sh
   ./start-all.sh
   ```
   This will:
   - Start all **Docker containers**
   - Build and start the **Lambda function** using SAM
   - Start the **Kafka-Lambda bridge**
   - Run the **Kafka producer** (`producer.py`)
5. Stop all the services and clean up:
   ```sh
   ./stop-all.sh
   ```

## How It Works
1. **Kafka Setup:** A self-managed Kafka cluster runs in Docker
2. **Lambda Execution:** SAM runs your Lambda function locally
3. **Message Flow:**
   - The producer sends messages to Kafka
   - The bridge reads messages from Kafka
   - The bridge forwards messages to your local Lambda
   - Messages are formatted exactly as they would be in AWS
4. **Production Deployment:**
   - The same SAM template and Lambda code deploy directly to AWS
   - AWS Event Source Mapping replaces the local bridge
   - No changes needed to infrastructure code or Lambda function

## Customization
- Modify the **Lambda function** in `lambda_function/lambda_function.py`
- Change the **number of messages generated** in `producer.py`
- Update the **message schema** in `lambda_function/user.avsc`
- Customize the **bridge behavior** in `kafka_lambda_bridge.py`

## Cleanup
To stop all running services:
```sh
./stop-all.sh
```

## Project Structure
```
.
├── docker-compose.yml      # Kafka and related services
├── lambda_function/        # Lambda function code and dependencies
│   ├── lambda_function.py  # Main Lambda handler
│   ├── requirements.txt    # Python dependencies
│   └── user.avsc          # Avro schema for messages
├── producer.py            # Kafka message producer
├── kafka_lambda_bridge.py # Local development bridge
├── setup.sh              # Installation script
├── start-all.sh         # Startup script
├── stop-all.sh          # Cleanup script
└── template.yml         # SAM/CloudFormation template
```

## Potential Upcoming Changes
- **Introduce security measures** such as TLS encryption or SASL authentication for Kafka
- **Implement access control lists (ACLs)** for fine-grained permission management in Kafka
- **Update lambda_function.py to use Confluent Schema Registry on initialization** to reduce package size, increase resiliency, and increase modifiability
- **Update lambda_function.py to do something interesting with its message data** like call an api found here: **https://github.com/toddmotto/public-apis/**
- **Remove unnecessary confluent containers** to reduce start up time
- **Introduce python virtual environments** to ensure consistent dependency resolution
- **Add message keys to Avro messages** to more closely mimic prod environments
- **Find lighter weight Avro library** to reduce package size
- **Customization script** that update the topic name and message format
- **Dockerize** everything so this is totally platform independent and stateless

## Extras
- **Consumer.py** shows how to consume Kafka messages in Python in a more traditional way. It is not necessary for the Lambda to work. Instead, it provides another means of testing.

## Monitoring and Debugging
- Access the **Confluent Control Center** at `http://localhost:9021`
- View **Lambda logs** in real-time via `lambda.log`
- Monitor **bridge operations** in the bridge process output
- Use the **Kafka CLI tools** available in the broker container

## Contributing
This project is intended to be **forked and modified**. Feel free to create a **pull request** or open an **issue** if you encounter any problems.

## Notes on Production Deployment
When deploying to production:
1. Remove/ignore the bridge code - it's only for local development
2. Use the same template.yml and Lambda function code
3. AWS will handle the event source mapping automatically

The bridge pattern ensures that your local development environment closely mirrors production while maintaining full control over the local setup.

**Happy coding! 🚀**
