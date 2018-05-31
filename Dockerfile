## Builder
FROM golang:1.10.2-alpine as builder

RUN apk update && apk upgrade && \
    apk --no-cache --update add git make && \
    go get -u github.com/golang/dep/cmd/dep

WORKDIR /go/src/github.com/uudashr/go-project-template
COPY . .
RUN DEP_OPTS="-v -vendor-only" make myproject-exec

## Distribution
FROM alpine:latest

RUN apk update && apk upgrade && \
    apk --no-cache --update add ca-certificates

WORKDIR /pushengine
COPY --from=builder /go/src/github.com/uudashr/go-project-template/myproject-exec .

CMD exec ./myproject-exec
