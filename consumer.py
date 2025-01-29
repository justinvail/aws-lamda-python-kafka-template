from confluent_kafka import Consumer, KafkaException, KafkaError
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroDeserializer
from confluent_kafka.serialization import SerializationContext, MessageField

# Load the Avro schema from an external file
with open("lambda_function/user.avsc", "r") as schema_file:
    avro_schema_str = schema_file.read()

# Kafka topic name
topic_name = "user-id-change-topic"

# Kafka configuration
kafka_config = {
    'bootstrap.servers': 'localhost:9092',  # Ensure the broker is reachable on localhost:9092
    'group.id': 'user-consumer-group',
    'auto.offset.reset': 'earliest',  # Start consuming from the earliest message
}

# Schema Registry configuration
schema_registry_config = {
    'url': 'http://localhost:8081'  # Ensure the Schema Registry is accessible
}

# Initialize the Schema Registry client
schema_registry_client = SchemaRegistryClient(schema_registry_config)

# Initialize the Avro deserializer
avro_deserializer = AvroDeserializer(
    schema_registry_client=schema_registry_client,
    schema_str=avro_schema_str,
    from_dict=lambda obj, ctx: obj  # Use a simple pass-through deserializer
)

# Initialize the Kafka consumer
consumer = Consumer(kafka_config)

# Subscribe to the topic
consumer.subscribe([topic_name])

# Poll for new messages
try:
    while True:
        msg = consumer.poll(timeout=1.0)  # Timeout in seconds

        if msg is None:
            continue  # No message available, continue polling
        if msg.error():
            if msg.error().code() == KafkaError.PARTITION_EOF:
                print(f"End of partition reached {msg.partition}")
            else:
                raise KafkaException(msg.error())
        else:
            # Deserialize the Avro message value
            value = avro_deserializer(msg.value(), SerializationContext(msg.topic(),
                                                                        MessageField.VALUE))
            print(f"Consumed message: {value}")

except KeyboardInterrupt:
    print("Consumer interrupted by user")

finally:
    # Close the consumer connection
    consumer.close()
