#!/bin/zsh
set -ex

VERSION="0.0.1"

docker build -t mutex:$VERSION .
docker tag mutex:$VERSION loganoconnell/mutex:$VERSION
docker image push loganoconnell/mutex:$VERSION