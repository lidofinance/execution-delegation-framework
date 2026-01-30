DEV_CONTAINER_NAME = delegation-dev-container
DEV_IMAGE = lidofinance/delegation-execution-authority:dev
DEV_WORKDIR = /app
EXEC_CMD = docker exec -w $(DEV_WORKDIR) $(DEV_CONTAINER_NAME)
EXEC_CMD_INTERACTIVE = docker exec -w $(DEV_WORKDIR) -it $(DEV_CONTAINER_NAME)

up:
	@if [ -z "$$(docker ps -q -f name=$(DEV_CONTAINER_NAME))" ]; then \
		echo "No container found, starting..."; \
		docker build --platform linux/amd64 --target development -t $(DEV_IMAGE) .; \
		docker run --platform linux/amd64 -dit --env-file .env --name $(DEV_CONTAINER_NAME) -v $$(pwd):$(DEV_WORKDIR) $(DEV_IMAGE) sleep infinity; \
	else \
		echo "Container $(DEV_CONTAINER_NAME) already running"; \
	fi

rebuild:
	@echo "Rebuilding dev image and container..."
	@if [ -n "$$(docker ps -q -f name=$(DEV_CONTAINER_NAME))" ]; then \
		echo "Stopping and removing existing container..."; \
		docker stop $(DEV_CONTAINER_NAME) && docker rm $(DEV_CONTAINER_NAME); \
	elif [ -n "$$(docker ps -aq -f name=$(DEV_CONTAINER_NAME))" ]; then \
		echo "Removing stopped container..."; \
		docker rm $(DEV_CONTAINER_NAME); \
	fi
	docker build --platform linux/amd64 --no-cache --target development -t $(DEV_IMAGE) .
	$(MAKE) up

sh: up
	$(EXEC_CMD_INTERACTIVE) bash

ipython: up
	$(EXEC_CMD_INTERACTIVE) uv run ipython

uv-lock: up
	$(EXEC_CMD) uv lock --no-upgrade

compile: up
	$(EXEC_CMD) uv run ape compile

.PHONY: up rebuild down sh ipython uv-lock compile
