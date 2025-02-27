import logging
import requests
from avro.io import DatumReader, BinaryDecoder
from avro.schema import parse
from io import BytesIO
import base64
import json
import urllib.parse
from argparse import ArgumentParser

parser = ArgumentParser(description="Test Health")

parser.add_argument("--jwt")
parser.add_argument("--proxyUser", required=False)
parser.add_argument("--proxyPassword", required=False)

req_proxies = {}

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
    logger.info("Lambda function invoked\n")
    logger.info(f"Full event structure: {json.dumps(event, indent=2)}\n")
    logger.info(f"Context: {vars(context)}\n")

    try:
        # Check if we have records in the event
        records = event.get('Records', [])
        #TODO: replace with your AIDE user
        username = ""
        #TODO: replace with your AIDE password
        password = ""
        req_proxies = {
            "http": f"http://{username}:{password}@host.docker.internal:9443",
            "https": f"http://{username}:{password}@host.docker.internal:9443",
            "ftp": f"http://{username}:{password}@host.docker.internal:9443"
        }
        #TODO: JWT should be retrieved from elsewhere.  This is from POSTMAN file search request
        #TODO: File Numbers should be retrieved from Kafka message
        response = send_request("vefs-claimevidence-dev.dev.bip.va.gov", 
                                "123456788", "09241999",
                                "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJqdGkiOiI3NmQxOWE2OC03MDA1LTRhNjgtOWEzNC03MzEzZmI0MjMzNzMiLCJpYXQiOjE1MTYyMzkwMjIsImlzcyI6ImRldmVsb3BlclRlc3RpbmciLCJhcHBsaWNhdGlvbklEIjoiVkJNUy1VSSIsInVzZXJJRCI6ImNob3dhcl9zc3VwZXIiLCJzdGF0aW9uSUQiOiIzMTcifQ.33CyN4lq3WnyON2F4m4SlctTBtonBaySjf_7NDCBLl4",
                                req_proxies)
        return response

    except Exception as e:
        logger.error(f"Unexpected error in handler: {str(e)}", exc_info=True)
        return {
            "error": str(e)
        }
    
def send_request(host_name, source_number, dest_number, jwt_search, proxies):
    # TODO: sample request data from POSTMAN file search request.  This should be altered for actual solution
    request_data = {
        "pageRequest":{
            "resultsPerPage":2,
            "page":1
        },
        "filters":{}
    }
    #TODO: I would hope we can pull a JWT which can do both, but our current Postman test requests have two separate ones.
    search_headers = {
        "Authorization": f"Bearer {jwt_search}",
        "X-Folder-URI": f"VETERAN:FILENUMBER:{source_number}",
    }
    move_headers = {
        "Authorization": f"Bearer {jwt_search}",
        "X-Folder-URI": f"VETERAN:FILENUMBER:{dest_number}",
    }
    cert = ("static/vbms-internal.client.vbms.aide.oit.va.gov.crt", 
            "static/vbms-internal.client.vbms.aide.oit.va.gov.open.key")

    try:
        search_response = requests.post( 
            #TODO: Host name needs to be dynamic
            url=f"https://{host_name}/api/v1/rest/folders/files:search",
            json=request_data, 
            headers=search_headers,
            proxies=proxies,
            cert=cert,
            verify="static/lambda.pem"
        )
        logger.info(search_response.json())
        if search_response.status_code == 200:
            json = search_response.json()
            for file in json["files"]:
                uuid = file["uuid"]
                logger.info(uuid + "\n")
                move_response = requests.patch( 
                    #TODO: Host name needs to be dynamic
                    url=f"https://{host_name}/api/v1/rest/files/{uuid}:move",
                    headers=move_headers,
                    proxies=proxies,
                    cert=cert,
                    verify="static/lambda.pem"
                )
                logger.info(move_response.text)
                if move_response.status_code != 200:
                    raise Exception(f"Failed to move files associated with {source_number} to {dest_number}.")
            return {
                "Results": f"Successfully moved all files for File Number {source_number} to {dest_number}."
            }
        else: 
            raise Exception("Encountered error searching for files.")
    except requests.exceptions.ProxyError as e:
        logger.info(f"ProxyError:\n {e}")
        return {
            "error": str(e)
        }
    except requests.exceptions.RequestException as e:
        logger.info(f"RequestException:\n {e}")
        return {
            "error": str(e)
        }
    except Exception as e:
        logger.info(f"An unexpected error occurred:\n {e}")
        return {
            "error": str(e)
        }

    
if __name__ == "__main__":
    args = parser.parse_args()

    if args.proxyUser is not None and args.proxyPassword is not None:
        escaped_password = urllib.parse.quote(args.proxyPassword)
        proxy_url = f"http://{args.proxyUser}:{escaped_password}@host.docker.internal:9443"
        req_proxies = {
            "http": proxy_url,
            "https": proxy_url,
            "ftp": proxy_url
        }
        send_request(args.jwt, req_proxies)
