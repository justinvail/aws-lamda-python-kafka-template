import json
import base64
import requests
from confluent_kafka import Consumer, KafkaError
from avro.io import DatumReader, BinaryDecoder
from avro.schema import parse
from io import BytesIO
import logging

# Set up logging
logging.basicConfig(level=logging.INFO,
                    format='kafka_lambda_bridge.py --> %(message)s')
logger = logging.getLogger(__name__)

# Load and parse the schema
with open("../schemas/user.avsc", "r") as schema_file:
    schema_json = schema_file.read()
    parsed_schema = parse(schema_json)


def create_kafka_consumer():
    consumer_conf = {
        'bootstrap.servers': 'localhost:9092',
        'group.id': 'sam-local-consumer-group',
        'auto.offset.reset': 'earliest'
    }
    return Consumer(consumer_conf)


def invoke_lambda(messages):
    lambda_url = "http://127.0.0.1:3001/2015-03-31/functions/KafkaConsumerFunction/invocations"

    records = []
    for msg in messages:
        # Debug: Print raw message details
        logger.info(f"\n=== Message at offset {msg.offset()} ===")
        logger.info(f"Raw value type: {type(msg.value())}")
        logger.info(f"Raw value length: {len(msg.value()) if msg.value() else 0}")
        logger.info(f"Raw value hex: {msg.value().hex() if msg.value() else None}")

        # Try to decode Avro before creating record
        try:
            bytes_reader = BytesIO(msg.value())
            decoder = BinaryDecoder(bytes_reader)
            reader = DatumReader(parsed_schema)
            decoded = reader.read(decoder)
            logger.info(f"Successfully decoded Avro message: {decoded}")
        except Exception as e:
            logger.error(f"Failed to decode Avro message: {e}")
            decoded = None

        record = {
            "topic": msg.topic(),
            "partition": msg.partition(),
            "offset": msg.offset(),
            "timestamp": msg.timestamp()[1],
            "timestampType": msg.timestamp()[0],
            "key": msg.key().decode('utf-8') if msg.key() else None,
            "value": base64.b64encode(msg.value()).decode('utf-8') if msg.value() else None,
            "headers": [[k, v.decode('utf-8')] for k, v in msg.headers()] if msg.headers() else [],
            "kafka": {
                "topic": msg.topic(),
                "partition": msg.partition(),
                "offset": msg.offset()
            }
        }
        records.append(record)

    event = {
        "Records": records
    }

    try:
        logger.info(f"Invoking Lambda with event: {json.dumps(event, indent=2)}")
        response = requests.post(lambda_url, json=event)
        logger.info(f"Lambda response status: {response.status_code}")
        logger.info(f"Lambda response body: {response.text}")
        return response.status_code == 200
    except Exception as e:
        logger.error(f"Error invoking Lambda: {str(e)}")
        return False


def main():
    consumer = create_kafka_consumer()
    consumer.subscribe(['user-id-change-topic'])

    batch = []
    batch_size = 10

    logger.info("Starting Kafka consumer bridge...")
    try:
        while True:
            msg = consumer.poll(1.0)
            if msg is None:
                continue

            if msg.error():
                if msg.error().code() == KafkaError._PARTITION_EOF:
                    logger.info(f"Reached end of partition: {msg.error()}")
                else:
                    logger.error(f"Error: {msg.error()}")
                continue

            batch.append(msg)

            if len(batch) >= batch_size:
                success = invoke_lambda(batch)
                if success:
                    consumer.commit()
                batch = []

    except KeyboardInterrupt:
        logger.info("Shutting down...")
    finally:
        consumer.close()


if __name__ == "__main__":
    main()
