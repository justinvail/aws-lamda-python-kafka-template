echo "Installing pipx and adding to system path."
echo ""
python3 -m pip install --user pipx
python3 -m pipx ensurepath
source ~/.zshrc
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
echo "Changing stop-all script permissions."
echo ""
chmod 500 stop-all.sh
echo ""
echo "Installing python requirements for lambda package in virtual environment."
cd lambda_function || exit
pip3 install --target . fastavro
