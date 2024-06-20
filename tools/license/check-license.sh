#!/bin/zsh

if [ ! -f "Package.swift" ]; then
	echo "\`check-license.sh\` must be run in repository root folder: \`./tools/license/check-license.sh\`"; exit 1
fi

IFS=$'\n'

# Lists all files requiring the license header.
function files {
	# Exclude all auto-generated and 3rd party files.
	find -E . \
		-iregex '.*\.(swift|h|m|py)$' \
		-type f \( ! -name "Package.swift" \) \
		-not -path "*/.build/*" \
		-not -path "*Pods*" \
		-not -path "*Carthage/Build/*" \
		-not -path "*Carthage/Checkouts/*" \
		-not -path "./tools/rum-models-generator/rum-events-format/*" \
		-not -path "*/tools/distribution/venv/*" \
		-not -path "*/tools/ci/venv/*" \
		-not -path "*.xcframework/*" \
		-not -path "*.xcarchive/*" \
		-not -name "OTSpan.swift" \
		-not -name "OTFormat.swift" \
		-not -name "OTTracer.swift" \
		-not -name "OTReference.swift" \
		-not -name "OTSpanContext.swift" \
		-not -name "Versioning.swift" \
		-not -name "__init__.py"
}

FILES_WITH_MISSING_LICENSE=""

for file in $(files); do
	if ! grep -q "Apache License Version 2.0" "$file"; then
		FILES_WITH_MISSING_LICENSE="${FILES_WITH_MISSING_LICENSE}\n${file}"
	fi
done

if [ -z "$FILES_WITH_MISSING_LICENSE" ]; then
	echo "✅ All files include the license header"
	exit 0
else
	echo -e "🔥 Missing the license header in files: $FILES_WITH_MISSING_LICENSE"
	exit 1
fi
