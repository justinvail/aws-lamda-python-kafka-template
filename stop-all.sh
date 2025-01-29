#!/bin/bash
cd -- "${BASH_SOURCE%/*}/" || exit
docker compose down --volumes;
docker container ls;
