import random
from confluent_kafka import Producer
import avro.schema
import json

# Load the Avro schema
with open("lambda_function/user.avsc", "r") as schema_file:
    avro_schema_str = schema_file.read()
    parsed_schema = avro.schema.parse(avro_schema_str)


def generate_user_name(first_name, last_name):
    return f"{first_name.lower()}_{last_name.lower()}"


def generate_random_id():
    return random.randint(10000000, 99999999)


def generate_sample_data():
    first_names = ["John", "Jane", "Alice", "Bob", "Michael", "Sarah", "David", "Emily"]
    last_names = ["Doe", "Smith", "Johnson", "Brown", "Williams", "Taylor"]

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


def delivery_report(err, msg):
    if err is not None:
        print(f'producer.py --> Message delivery failed: {err}')
    else:
        print(f'producer.py --> Message delivered to {msg.topic()} [{msg.partition()}] at offset {msg.offset()}')


def main():
    # Simple Avro serializer (without schema registry)
    def serialize_avro(obj, ctx):
        import io
        from avro.io import DatumWriter, BinaryEncoder

        writer = DatumWriter(parsed_schema)
        bytes_writer = io.BytesIO()
        encoder = BinaryEncoder(bytes_writer)
        writer.write(obj, encoder)
        return bytes_writer.getvalue()

    # Kafka producer configuration
    producer_config = {
        'bootstrap.servers': 'localhost:9092'
    }

    # Create producer
    producer = Producer(producer_config)

    # Produce some messages
    try:
        for _ in range(1):
            data = generate_sample_data()
            # Serialize the data using Avro
            serialized_data = serialize_avro(data, None)

            # Print what we're sending (for debugging)
            print(f"producer.py --> Sending message: {data}")

            producer.produce(
                topic='user-id-change-topic',
                value=serialized_data,
                callback=delivery_report
            )
            producer.poll(0)  # Trigger delivery reports

        # Wait for any outstanding messages to be delivered
        producer.flush()

    except Exception as e:
        print(f"producer.py --> Error producing message: {e}")


if __name__ == '__main__':
    main()
