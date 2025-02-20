#!/bin/bash
# Script to create a proper Lambda deployment package with correct dependencies

set -e
echo "create_deployment_package.sh --> Creating Lambda deployment package..."

# Set up directories
BASE_DIR=/app
PACKAGE_DIR=/tmp/lambda_package
BUILD_DIR=/tmp/lambda_build
ZIP_PATH=/tmp/lambda_function.zip

# Clean previous builds
rm -rf $PACKAGE_DIR $BUILD_DIR
mkdir -p $PACKAGE_DIR $BUILD_DIR

# Copy Lambda function and dependencies
echo "create_deployment_package.sh --> Copying Lambda function code..."
cp $BASE_DIR/lambda_function/lambda_function.py $BUILD_DIR/

# Copy requirements.txt if it exists
if [ -f "$BASE_DIR/lambda_function/requirements.txt" ]; then
    echo "create_deployment_package.sh --> Copying requirements.txt..."
    cp $BASE_DIR/lambda_function/requirements.txt $BUILD_DIR/
else
    # Create requirements file with avro specifically
    echo "create_deployment_package.sh --> Creating requirements.txt with avro==1.11.1..."
    echo "avro==1.11.1" > $BUILD_DIR/requirements.txt
fi

# Add a debug helper to print environment
cat > $BUILD_DIR/debug_helper.py << 'INNEREOF'
import os
import sys

def debug_environment():
    """Helper function to debug Lambda environment"""
    debug_info = {
        "sys.path": sys.path,
        "current_dir": os.getcwd(),
        "dir_contents": os.listdir('.'),
        "env_vars": dict(os.environ),
        "python_version": sys.version
    }
    return debug_info

def debug_imports():
    """Test importing key modules"""
    import_results = {}
    try:
        import avro
        import_results["avro"] = f"Success, version: {getattr(avro, '__version__', 'unknown')}"

        # Test more specific imports
        from avro.io import DatumReader, BinaryDecoder
        import_results["avro.io"] = "Success"

        from avro.schema import parse
        import_results["avro.schema"] = "Success"
    except ImportError as e:
        import_results["error"] = str(e)

    return import_results
INNEREOF

# Modify lambda_function.py to include debug info
ORIGINAL_LAMBDA=$(cat $BUILD_DIR/lambda_function.py)
cat > $BUILD_DIR/lambda_function.py << INNEREOF
import json
import os
import sys
import logging

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.DEBUG)

# Import debug helper
try:
    from debug_helper import debug_environment, debug_imports
    logger.info("Debug helper imported successfully")
except ImportError as e:
    logger.error(f"Failed to import debug helper: {e}")
    def debug_environment():
        return {"error": "Debug helper not available"}
    def debug_imports():
        return {"error": "Debug helper not available"}

# Original lambda function code
$ORIGINAL_LAMBDA

# Wrap handler with debugging
_original_handler = handler
def handler(event, context):
    """Wrapper for original handler with debugging"""
    try:
        logger.info("Lambda function invoked with fixed package")
        logger.info(f"Event: {json.dumps(event)}")
        logger.info(f"Environment debug info: {json.dumps(debug_environment(), default=str)}")
        logger.info(f"Import test results: {json.dumps(debug_imports(), default=str)}")

        # Call original handler
        return _original_handler(event, context)
    except Exception as e:
        logger.error(f"Error in handler: {str(e)}", exc_info=True)
        raise
INNEREOF

# Copy Avro schemas if they exist
if [ -d "$BASE_DIR/schemas" ]; then
    echo "create_deployment_package.sh --> Copying Avro schemas..."
    mkdir -p $BUILD_DIR/schemas
    cp -r $BASE_DIR/schemas/* $BUILD_DIR/schemas/
fi

# Install dependencies from requirements.txt
cd $BUILD_DIR
echo "create_deployment_package.sh --> Installing dependencies from requirements.txt..."
pip install -r requirements.txt -t . --upgrade
echo "create_deployment_package.sh --> Installed Python packages:"
pip list

# Create the ZIP package
echo "create_deployment_package.sh --> Creating ZIP package..."
zip -r $ZIP_PATH . -x "*.pyc" "__pycache__/*" "*.dist-info/*" "*.egg-info/*"

echo "create_deployment_package.sh --> Lambda deployment package created at $ZIP_PATH"
echo "create_deployment_package.sh --> Package contents:"
unzip -l $ZIP_PATH | tail -n +4 | head -n -2 | awk '{print $4}'

# Copy to a location accessible by SAM
mkdir -p $PACKAGE_DIR
cp $ZIP_PATH $PACKAGE_DIR/
echo "create_deployment_package.sh --> Deployment package copied to $PACKAGE_DIR/lambda_function.zip"
