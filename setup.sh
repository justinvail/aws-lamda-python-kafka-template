echo "Installing necessary CLIs adding them to system path via brew."
echo ""
brew install pipx
brew install awscli-local
brew install aws-sam-cli
echo "Installing system level requirements."
echo ""
pip3 install confluent-kafka
pip3 install httpx
pip3 install attrs
pip3 install cachetools
pip3 install avro
