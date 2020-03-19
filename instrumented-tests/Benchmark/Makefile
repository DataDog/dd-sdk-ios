.PHONY : benchmark

benchmark:
		@echo "⚙️  Generating 'Datadog.xcodeproj'..."
		@cd ../.. && swift package generate-xcodeproj --output instrumented-tests/Benchmark --skip-extra-files 
		@echo "OK 👌"
