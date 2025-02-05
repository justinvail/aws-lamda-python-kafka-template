import logging
from avro.io import DatumReader, BinaryDecoder
from avro.schema import parse
from io import BytesIO
import base64
import json
import binascii

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.DEBUG)  # Changed to DEBUG for more detail

# Add a custom formatter to prepend the script name
class CustomFormatter(logging.Formatter):
    def format(self, record):
        record.message = record.getMessage()
        return f"lambda.py --> {record.message}"

# Apply the custom formatter to all handlers
for handler in logger.handlers:
    handler.setFormatter(CustomFormatter())

# If no handlers exist, create one
if not logger.handlers:
    handler = logging.StreamHandler()
    handler.setFormatter(CustomFormatter())
    logger.addHandler(handler)

# Avro Schema
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

# Parse the schema
parsed_schema = parse(json.dumps(USER_SCHEMA))


def deserialize_avro_message(avro_bytes):
    """Deserialize the Avro message using the avro library."""
    try:
        # Ensure we have bytes
        if isinstance(avro_bytes, str):
            # Handle base64 encoded strings
            avro_bytes = base64.b64decode(avro_bytes)
        elif isinstance(avro_bytes, (bytes, bytearray)):
            # Already in bytes format
            pass
        else:
            raise ValueError(f"Unexpected message type: {type(avro_bytes)}")

        logger.debug(f"Raw bytes (hex): {avro_bytes.hex()[:100]}...")

        # Create a BinaryDecoder
        bytes_reader = BytesIO(avro_bytes)
        decoder = BinaryDecoder(bytes_reader)

        # Create a DatumReader and read the data
        reader = DatumReader(parsed_schema)
        record = reader.read(decoder)

        logger.debug(f"Successfully deserialized record: {record}")

        # Validate the record has expected values
        if not record['user_name'] or record['old_id'] == 0:
            logger.warning("Record contains empty or zero values")

        return record
    except Exception as e:
        logger.error(f"Failed to deserialize message: {str(e)}", exc_info=True)
        logger.error(f"Raw bytes (hex): {avro_bytes.hex() if isinstance(avro_bytes, (bytes, bytearray)) else 'N/A'}")
        raise


def process_record(record):
    """Process a single Kafka record."""
    try:
        # Extract the message value
        message_value = record.get('value')
        if not message_value:
            logger.warning(f"Empty message value in record: {record}")
            return None

        # Log the message value type and content
        logger.debug(f"Processing record value type: {type(message_value)}")
        logger.debug(
            f"Record value content: "
            f"{message_value[:100] if isinstance(message_value, str) else 'non-string'}"
        )

        # Deserialize and process the message
        message = deserialize_avro_message(message_value)
        logger.info(f"Successfully processed message: {message}")
        return message
    except Exception as e:
        logger.error(f"Error processing record: {str(e)}", exc_info=True)
        raise


def handler(event, context):
    """Main Lambda handler function."""
    logger.info("Lambda function invoked")
    logger.info(f"Full event structure: {json.dumps(event, indent=2)}")
    logger.info(f"Context: {vars(context)}")

    failed_records = []

    try:
        # Check if we have records in the event
        records = event.get('Records', [])
        if not records:
            logger.warning("No records found in event")
            return {"batchItemFailures": []}

        logger.info(f"Number of records received: {len(records)}")

        # Log details of first record
        if records:
            first_record = records[0]
            logger.info(f"First record structure: {json.dumps(first_record, indent=2)}")

            # Log Kafka metadata if available
            kafka_info = first_record.get('kafka', {})
            if kafka_info:
                logger.info(f"Kafka metadata: {json.dumps(kafka_info, indent=2)}")

            # Examine the value format
            value = first_record.get('value')
            if value:
                logger.info(f"Value type: {type(value)}")
                try:
                    # Try to decode if base64
                    decoded = base64.b64decode(value)
                    logger.info(f"Successfully decoded base64. Hex: {decoded.hex()[:100]}...")
                except binascii.Error:
                    logger.info("Value is not base64 encoded")
                except Exception as e:
                    logger.error(f"Error examining value: {str(e)}")

        # Process each record
        for record in records:
            try:
                result = process_record(record)
                logger.info(f"Processed record result: {result}")
            except Exception as e:
                logger.error(f"Failed to process record: {str(e)}", exc_info=True)
                failed_records.append({
                    "itemIdentifier": record.get('kafka', {}).get('offset')
                })

        return {"batchItemFailures": failed_records}

    except Exception as e:
        logger.error(f"Unexpected error in handler: {str(e)}", exc_info=True)
        return {
            "batchItemFailures": [
                {"itemIdentifier": record.get('kafka', {}).get('offset')}
                for record in records
            ]
        }
