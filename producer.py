import random
from confluent_kafka import Producer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer
from confluent_kafka.serialization import SerializationContext, MessageField

# Load the Avro schema from an external file
with open("lambda_function/user.avsc", "r") as schema_file:
    avro_schema_str = schema_file.read()

# Kafka topic name
topic_name = "user-id-change-topic"

# Kafka configuration
kafka_config = {
    'bootstrap.servers': 'localhost:9092',
}

# Schema Registry configuration
schema_registry_config = {
    'url': 'http://localhost:8081'
}


def generate_user_name(first_name, last_name):
    return f"{first_name}_{last_name}".lower()


def generate_random_id():
    return random.randint(10000000, 99999999)


def generate_sample_data():
    first_names = ["John", "Jane", "Alice", "Bob", "Michael", "Sarah", "David", "Emily", "Chris",
                   "Emma"]
    last_names = ["Doe", "Smith", "Johnson", "Brown", "Williams", "Taylor", "Anderson", "Thomas",
                  "Jackson", "White"]

    first_name = random.choice(first_names)
    last_name = random.choice(last_names)
    user_name = generate_user_name(first_name, last_name)
    old_id = generate_random_id()
    new_id = generate_random_id()

    return {
        "user_name": user_name,
        "old_id": old_id,
        "new_id": new_id
    }


# Initialize the Schema Registry client
schema_registry_client = SchemaRegistryClient(schema_registry_config)

# Initialize the Avro serializer
avro_serializer = AvroSerializer(
    schema_registry_client=schema_registry_client,
    schema_str=avro_schema_str,
    to_dict=lambda record, ctx: record  # Use a simple pass-through serializer for this example
)

# Initialize the Kafka producer
producer = Producer(kafka_config)

# Generate and produce 100 messages
try:
    for _ in range(10000):
        sample_data = generate_sample_data()
        serialized_data = avro_serializer(sample_data,
                                          SerializationContext(topic_name, MessageField.VALUE))

        producer.produce(
            topic=topic_name,
            value=serialized_data,
        )
    producer.flush()
except Exception as e:
    print("Error while producing messages: {}".format(e))
