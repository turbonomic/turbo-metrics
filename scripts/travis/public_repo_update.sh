#!/usr/bin/env bash

set -e

if [ -z "${PUBLIC_GITHUB_TOKEN}" ]; then
    echo "Error: PUBLIC_GITHUB_TOKEN environment variable is not set"
    exit 1
fi
TC_PUBLIC_REPO=turbonomic-container-platform

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
SRC_DIR=${SCRIPT_DIR}/../..
OUTPUT_DIR=${SCRIPT_DIR}/../../_output

if ! command -v git > /dev/null 2>&1; then
    echo "Error: git could not be found."
    exit 1
fi

echo "===> Cloning public repo..."; 
mkdir -p ${OUTPUT_DIR}
cd ${OUTPUT_DIR}
git clone https://${PUBLIC_GITHUB_TOKEN}@github.com/IBM/${TC_PUBLIC_REPO}.git
cd ${TC_PUBLIC_REPO}


mkdir -p turbo-metrics/crd turbo-metrics/samples
cd turbo-metrics

# copy CRD files
echo "===> Copy CRD files"
cp ${SRC_DIR}/config/crd/bases/* crd/

# copy sample yaml files
echo "===> Copy sample yaml files"
cp ${SRC_DIR}/config/samples/* samples/

# Add README
echo "===> Adding README"
echo "See the [documentation](https://www.ibm.com/docs/en/tarm/latest?topic=prometheus-enabling-metrics-collection-prometurbo)" > README.md

# commit all modified source files to the public repo
echo "===> Commit modified files to public repo"
cd .. 
git add .
if ! git diff --quiet --cached; then
    git commit -m "sync turbo-metrics"
    git push
else
    echo "No changed files"
fi

# cleanup
rm -rf ${OUTPUT_DIR}

echo ""
echo "Update public repo complete."
