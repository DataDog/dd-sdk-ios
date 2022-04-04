#!/usr/bin/env zsh

if [[ ! -f "Package.swift" ]]; then
    echo "\`rum-models-generator/run.sh\` must be run in repository root folder: \`./tools/rum-models-generator/run.sh\`"; 
    exit 1;
fi

MODE="$1"
MODE_VERIFY="verify"
MODE_GENERATE="generate"

TARGET_SWIFT_FILE="$(pwd)/Sources/Datadog/RUM/DataModels/RUMDataModels.swift"
TARGET_OBJC_FILE="$(pwd)/Sources/DatadogObjc/RUM/RUMDataModels+objc.swift"

if [[ "$MODE" != "$MODE_VERIFY" ]] && [[ "$MODE" != "$MODE_GENERATE" ]]; then
    echo "Invalid command.\n"
    echo "Usage:"
    echo "	run.sh generate"
    echo "	run.sh verify"
	exit 1
fi

# Get $GIT_REF for current $MODE
if [[ "$MODE" == "$MODE_VERIFY" ]]; then
    SHA_REGEX='[0-9a-f]{5,40}'

    # Get SHA signature from Swift file
	LAST_LINE_IN_SWIFT_FILE=$(tail -n 1 $TARGET_SWIFT_FILE)
	if [[ $LAST_LINE_IN_SWIFT_FILE =~ $SHA_REGEX ]]; then
		SWIFT_GIT_REF="$MATCH"
    else
        echo "❌ Cannot read git SHA signature in $TARGET_SWIFT_FILE"
        exit 1;
	fi

    # Get SHA signature from Objc file
    LAST_LINE_IN_OBJC_FILE=$(tail -n 1 $TARGET_OBJC_FILE)
    if [[ $LAST_LINE_IN_OBJC_FILE =~ $SHA_REGEX ]]; then
        OBJC_GIT_REF="$MATCH"
    else
        echo "❌ Cannot read git SHA signature in $TARGET_OBJC_FILE"
        exit 1;
    fi

    if [[ "$SWIFT_GIT_REF" != "$OBJC_GIT_REF" ]]; then
        echo "❌ Git SHA signatures are different in $TARGET_SWIFT_FILE ($SWIFT_GIT_REF) and $TARGET_OBJC_FILE ($OBJC_GIT_REF)"
        exit 1;
    fi

    GIT_REF=$SWIFT_GIT_REF
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

# Generate RUM models (Swift) file in temporary location
mkdir -p ".temp"
GENERATED_SWIFT_FILE=".temp/RUMDataModels.swift"
$GENERATOR generate-swift --path "rum-events-format/rum-events-format.json" > $GENERATED_SWIFT_FILE
echo "// Generated from https://github.com/DataDog/rum-events-format/tree/$SHA" >> $GENERATED_SWIFT_FILE

# Generate RUM models (Objc) file in temporary location
mkdir -p ".temp"
GENERATED_OBJC_FILE=".temp/RUMDataModels+objc.swift"
$GENERATOR generate-objc --path "rum-events-format/rum-events-format.json" > $GENERATED_OBJC_FILE
echo "// Generated from https://github.com/DataDog/rum-events-format/tree/$SHA" >> $GENERATED_OBJC_FILE

if [[ $MODE == $MODE_VERIFY ]]; then
	# When verifying, check if there is no difference between TARGET_FILE and GENERATED_FILE
    SWIFT_DIFF=$(diff $GENERATED_SWIFT_FILE $TARGET_SWIFT_FILE)
    OBJC_DIFF=$(diff $GENERATED_OBJC_FILE $TARGET_OBJC_FILE)

    if [[ ! -z $SWIFT_DIFF ]]; then
    	echo "❌ $TARGET_SWIFT_FILE is out of sync with rum-events-format: $SHA"
    	echo "Difference was found when comparing it with template file:"
    	echo ">>>"
        echo "$SWIFT_DIFF"
        echo "<<<"
        exit 1;
    elif [[ ! -z $OBJC_DIFF ]]; then
        echo "❌ $TARGET_OBJC_FILE is out of sync with rum-events-format: $SHA"
        echo "Difference was found when comparing it with template file:"
        echo ">>>"
        echo "$OBJC_DIFF"
        echo "<<<"
        exit 1;
    else
    	echo "✅ $TARGET_SWIFT_FILE is up to date with rum-events-format: $SHA"
        echo "✅ $TARGET_OBJC_FILE is up to date with rum-events-format: $SHA"
	    exit 0;
    fi
else
	# When generating, replace TARGET_FILE with GENERATED_FILE
    cp $GENERATED_SWIFT_FILE $TARGET_SWIFT_FILE
    echo "✅ $TARGET_SWIFT_FILE was updated to rum-events-format: $SHA"

    cp $GENERATED_OBJC_FILE $TARGET_OBJC_FILE
    echo "✅ $TARGET_OBJC_FILE was updated to rum-events-format: $SHA"
    exit 0;
fi

exit 1
