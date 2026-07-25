.PHONY: run stop update

run:
	@mac/Scripts/dev-service.sh run

stop:
	@mac/Scripts/dev-service.sh stop

update:
	@mac/Scripts/dev-service.sh run
