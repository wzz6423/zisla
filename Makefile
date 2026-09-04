.PHONY: run stop update build-package clean

LOCAL_SIGNING_ENV := SIGNING_MODE=dev

run:
	@$(LOCAL_SIGNING_ENV) mac/Scripts/dev-service.sh run

stop:
	@mac/Scripts/dev-service.sh stop

update:
	@$(LOCAL_SIGNING_ENV) mac/Scripts/dev-service.sh run

build-package:
	@mac/Scripts/build-package.sh

clean: stop
	@rm -rf outputs .impeccable .playwright-cli \
		mac/dist mac/.build mac/.swiftpm mac/DerivedData mac/.release-* \
		web/dist web/.playwright web/screenshots
