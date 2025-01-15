#!/bin/bash
cd -- "${BASH_SOURCE%/*}/"
docker compose up -d
c3_url="http://localhost:9021"
explanation=" seconds have past."
echo "Waiting for Kafka ecosystem to start."
duration_past=0
while ! curl --head --silent --fail "$c3_url" >/dev/null; do
  echo -ne " -> $duration_past$explanation\r"
  ((duration_past+=1))
  sleep 1
done
echo ""
echo "Ecosystem started!"
echo ""
echo "Installing python requirements"
echo ""
pip3 install confluent_kafka
pip3 install httpx
pip3 install avro
pip3 install kafka
pip3 install attrs
pip3 install cachetools
pip3 install fastavro
echo "Running producer.py"
python3 producer.py
docker container ls
open http://localhost:9021
