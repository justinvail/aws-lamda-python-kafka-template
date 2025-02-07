FROM public.ecr.aws/sam/build-python3.9:latest-x86_64

# Install AWS SAM CLI and build dependencies
RUN pip3 install --no-cache-dir aws-sam-cli && \
    yum update -y && \
    yum install -y \
    gcc \
    gcc-c++ \
    librdkafka \
    librdkafka-devel \
    python3-devel \
    zlib-devel \
    openssl-devel \
    cyrus-sasl-devel \
    java-11-amazon-corretto \
    java-11-amazon-corretto-devel \
    wget

# Set JAVA_HOME
ENV JAVA_HOME=/usr/lib/jvm/java-11-amazon-corretto

# Install Confluent Platform (includes Kafka tools)
RUN wget https://packages.confluent.io/archive/7.8/confluent-7.8.0.tar.gz && \
    tar xzf confluent-7.8.0.tar.gz && \
    mv confluent-7.8.0 /opt/confluent && \
    rm confluent-7.8.0.tar.gz

ENV PATH="${PATH}:/opt/confluent/bin:${JAVA_HOME}/bin"

# Install required Python packages with pip
RUN pip3 install --upgrade pip && \
    pip3 install --no-cache-dir \
    confluent-kafka==2.3.0 \
    httpx \
    attrs \
    cachetools \
    avro

# Create app directory
WORKDIR /app

# Expose necessary ports
EXPOSE 3001 9021 8081 9092

# Set environment variables
ENV DOCKER_HOST=unix:///var/run/docker.sock
ENV AWS_SAM_CLI_TELEMETRY=0
ENV PYTHONPATH=/app
ENV LD_LIBRARY_PATH=/usr/lib64

ENTRYPOINT ["/app/mock_aws_environment/docker-entrypoint.sh"]
