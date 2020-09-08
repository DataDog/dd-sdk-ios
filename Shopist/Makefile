all: setup

define ORG2_SECRETS
RUM_APPLICATION_ID=${RUM_APPLICATION_ID}\n
DATADOG_CLIENT_TOKEN=${DATADOG_CLIENT_TOKEN}\n
SHOPIST_BASE_URL=${SHOPIST_BASE_URL}\n
endef
export ORG2_SECRETS

define DEMO_SECRETS
RUM_APPLICATION_ID=${DEMO_RUM_APPLICATION_ID}\n
DATADOG_CLIENT_TOKEN=${DEMO_DATADOG_CLIENT_TOKEN}\n
SHOPIST_BASE_URL=${SHOPIST_BASE_URL}\n
endef
export DEMO_SECRETS

setup:
ifeq (${IS_DEMO}, true)
	@echo "Running demo scenarios..."
	@echo $$DEMO_SECRETS > ../xcconfigs/Shopist.local.xcconfig;
else
	@echo $$ORG2_SECRETS > ../xcconfigs/Shopist.local.xcconfig;
endif
