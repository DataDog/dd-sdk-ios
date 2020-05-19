#!/bin/bash

mv fastlaneOutput/$FL_PLATFORM/$FL_LANE/report.* fastlaneOutput
mv fastlaneOutput/$FL_PLATFORM/$FL_LANE/results/1_Test/Diagnostics fastlaneOutput

export ATTACHMENTS=fastlaneOutput/$FL_PLATFORM/$FL_LANE/results/Attachments
if [ -d "$ATTACHMENTS" ]; then
  mv $ATTACHMENTS fastlaneOutput
fi

mv ~/Library/Logs/scan fastlaneOutput
mv fastlaneOutput/$FL_PLATFORM/$FL_LANE ~/trash
