FROM docker.io/library/golang:1-alpine AS builder
ARG VERSION=

RUN set -eux \
    && apk --no-cache add --virtual build-dependencies cmake g++ make unzip curl git

WORKDIR ${GOPATH}/src/github.com/AthenZ/athenz

COPY athenz/ ./

ARG VERSION
ARG TARGETPLATFORM
ARG BUILDPLATFORM

RUN case ${TARGETPLATFORM} in \
         "linux/amd64")  \
            GOARCH=amd64 go install ./utils/athenz-conf \
            && GOARCH=amd64 go install ./utils/zms-cli \
            && GOARCH=amd64 go install ./utils/zms-authhistory \
            && GOARCH=amd64 go install ./utils/zms-domainattrs \
            && GOARCH=amd64 go install ./utils/zts-idtoken \
            && GOARCH=amd64 go install ./utils/zms-svctoken \
            && GOARCH=amd64 go install ./utils/zpe-updater/cmd/tools \
            && GOARCH=amd64 go install ./utils/zts-accesstoken \
            && GOARCH=amd64 go install ./utils/zts-rolecert \
            && GOARCH=amd64 go install ./utils/zts-roletoken \
            && GOARCH=amd64 go install ./utils/zts-usercert \
            && GOARCH=amd64 go install ./utils/zts-svccert \
              ;; \
         "linux/arm64" | "linux/arm64/v8")  \
            GOARCH=arm64 go install ./utils/athenz-conf \
            && GOARCH=arm64 go install ./utils/zms-cli \
            && GOARCH=arm64 go install ./utils/zms-authhistory \
            && GOARCH=arm64 go install ./utils/zms-domainattrs \
            && GOARCH=arm64 go install ./utils/zts-idtoken \
            && GOARCH=arm64 go install ./utils/zms-svctoken \
            && GOARCH=arm64 go install ./utils/zpe-updater/cmd/tools \
            && GOARCH=arm64 go install ./utils/zts-accesstoken \
            && GOARCH=arm64 go install ./utils/zts-rolecert \
            && GOARCH=arm64 go install ./utils/zts-roletoken \
            && GOARCH=arm64 go install ./utils/zts-usercert \
            && GOARCH=arm64 go install ./utils/zts-svccert \
              ;; \
         "linux/arm/v7")  \
            GOARCH=arm GOARM=7 go install ./utils/athenz-conf \
            && GOARCH=arm GOARM=7 go install ./utils/zms-cli \
            && GOARCH=arm GOARM=7 go install ./utils/zms-authhistory \
            && GOARCH=arm GOARM=7 go install ./utils/zms-domainattrs \
            && GOARCH=arm GOARM=7 go install ./utils/zts-idtoken \
            && GOARCH=arm GOARM=7 go install ./utils/zms-svctoken \
            && GOARCH=arm GOARM=7 go install ./utils/zpe-updater/cmd/tools \
            && GOARCH=arm GOARM=7 go install ./utils/zts-accesstoken \
            && GOARCH=arm GOARM=7 go install ./utils/zts-rolecert \
            && GOARCH=arm GOARM=7 go install ./utils/zts-roletoken \
            && GOARCH=arm GOARM=7 go install ./utils/zts-usercert \
            && GOARCH=arm GOARM=7 go install ./utils/zts-svccert \
             ;; \
    esac

RUN go install github.com/smallstep/cli/cmd/step@latest

RUN apk del build-dependencies

RUN set -eux && apk update && apk add --no-cache --update tini

FROM docker.io/library/alpine:3

ARG VERSION
# date -u +'%Y-%m-%dT%H:%M:%SZ'
ARG BUILD_DATE
# git rev-parse --short HEAD
ARG VCS_REF

ENV VERSION=$VERSION
ENV BUILD_DATE=$BUILD_DATE
ENV VCS_REF=$VCS_REF

LABEL org.opencontainers.image.version=$VERSION
LABEL org.opencontainers.image.revision=$VCS_REF
LABEL org.opencontainers.image.created=$BUILD_DATE
LABEL org.opencontainers.image.title="Athenz CLI"
LABEL org.opencontainers.image.authors="ctyano <ctyano@duck.com>"
LABEL org.opencontainers.image.vendor="ctyano <ctyano@duck.com>"
LABEL org.opencontainers.image.licenses="GPL-3.0 license"
LABEL org.opencontainers.image.url="ghcr.io/ctyano/athenz-cli"
LABEL org.opencontainers.image.documentation="https://www.athenz.io/"
LABEL org.opencontainers.image.source="https://github.com/ctyano/athenz-distribution"

ENV APP_NAME='athenz'

COPY --from=builder /sbin/tini /sbin/tini

COPY --from=builder /go/bin/athenz-conf /usr/bin/athenz-conf
COPY --from=builder /go/bin/zms-cli /usr/bin/zms-cli
COPY --from=builder /go/bin/zms-authhistory /usr/bin/zms-authhistory
COPY --from=builder /go/bin/zms-domainattrs /usr/bin/zms-domainattrs
COPY --from=builder /go/bin/zts-idtoken /usr/bin/zts-idtoken
COPY --from=builder /go/bin/zms-svctoken /usr/bin/zms-svctoken
COPY --from=builder /go/bin/tools /usr/bin/zpu
COPY --from=builder /go/bin/zts-accesstoken /usr/bin/zts-accesstoken
COPY --from=builder /go/bin/zts-rolecert /usr/bin/zts-rolecert
COPY --from=builder /go/bin/zts-roletoken /usr/bin/zts-roletoken
COPY --from=builder /go/bin/zts-usercert /usr/bin/zts-usercert
COPY --from=builder /go/bin/zts-svccert /usr/bin/zts-svccert

COPY --from=builder /go/bin/step /usr/bin/step

RUN set -eux \
    && apk --no-cache add curl openssl tzdata tree netcat-openbsd jq yq dasel

RUN cp /usr/share/zoneinfo/Japan /etc/localtime

ARG GID=1001
ARG UID=10001

RUN addgroup -g ${GID} ${APP_NAME} && \
  adduser -S -D -H -s /sbin/nologin -u ${UID} -G ${APP_NAME} ${APP_NAME}
USER ${APP_NAME}:${APP_NAME}
WORKDIR /home/athenz

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/usr/bin/tail", "-f", "/dev/null"]
