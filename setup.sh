echo "Installing necessary CLIs and Libraries to a Python Virtual Environment (./.venv)"
echo ""

#stops the execution of a script if a command or pipeline has an error
set -e

echo "Creating virtual environment for python packages"
python3 -m venv ./.venv
echo ""
echo "Activating virtual environment. (Modifies path to search virtual environment first)"
source ./.venv/bin/activate || exit
echo ""

echo "Installing CLI: awscli-local[ver1]  in virtual environment"
pip3 install awscli-local
echo ""
echo "Installing CLI: aws-sam-cli  in virtual environment"
pip3 install aws-sam-cli
echo ""

echo "Installing Library: confluent-kafka  in virtual environment"
pip3 install confluent-kafka
echo ""
echo "Installing Library: avro  in virtual environment"
pip3 install avro
echo ""

echo "Deactivate virtual environment."
deactivate
