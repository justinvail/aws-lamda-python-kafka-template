#!/bin/bash
cd -- "${BASH_SOURCE%/*}/"
docker compose down --volumes;
docker container ls;
