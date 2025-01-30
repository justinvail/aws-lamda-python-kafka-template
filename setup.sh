#!/bin/bash
echo "Installing system level requirements."
echo ""
pip3 install confluent-kafka
pip3 install awscli-local
pip3 install aws-sam-cli
brew install jq
echo "Changing stop-all script permissions."
echo ""
chmod 500 stop-all.sh
echo ""
echo "Installing python requirements for lambda package in virtual environment."
cd lambda_function || exit
pip3 install --target . fastavro
