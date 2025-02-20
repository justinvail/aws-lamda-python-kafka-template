#!/bin/bash
# Create a test Lambda package to verify module imports

# Create a clean test directory
TEST_DIR=/tmp/lambda_test
mkdir -p $TEST_DIR
cd $TEST_DIR

# Create a minimal lambda_function.py
cat > lambda_function.py << 'EOF'
def handler(event, context):
    print("Handler successfully executed!")
    return {
        "statusCode": 200,
        "body": "Success - Module properly imported"
    }
EOF

# Make it executable
chmod 755 lambda_function.py

# Create a simple test event
cat > event.json << 'EOF'
{
  "Records": []
}
EOF

echo "Test package created at $TEST_DIR"
echo "You can test it with: cd $TEST_DIR && sam local invoke -e event.json"
