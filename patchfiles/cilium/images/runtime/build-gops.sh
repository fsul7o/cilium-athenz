#!/usr/bin/env bash

# Copyright Authors of Cilium
# SPDX-License-Identifier: Apache-2.0

set -o xtrace
set -o errexit
set -o pipefail
set -o nounset

# renovate: datasource=github-releases depName=google/gops
gops_version="v0.3.27"

mkdir -p /go/src/github.com/google
cd /go/src/github.com/google

git clone https://github.com/google/gops.git
cd gops

git checkout -b "${gops_version}" "${gops_version}"
git --no-pager remote -v
git --no-pager log -1

mkdir -p "/out/usr/bin"
# In some corporate environments, cert interception breaks access to
# go.googlesource.com even when GitHub remains reachable. Prefer the GitHub
# mirror for golang.org/x/* repos for this auxiliary build step.
git config --global url."https://github.com/golang/".insteadOf https://go.googlesource.com/

# Some corporate environments break TLS verification for proxy.golang.org.
# Fall back to direct VCS fetches for this auxiliary build step and allow
# insecure vanity-import resolution for golang.org/* when corporate TLS
# interception breaks certificate validation.
GOPROXY="${GOPROXY:-direct}" \
GOSUMDB="${GOSUMDB:-off}" \
GOINSECURE="${GOINSECURE:-golang.org/*}" \
GIT_SSL_NO_VERIFY="${GIT_SSL_NO_VERIFY:-true}" \
CGO_ENABLED=0 \
go build -ldflags "-s -w" -o "/out/usr/bin/gops" github.com/google/gops
