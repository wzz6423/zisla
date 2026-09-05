.PHONY: run stop update build-package sync-cask clean

LOCAL_SIGNING_ENV := SIGNING_MODE=dev

run:
	@$(LOCAL_SIGNING_ENV) mac/Scripts/dev-service.sh run

stop:
	@mac/Scripts/dev-service.sh stop

update:
	@$(LOCAL_SIGNING_ENV) mac/Scripts/dev-service.sh run

build-package:
	@mac/Scripts/build-package.sh

# VERSION is required. Add PUBLISH_TAP=true to push the cask to the Homebrew tap.
sync-cask:
	@mac/Scripts/sync-homebrew-cask.sh

clean: stop
	@rm -rf outputs .impeccable .playwright-cli \
		mac/dist mac/.build mac/.swiftpm mac/DerivedData mac/.release-* \
		web/dist web/.playwright web/screenshots
