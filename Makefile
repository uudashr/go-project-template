SOURCES := $(shell find . -name '*.go' -type f -not -path './vendor/*'  -not -path '*/mocks/*')

PACKAGE := $(shell go list)
GOOS := $(shell go env GOOS)
GOARCH = $(shell go env GOARCH)
OBJ_DIR := $(GOPATH)/pkg/$(GOOS)_$(GOARCH)/$(PACKAGE)

DOCKER_IMAGE := myproject

# Database
DB_USER ?= myproject
DB_PASSWORD ?= secret
DB_PORT ?= 3306
DB_ADDRESS ?= 127.0.0.1:${DB_PORT}
DB_NAME ?= myproject_test
DB_PING_MAX_RETRY ?= 30
DB_PING_RETRY_INTERVAL ?= 1s

# Dependencies Management
.PHONY: vendor-prepare
vendor-prepare:
	@echo "Installing dep"
	@go get -u -v github.com/golang/dep/cmd/dep

Gopkg.lock: Gopkg.toml
	@dep ensure -update $(DEP_OPTS)

.PHONY: vendor-update
vendor-update:
	@dep ensure -update $(DEP_OPTS)

vendor: Gopkg.lock
	@dep ensure $(DEP_OPTS)

.PHONY: vendor-optimize
vendor-optimize: vendor
	@dep prune

.PHONY: clean-vendor
clean-vendor:
	@rm -rf vendor

# Linter
.PHONY: lint-prepare
lint-prepare:
	@echo "Installing golangci-lint"
	@go get -u github.com/golangci/golangci-lint/cmd/golangci-lint

.PHONY: lint
lint: vendor
	@golangci-lint run \
		--exclude-use-default=false \
		--enable=golint \
		--enable=gocyclo \
		--enable=goconst \
		--enable=unconvert \
		--exclude='^Error return value of `.*\.Log` is not checked$$' \
		--exclude='^G104: Errors unhandled\.$$' \
		--exclude='^G304: Potential file inclusion via variable$$' \
		./...

# Mock
.PHONY: mockery-prepare
mockery-prepare:
	@echo "Installing mockery"
	@go get github.com/vektra/mockery/.../

# internal/mocks/AppInstallRepository.go: app_install.go
# 	@mockery -name=AppInstallRepository -output=internal/mocks

# internal/app/mocks/AppInstallService.go: internal/app/app_install.go
# 	@mockery -name=AppInstallService -dir=internal/app -output=internal/app/mocks

# Testing
.PHONY: test
test: vendor
	@go test -short $(TEST_OPTS) ./...

.PHONY: test-mysql
test-mysql: vendor
	@go test -v $(TEST_OPTS) ./internal/mysql -scripts=file://migrations -db-user $(DB_USER) -db-password $(DB_PASSWORD) -db-address $(DB_ADDRESS) -db-name $(DB_NAME) -db-ping-max-retry=$(DB_PING_MAX_RETRY) -db-ping-retry-interval=$(DB_PING_RETRY_INTERVAL)

# Database Migration
.PHONY: migrate-prepare
migrate-prepare:
	@go get -u -d github.com/mattes/migrate/cli github.com/go-sql-driver/mysql
	@go build -tags 'mysql' -o /usr/local/bin/migrate github.com/mattes/migrate/cli

.PHONY: migrate-up
migrate-up:
	@migrate -database "mysql://$(DB_USER):$(DB_PASSWORD)@tcp($(DB_ADDRESS))/$(DB_NAME)?multiStatements=true" -path=internal/mysql/migrations up

.PHONY: migrate-down
migrate-down:
	@migrate -database "mysql://$(DB_USER):$(DB_PASSWORD)@tcp($(DB_ADDRESS))/$(DB_NAME)?multiStatements=true" -path=internal/mysql/migrations down

.PHONY: migrate-drop
migrate-drop:
	@migrate -database "mysql://$(DB_USER):$(DB_PASSWORD)@tcp($(DB_ADDRESS))/$(DB_NAME)?multiStatements=true" -path=internal/mysql/migrations drop

# Upstream Services
.PHONY: docker-mysql-up
docker-mysql-up:
	@docker run --rm -d --name mysql -p ${DB_PORT}:3306 -e MYSQL_DATABASE=$(DB_NAME) -e MYSQL_USER=$(DB_USER) -e MYSQL_PASSWORD=$(DB_PASSWORD) -e MYSQL_ROOT_PASSWORD=rootsecret mysql:5 && docker logs -f mysql

.PHONY: docker-mysql-down
docker-mysql-down:
	@docker stop mysql

# Build and Installation
.PHONY: install
install: vendor
	@go install ./...

.PHONY: uninstall
uninstall:
	@echo "Removing binaries and libraries"
	@go clean -i ./...
	@if [ -d $(OBJ_DIR) ]; then \
		rm -rf $(OBJ_DIR); \
	fi

myproject-exec: cmd/$@ vendor $(SOURCES)
	@echo "Building $@"
	@CGO_ENABLED=0 go build -a -installsuffix cgo -o $@ cmd/$@/*.go

# Docker
.PHONY: docker
docker:
	@docker build -t $(DOCKER_IMAGE) .
