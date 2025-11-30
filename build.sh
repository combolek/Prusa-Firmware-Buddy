#!/bin/bash -x

set -e

BRANCH=$(git rev-parse --abbrev-ref HEAD)
DESCRIBE=$(git describe --tags)
BUILD_NUMBER=$(echo $DESCRIBE | cut -d- -f 2)
PROJECT_VERSION_SUFFIX_SHORT=+$(echo $DESCRIBE | cut -d- -f 2-)
PROJECT_VERSION_SUFFIX="$PROJECT_VERSION_SUFFIX_SHORT-$BRANCH"

UPLOAD=0
if [[ "$1" = "--upload" ]]; then
    UPLOAD=1
    shift
fi

if [[ ! -d .venv ]]; then
    python3 utils/bootstrap.py
fi

.venv/bin/python utils/build.py \
    --preset coreone \
    --bootloader empty \
    -D DEVELOPMENT_ITEMS_ENABLED:BOOL=0 \
    -D BUILD_NUMBER:STRING="$BUILD_NUMBER" \
    -D PROJECT_VERSION_SUFFIX_SHORT:STRING="$PROJECT_VERSION_SUFFIX_SHORT" \
    -D PROJECT_VERSION_SUFFIX:STRING="$PROJECT_VERSION_SUFFIX" \
    "$@"

if [[ $UPLOAD -eq 1 ]]; then
    ./upload.sh
fi
