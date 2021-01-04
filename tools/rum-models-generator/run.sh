#!/usr/bin/env zsh

if [[ ! -f "Package.swift" ]]; then
    echo "\`rum-models-generator/run.sh\` must be run in repository root folder: \`./tools/rum-models-generator/run.sh\`"; 
    exit 1;
fi

MODE="$1"
MODE_VERIFY="verify"
MODE_GENERATE="generate"

TARGET_FILE="$(pwd)/Sources/Datadog/RUM/DataModels/RUMDataModels.swift"

if [[ "$MODE" != "$MODE_VERIFY" ]] && [[ "$MODE" != "$MODE_GENERATE" ]]; then
    echo "Invalid command.\n"
    echo "Usage:"
    echo "	run.sh generate"
    echo "	run.sh verify"
	exit 1
fi

# Get $GIT_REF for current $MODE
if [[ "$MODE" == "$MODE_VERIFY" ]]; then
	LAST_LINE=$(tail -n 1 $TARGET_FILE)
	SHA_REGEX='[0-9a-f]{5,40}'

	if [[ $LAST_LINE =~ $SHA_REGEX ]]; then
		GIT_REF="$MATCH"
	else
		echo "Cannot find SHA git reference in $TARGET_FILE";
		exit 1
	fi
else
	GIT_REF="master"
fi

# Change to script's directory
cd $(dirname "$0")

# Fetch rum-events-format for given $GIT_REF
rm -rf rum-events-format
git clone git@github.com:DataDog/rum-events-format.git
cd rum-events-format
git fetch origin $GIT_REF
git checkout FETCH_HEAD
SHA=$(git rev-parse HEAD)
cd -

# Prepare `rum-models-generator` executable
swift build --configuration release
GENERATOR=".build/x86_64-apple-macosx/release/rum-models-generator"

# Generate file in temporary location
mkdir -p ".temp"
GENERATED_FILE=".temp/RUMDataModels.swift"
$GENERATOR generate-swift --path "rum-events-format/schemas" > $GENERATED_FILE
echo "// Generated from https://github.com/DataDog/rum-events-format/tree/$SHA" >> $GENERATED_FILE

if [[ $MODE == $MODE_VERIFY ]]; then
	# When verifying, check if there is no difference between $TARGET_FILE and $GENERATED_FILE
    DIFF=$(diff $GENERATED_FILE $TARGET_FILE)
    if [[ ! -z $DIFF ]]; then 
    	echo "🔥 $TARGET_FILE is out of sync with rum-events-format: $SHA"
    	echo "Difference was found when comparing it with template file:"
    	echo ">>>"
        echo "$DIFF"
        echo "<<<"
        exit 1;
    else
    	echo "✅ $TARGET_FILE is up to date with rum-events-format: $SHA"
	    exit 0;
    fi
else
	# When generating, replace $TARGET_FILE with $GENERATED_FILE
    cp $GENERATED_FILE $TARGET_FILE
    echo "✅ $TARGET_FILE was updated to rum-events-format: $SHA"
    exit 0;
fi

exit 1
