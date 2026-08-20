.PHONY: run stop update

LOCAL_SIGNING_ENV := SIGNING_MODE=dev

run:
	@$(LOCAL_SIGNING_ENV) mac/Scripts/dev-service.sh run

stop:
	@mac/Scripts/dev-service.sh stop

update:
	@$(LOCAL_SIGNING_ENV) mac/Scripts/dev-service.sh run
