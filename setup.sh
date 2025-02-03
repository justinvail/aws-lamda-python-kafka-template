echo "Installing pipx and adding to system path."
echo ""
brew install pipx
source ~/.zshrc
pipx --version
echo "Installing system level requirements."
echo ""
pip3 install confluent-kafka
pip3 install httpx
pip3 install attrs
pip3 install cachetools
pip3 install fastavro
pipx install awscli-local
pipx install aws-sam-cli
brew install jq
echo ""
echo "Installing python requirements for lambda package in virtual environment."
cd lambda_function || exit
pip3 install --target . fastavro
