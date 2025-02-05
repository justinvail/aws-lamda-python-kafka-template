from confluent_kafka import Consumer, KafkaException, KafkaError
import avro.schema
from avro.io import DatumReader, BinaryDecoder
from io import BytesIO
import json

# Same schema as producer and Lambda
USER_SCHEMA = {
    "namespace": "example.avro",
    "type": "record",
    "name": "User",
    "fields": [
        {"name": "user_name", "type": ["string", "null"]},
        {"name": "old_id", "type": ["int", "null"]},
        {"name": "new_id", "type": ["int", "null"]},
    ],
}


def deserialize_avro(avro_bytes, schema):
    """Deserialize Avro message."""
    reader = DatumReader(schema)
    bytes_reader = BytesIO(avro_bytes)
    decoder = BinaryDecoder(bytes_reader)
    return reader.read(decoder)


# Parse schema
schema = avro.schema.parse(json.dumps(USER_SCHEMA))

# Kafka configuration
kafka_config = {
    'bootstrap.servers': 'localhost:9092',
    'group.id': 'test-consumer-group',
    'auto.offset.reset': 'earliest'
}

# Initialize consumer
consumer = Consumer(kafka_config)

# Subscribe to topic
consumer.subscribe(['user-id-change-topic'])

try:
    while True:
        msg = consumer.poll(timeout=1.0)

        if msg is None:
            continue
        if msg.error():
            if msg.error().code() == KafkaError.PARTITION_EOF:
                print(f"consumer.py --> Reached end of partition {msg.partition()}")
            else:
                raise KafkaException(msg.error())
        else:
            try:
                # Deserialize the message value
                value = deserialize_avro(msg.value(), schema)
                print(f"consumer.py --> Received message: {value}")
                print(f"consumer.py --> Partition: {msg.partition()}, Offset: {msg.offset()}")
            except Exception as e:
                print(f"consumer.py --> Error deserializing message: {str(e)}")

except KeyboardInterrupt:
    print("consumer.py --> Shutting down consumer...")

finally:
    consumer.close()
