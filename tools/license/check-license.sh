#!/bin/bash

if [ ! -f "Package.swift" ]; then
	echo "\`check-license.sh\` must be run in repository root folder: \`./tools/license/check-license.sh\`"; exit 1
fi

find . -type f \( -name "*.swift" ! -iname "Package.swift" \) -print0 | while IFS= read -r -d '' file; do
  if ! grep -q "Apache License Version 2.0" "$file"
  then
  	echo "No license in $file"
  	exit 1
  fi
done
