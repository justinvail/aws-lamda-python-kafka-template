import logging
import fastavro
from io import BytesIO
import base64

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

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


def deserialize_avro_message(avro_bytes):
    """Deserialize the Avro message using fastavro."""
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

        reader = fastavro.reader(BytesIO(avro_bytes), USER_SCHEMA)
        for record in reader:
            return record
    except Exception as e:
        logger.error(f"Failed to deserialize message: {str(e)}")
        logger.error(f"Raw message (hex): {avro_bytes.hex() if isinstance(avro_bytes, (bytes, bytearray)) else 'N/A'}")
        raise


def process_record(record):
    """Process a single Kafka record."""
    try:
        # Extract the message value
        message_value = record.get('value')
        if not message_value:
            logger.warning(f"Empty message value in record: {record}")
            return None

        # Deserialize and process the message
        message = deserialize_avro_message(message_value)
        logger.info(f"Successfully processed message: {message}")
        return message
    except Exception as e:
        logger.error(f"Error processing record: {str(e)}")
        raise


def handler(event, context):
    """Main Lambda handler function."""
    logger.info("Lambda function invoked")
    logger.debug(f"Received event: {event}")

    failed_records = []

    try:
        # Check if we have records in the event
        records = event.get('Records', [])
        if not records:
            logger.warning("No records found in event")
            return {"batchItemFailures": []}

        # Process each record
        for record in records:
            try:
                process_record(record)
            except Exception as e:
                # Log the error and add to failed records
                logger.error(
                    f"Failed to process record {record.get('kafka', {}).get('offset')}: {str(e)}")
                failed_records.append({
                    "itemIdentifier": record.get('kafka', {}).get('offset')
                })

        # Return any failed records
        return {"batchItemFailures": failed_records}

    except Exception as e:
        logger.error(f"Unexpected error in handler: {str(e)}")
        # In case of unexpected errors, fail all records to ensure no data loss
        return {
            "batchItemFailures": [
                {"itemIdentifier": record.get('kafka', {}).get('offset')}
                for record in records
            ]
        }
