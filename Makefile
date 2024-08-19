TAG_NAME := latest
IMAGE_NAME := todo-backend-dart:$(TAG_NAME)

build:
	docker build --platform=linux/amd64 -t $(IMAGE_NAME) .

run: build
	docker run -p 8080:8080 -it $(IMAGE_NAME)