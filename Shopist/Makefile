all: secret

LOCAL_XCCONFIG="./Shopist/shopist-secrets.local.xcconfig" 
ifeq ($(secret),)
	secret="my-secret-token"
endif

secret:
ifeq (,$(wildcard ./Shopist/shopist-secrets.local.xcconfig))
	@echo "Creating shopist-secrets.local.xcconfig..." ;
	@echo DATADOG_CLIENT_TOKEN="$(secret)" >> $(LOCAL_XCCONFIG)
	@echo "🔑 Your token is set: $(secret)"
	@echo "🛠  You can change it in $(LOCAL_XCCONFIG)"
endif
	@echo "All good 👌"
