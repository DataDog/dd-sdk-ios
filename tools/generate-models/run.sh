#!/usr/bin/env zsh

if [[ ! -f "Package.swift" ]]; then
    echo "\`generate-models/run.sh\` must be run in repository root folder: \`./tools/config/generate-models/run.sh\`"; 
    exit 1;
fi

MODE_VERIFY="verify"
MODE_GENERATE="generate"
MODE="$1" # verify or generate

OUTPUT_FILE="RUMDataModels.swift"
TARGET_FILE="$(pwd)/Sources/Datadog/RUM/DataModels/$OUTPUT_FILE"

# get git reference
if [[ $MODE == $MODE_VERIFY ]]; then
    TARGET_LINE=$(tail -n 1 $TARGET_FILE)
    SHA_REGEX='[0-9a-f]{5,40}'
    if [[ $TARGET_LINE =~ $SHA_REGEX ]]; 
    then
        GIT_REF=$MATCH
    else
        echo "Target SHA could not be read in $TARGET_FILE !"
        exit 1;
    fi
elif [[ $MODE == $MODE_GENERATE ]]; then
    GIT_REF="master"
else
    echo "Invalid command!"
    echo "Model generation: run.sh generate"
    echo "Model verification: run.sh verify"
    exit 1;
fi

# fetch rum-events-format for given git ref
SCRIPT_LOC=$(dirname "$0")
cd $SCRIPT_LOC
if [[ ! -d "rum-events-format" ]]; then
    git clone git@github.com:DataDog/rum-events-format.git
fi
cd "rum-events-format"
git fetch origin $GIT_REF
git checkout FETCH_HEAD
SHA=$(git rev-parse HEAD)
cd ..

# install quicktype and generate model
if [[ ! -a $(npm bin)/quicktype ]]; then
    npm install DataDog/quicktype
fi
$(npm bin)/quicktype --lang swift --src-lang schema -o "$OUTPUT_FILE".bak --type-prefix RUMData --src rum-events-format/schemas
echo "// $SHA" >> "$OUTPUT_FILE".bak

LICENSE_HEADER="/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */
"
echo "$LICENSE_HEADER\n$(cat "$OUTPUT_FILE".bak)" > temp
mv temp "$OUTPUT_FILE".bak

# verify or move the generated model
if [[ $MODE == $MODE_VERIFY ]]; then
    DIFF=$(diff "$OUTPUT_FILE".bak $TARGET_FILE)
    if [[ ! -z $DIFF ]]; then 
        echo "Diff detected!\n$DIFF"
        exit 1;
    fi
    echo "Verified!"
    exit 0;
elif [[ $MODE == $MODE_GENERATE ]]; then
    cp "$OUTPUT_FILE".bak $TARGET_FILE
    exit 0;
fi

exit 1;