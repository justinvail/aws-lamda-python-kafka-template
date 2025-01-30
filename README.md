# Confluent Kafka & AWS Lambda Demo

## Overview
This project is a **prototype** designed to demonstrate the integration of a **self-managed Confluent Kafka** with **AWS Lambda**, deployed locally using **LocalStack**. The entire setup runs in **Docker** and is intended to be **forked, updated, and deployed** by others.

## Features
- **Confluent Kafka** environment running in Docker.
- **AWS Lambda** function written in Python, deployed to **LocalStack**.
- **Automated setup** via `setup.sh`.
- **Automated deployment** via `start-all.sh`.
- **Message producer** (`producer.py`) generates **10,000 randomized messages** at a time.
- **AWS user roles, policies, and secrets** are dynamically created.
- **Event source mapping** is established between Kafka and Lambda.
- **Automatic cleanup** of generated Lambda package.

## Prerequisites
Ensure you have the following installed before proceeding:
- **chmod 755** on **start-all.sh**, **stop-all.sh**, and **setup.sh** (This may or may not be need depending on your system)
- **LocalStack Pro Key** (I recommend using a temp mail service to achieve this)
- **Docker** & **Docker Compose**
- **Python3** (via `brew` or manually installed)

## Setup Instructions
1. Clone this repository:
   ```sh
   git clone https://github.com/yourusername/confluent-kafka-lambda-demo.git
   cd confluent-kafka-lambda-demo
   ```
2. Get permission to setup scripts (if you system requires it):
   ```sh
   chmod 755 setup.sh
   chmod 755 start-all.sh
   chmod 755 stop-all.sh
   ```
3. Run the **setup script** to install dependencies:
   ```sh
   ./setup.sh
   ```
4. Start all services and deploy the Lambda:
   ```sh
   ./start-all.sh
   ```
   This will:
    - Start all **Docker containers**.
    - Gather dependencies and package the **Lambda function**.
    - Create **AWS IAM roles and policies**.
    - Generate an **AWS Secrets Manager secret** for Kafka authentication.
    - Create an **event source mapping**.
    - Run the **Kafka producer (`producer.py`)**.
    - Clean up any temporary files.
5. Stop all the services and clean up docker:
   ```sh
   ./stop-all.sh
   ```

## How It Works
1. **Kafka Setup:** A self-managed Kafka cluster is started using Docker.
2. **Lambda Deployment:** The Python Lambda function is packaged and deployed to LocalStack.
3. **Event Source Mapping:** Kafka is configured as an event source for the Lambda function.
4. **Message Production:** The `producer.py` script generates **random messages** and sends them to Kafka.
5. **Lambda Execution:** The Lambda function consumes messages and processes them.

## Customization
- Modify the **Lambda function** in `lambda_function/lambda_function.py`.
- Change the **number of messages generated** in `producer.py`.
- Update the **message schema** in lambda_function/user.avsc`.

## Cleanup
To stop all running services:
```sh
./stop-all.sh
```

## Potential Upcoming Changes
- **Transition from AWS CLI to CloudFormation and the Serverless Application Model (SAM)** for improved infrastructure-as-code management.
- **Introduce security measures** such as TLS encryption or SASL authentication for Kafka.
- **Implement access control lists (ACLs)** for fine-grained permission management in Kafka.
- **Update lambda_function.py to use Confluent Schema Registry on initialization** to reduce package size, increase resiliency, and increase modifiability.
- **Update lambda_function.py to do something interesting with its message data** like call an api found here: **https://github.com/toddmotto/public-apis/**

## Extras
- **Consumer.py** shows how to consumer kafka messages in python in a more traditional way.  It is not necessary for the lambda to work.  Instead, it provides another means of testing. 

---

## Contributing
This project is intended to be **forked and modified**. Feel free to create a **pull request** or open an **issue** if you encounter any problems.


**Happy coding! 🚀**

