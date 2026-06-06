
KIND ?= kind
KUBECTL ?= kubectl
CILIUM_CLI ?= cilium
KIND_ATHENZ_CLUSTER ?= cilium-athenz
KIND_CILIUM_CLUSTER ?= cilium
KIND_CILIUM_NETWORK ?= kind-$(KIND_CILIUM_CLUSTER)
ATHENZ_CONTEXT ?= kind-$(KIND_ATHENZ_CLUSTER)
CILIUM_CONTEXT ?= kind-$(KIND_CILIUM_CLUSTER)
ATHENZ_CONTROL_PLANE ?= $(KIND_ATHENZ_CLUSTER)-control-plane
REAL_KUBECTL ?= $(shell command -v kubectl 2>/dev/null || printf '%s' kubectl)
ATHENZ_KUBECTL ?= $(KUBECTL) --context $(ATHENZ_CONTEXT)
CILIUM_KUBECTL ?= $(KUBECTL) --context $(CILIUM_CONTEXT)
CILIUM_CLUSTER_CLI ?= $(CILIUM_CLI) --context $(CILIUM_CONTEXT)
BENCH_RATE ?= 100
BENCH_WORKERS ?= 100
BENCH_DURATION ?= 30s
BENCH_KEEPALIVE ?= false

# Multi-cluster variables
KIND_CILIUM1_CLUSTER ?= cilium1
KIND_CILIUM2_CLUSTER ?= cilium2
KIND_MULTI_NETWORK ?= kind-cilium
CILIUM1_CONTEXT ?= kind-$(KIND_CILIUM1_CLUSTER)
CILIUM2_CONTEXT ?= kind-$(KIND_CILIUM2_CLUSTER)
CILIUM1_KUBECTL ?= $(KUBECTL) --context $(CILIUM1_CONTEXT)
CILIUM2_KUBECTL ?= $(KUBECTL) --context $(CILIUM2_CONTEXT)
CILIUM1_CLUSTER_CLI ?= $(CILIUM_CLI) --context $(CILIUM1_CONTEXT)
CILIUM2_CLUSTER_CLI ?= $(CILIUM_CLI) --context $(CILIUM2_CONTEXT)
CILIUM1_CONTROL_PLANE ?= $(KIND_CILIUM1_CLUSTER)-control-plane
CILIUM2_CONTROL_PLANE ?= $(KIND_CILIUM2_CLUSTER)-control-plane
MULTI1_CUSTOM_VALUES_FILE ?= cilium/contrib/testing/kind-custom-multi1.yaml
MULTI2_CUSTOM_VALUES_FILE ?= cilium/contrib/testing/kind-custom-multi2.yaml
ENABLE_KVSTOREMESH ?= true
KUBECTL_CONTEXT_WRAPPER_DIR := $(abspath hack/bin/kubectl-context)
ATHENZ_KUBECTL_ENV := PATH="$(KUBECTL_CONTEXT_WRAPPER_DIR):$$PATH" REAL_KUBECTL="$(REAL_KUBECTL)" KUBECTL_CONTEXT="$(ATHENZ_CONTEXT)"
ATHENZ_REPO_URL ?= https://github.com/AthenZ/athenz.git
ATHENZ_GIT_REF ?= 

patch:
	rsync -av --exclude=".gitkeep" patchfiles/cilium/* cilium
	rsync -av --exclude=".gitkeep" patchfiles/athenz-distribution/* athenz-distribution

.PHONY: patch kind-setup kind-prepare-identityprovider kind-delete deploy-athenz clean-athenz prepare-cilium-athenz deploy-cilium clean-cilium deploy-identityprovider clean-identityprovider deploy-test-workload clean-test-workload deploy-benchmark-workload run-benchmark clean-benchmark-workload

kind-setup:
	$(KIND) create cluster --name $(KIND_ATHENZ_CLUSTER)
	CLUSTER_NAME=$(KIND_CILIUM_CLUSTER) $(MAKE) -C cilium kind
	$(MAKE) kind-prepare-identityprovider

kind-prepare-identityprovider:
	@docker network inspect "$(KIND_CILIUM_NETWORK)" >/dev/null 2>&1 || { echo "missing cilium kind docker network: $(KIND_CILIUM_NETWORK)"; exit 1; }
	@for node in $$($(KIND) get nodes --name "$(KIND_ATHENZ_CLUSTER)"); do \
		echo "tune inotify on $$node"; \
		docker exec "$$node" sysctl -w fs.inotify.max_user_watches=1048576 >/dev/null; \
		docker exec "$$node" sysctl -w fs.inotify.max_user_instances=512 >/dev/null; \
		if docker inspect "$$node" --format '{{json .NetworkSettings.Networks}}' | grep -q '"$(KIND_CILIUM_NETWORK)"'; then \
			echo "$$node already attached to $(KIND_CILIUM_NETWORK)"; \
		else \
			echo "attach $$node to $(KIND_CILIUM_NETWORK)"; \
			docker network connect "$(KIND_CILIUM_NETWORK)" "$$node"; \
		fi; \
	done

kind-delete:
	$(KIND) delete cluster --name $(KIND_ATHENZ_CLUSTER)
	$(KIND) delete cluster --name $(KIND_CILIUM_CLUSTER)

deploy-athenz: 
	$(ATHENZ_KUBECTL_ENV) $(MAKE) -C athenz-distribution clean-kubernetes-athenz
	@if [ -n "$(ATHENZ_GIT_REF)" ] || [ "$(ATHENZ_REPO_URL)" != "https://github.com/AthenZ/athenz.git" ]; then \
		$(ATHENZ_KUBECTL_ENV) $(MAKE) -C athenz-distribution load-docker-images; \
		$(ATHENZ_KUBECTL_ENV) $(MAKE) -C athenz-distribution build-athenz-zms-server build-athenz-zts-server; \
		$(ATHENZ_KUBECTL_ENV) $(MAKE) -C athenz-distribution load-kubernetes-images KIND_CLUSTER_NAME=$(KIND_ATHENZ_CLUSTER); \
	fi
	$(ATHENZ_KUBECTL_ENV) $(MAKE) -C athenz-distribution deploy-kubernetes-athenz KIND_CLUSTER_NAME=$(KIND_ATHENZ_CLUSTER)

clean-athenz:
	$(ATHENZ_KUBECTL_ENV) $(MAKE) -C athenz-distribution clean-kubernetes-athenz

prepare-cilium-athenz:
	@athenz_ip="$$(docker inspect "$(ATHENZ_CONTROL_PLANE)" --format '{{with index .NetworkSettings.Networks "$(KIND_CILIUM_NETWORK)"}}{{.IPAddress}}{{end}}')"; \
	test -n "$$athenz_ip" || { echo "failed to determine IP for $(ATHENZ_CONTROL_PLANE) on $(KIND_CILIUM_NETWORK)"; exit 1; }; \
	$(MAKE) -C athenz-cilium sync-cilium-athenz-cacert sync-kind-athenz-hostaliases setup-athenz-cilium-services \
		ATHENZ_CONTEXT=$(ATHENZ_CONTEXT) \
		CILIUM_CONTEXT=$(CILIUM_CONTEXT) \
		ATHENZ_ENDPOINT_IP="$$athenz_ip"

deploy-cilium: prepare-cilium-athenz
	kind load docker-image quay.io/cilium/cilium-envoy:v1.35.9-1773656288-7b052e66eb2cfc5ac130ce0a5be66202a10d83be --name cilium

	$(MAKE) -C cilium kind-image KIND_CLUSTER_NAME=$(KIND_CILIUM_CLUSTER)
	$(MAKE) -C cilium kind-install-cilium KIND_CLUSTER_NAME=$(KIND_CILIUM_CLUSTER) CILIUM_CLI="$(CILIUM_CLUSTER_CLI)"
	$(CILIUM_CLUSTER_CLI) config set debug true

clean-cilium:
	$(MAKE) -C cilium kind-uninstall-cilium KIND_CLUSTER_NAME=$(KIND_CILIUM_CLUSTER) CILIUM_CLI="$(CILIUM_CLUSTER_CLI)"

deploy-identityprovider:
	$(MAKE) -C athenz-identityprovider build-athenz-identityprovider ATHENZ_CONTEXT=$(ATHENZ_CONTEXT) CILIUM_CONTEXT=$(CILIUM_CONTEXT)

cleanup-identityprovider:
	$(MAKE) -C athenz-identityprovider clean-athenz-identityprovider ATHENZ_CONTEXT=$(ATHENZ_CONTEXT) CILIUM_CONTEXT=$(CILIUM_CONTEXT)

deploy-test-workload:
	$(MAKE) -C athenz-cilium deploy-test-workload \
		ATHENZ_CONTEXT=$(ATHENZ_CONTEXT) \
		CILIUM_CONTEXT=$(CILIUM_CONTEXT)

clean-test-workload:
	$(MAKE) -C athenz-cilium clean-test-workload \
		ATHENZ_CONTEXT=$(ATHENZ_CONTEXT) \
		CILIUM_CONTEXT=$(CILIUM_CONTEXT)

deploy-benchmark-workload:
	$(MAKE) -C athenz-cilium deploy-benchmark-workload \
		ATHENZ_CONTEXT=$(ATHENZ_CONTEXT) \
		CILIUM_CONTEXT=$(CILIUM_CONTEXT)

run-benchmark:
	$(MAKE) -C athenz-cilium run-benchmark \
		ATHENZ_CONTEXT=$(ATHENZ_CONTEXT) \
		CILIUM_CONTEXT=$(CILIUM_CONTEXT) \
		BENCH_RATE="$(BENCH_RATE)" \
		BENCH_WORKERS="$(BENCH_WORKERS)" \
		BENCH_DURATION="$(BENCH_DURATION)" \
		BENCH_KEEPALIVE="$(BENCH_KEEPALIVE)"

clean-benchmark-workload:
	$(MAKE) -C athenz-cilium clean-benchmark-workload \
		ATHENZ_CONTEXT=$(ATHENZ_CONTEXT) \
		CILIUM_CONTEXT=$(CILIUM_CONTEXT)

kind-cleanup:
	$(KIND) delete cluster --name $(KIND_ATHENZ_CLUSTER)
	$(KIND) delete cluster --name $(KIND_CILIUM_CLUSTER)

# ==============================================================================
# Multi-cluster targets
# ==============================================================================

.PHONY: multi-kind-setup multi-kind-prepare-networking multi-deploy-athenz multi-deploy-identityprovider multi-prepare-cilium-athenz multi-deploy-cilium multi-deploy-test-workload multi-clean-test-workload multi-kind-delete

multi-kind-setup:
	$(KIND) create cluster --name $(KIND_ATHENZ_CLUSTER)
	CLUSTER_NAME=$(KIND_CILIUM1_CLUSTER) PODSUBNET=10.1.0.0/16 SERVICESUBNET=172.20.1.0/24 \
		$(MAKE) -C cilium kind
	CLUSTER_NAME=$(KIND_CILIUM2_CLUSTER) PODSUBNET=10.2.0.0/16 SERVICESUBNET=172.20.2.0/24 \
		AGENTPORTPREFIX=236 OPERATORPORTPREFIX=237 \
		$(MAKE) -C cilium kind
	$(MAKE) multi-kind-prepare-networking

multi-kind-prepare-networking:
	@docker network inspect "$(KIND_MULTI_NETWORK)" >/dev/null 2>&1 || { echo "missing docker network: $(KIND_MULTI_NETWORK)"; exit 1; }
	@for node in $$($(KIND) get nodes --name "$(KIND_ATHENZ_CLUSTER)"); do \
		docker exec "$$node" sysctl -w fs.inotify.max_user_watches=1048576 >/dev/null; \
		docker exec "$$node" sysctl -w fs.inotify.max_user_instances=512 >/dev/null; \
		if docker inspect "$$node" --format '{{json .NetworkSettings.Networks}}' | grep -q '"$(KIND_MULTI_NETWORK)"'; then \
			echo "$$node already attached to $(KIND_MULTI_NETWORK)"; \
		else \
			echo "attach $$node to $(KIND_MULTI_NETWORK)"; \
			docker network connect "$(KIND_MULTI_NETWORK)" "$$node"; \
		fi; \
	done

multi-deploy-athenz: deploy-athenz

multi-deploy-identityprovider:
	$(MAKE) -C athenz-identityprovider build-athenz-identityprovider \
		ATHENZ_CONTEXT=$(ATHENZ_CONTEXT) \
		CILIUM_CONTEXT=$(CILIUM1_CONTEXT) \
		CILIUM_KIND_CLUSTER_NAME=$(KIND_CILIUM1_CLUSTER)
	$(MAKE) -C athenz-identityprovider deploy-cilium-rbac \
		CILIUM_CONTEXT=$(CILIUM2_CONTEXT) \
		CILIUM_KUBECTL="$(KUBECTL) --context $(CILIUM2_CONTEXT)"
	$(MAKE) multi-deploy-identityprovider2

multi-deploy-identityprovider2:
	$(MAKE) -C athenz-identityprovider build-athenz-identityprovider \
		ATHENZ_CONTEXT=$(ATHENZ_CONTEXT) \
		CILIUM_CONTEXT=$(CILIUM2_CONTEXT) \
		CILIUM_KIND_CLUSTER_NAME=$(KIND_CILIUM2_CLUSTER) \
		KUSTOMIZE_DIR=kustomize-multi2 \
		CILIUM_RBAC_DIR=cilium2 \
		CILIUM_SECRET_NAME=identityprovider2-remote-cluster \
		PRIVATE_KEY_FILE=private2.key.pem \
		SERVICE_CERT_FILE=service2.cert.pem \
		TLS_SECRET_MANIFEST=kustomize-multi2/secret.yaml \
		IDENTITYPROVIDER_DEPLOYMENT=identityprovider2-deployment \
		IDENTITYPROVIDER_JWT_SECRET=identityprovider2-jwt

multi-prepare-cilium-athenz:
	@athenz_ip="$$(docker inspect "$(ATHENZ_CONTROL_PLANE)" --format '{{with index .NetworkSettings.Networks "$(KIND_MULTI_NETWORK)"}}{{.IPAddress}}{{end}}')"; \
	test -n "$$athenz_ip" || { echo "failed to get Athenz IP on $(KIND_MULTI_NETWORK)"; exit 1; }; \
	$(MAKE) -C athenz-cilium sync-cilium-athenz-cacert sync-kind-athenz-hostaliases setup-athenz-cilium-services \
		ATHENZ_CONTEXT=$(ATHENZ_CONTEXT) \
		CILIUM_CONTEXT=$(CILIUM1_CONTEXT) \
		ATHENZ_ENDPOINT_IP="$$athenz_ip" \
		KIND_CUSTOM_VALUES_FILE=../$(MULTI1_CUSTOM_VALUES_FILE)
	@athenz_ip="$$(docker inspect "$(ATHENZ_CONTROL_PLANE)" --format '{{with index .NetworkSettings.Networks "$(KIND_MULTI_NETWORK)"}}{{.IPAddress}}{{end}}')"; \
	test -n "$$athenz_ip" || { echo "failed to get Athenz IP on $(KIND_MULTI_NETWORK)"; exit 1; }; \
	$(MAKE) -C athenz-cilium sync-cilium-athenz-cacert sync-kind-athenz-hostaliases setup-athenz-cilium-services \
		ATHENZ_CONTEXT=$(ATHENZ_CONTEXT) \
		CILIUM_CONTEXT=$(CILIUM2_CONTEXT) \
		ATHENZ_ENDPOINT_IP="$$athenz_ip" \
		KIND_CUSTOM_VALUES_FILE=../$(MULTI2_CUSTOM_VALUES_FILE) \
		REGISTER_PROVIDER_SERVICE=cilium.identityprovider2

multi-deploy-cilium: multi-prepare-cilium-athenz
	kind load docker-image quay.io/cilium/cilium-envoy:v1.35.9-1773656288-7b052e66eb2cfc5ac130ce0a5be66202a10d83be --name $(KIND_CILIUM1_CLUSTER)
	kind load docker-image quay.io/cilium/cilium-envoy:v1.35.9-1773656288-7b052e66eb2cfc5ac130ce0a5be66202a10d83be --name $(KIND_CILIUM2_CLUSTER)
	kind load docker-image quay.io/cilium/clustermesh-apiserver:v1.19.2 --name $(KIND_CILIUM1_CLUSTER)
	kind load docker-image quay.io/cilium/clustermesh-apiserver:v1.19.2 --name $(KIND_CILIUM2_CLUSTER)
	$(MAKE) -C cilium kind-image KIND_CLUSTER_NAME=$(KIND_CILIUM1_CLUSTER)
	$(MAKE) -C cilium kind-image KIND_CLUSTER_NAME=$(KIND_CILIUM2_CLUSTER)
	@echo "  INSTALL cilium on $(KIND_CILIUM1_CLUSTER)"
	-@$(CILIUM1_CLUSTER_CLI) uninstall >/dev/null 2>&1 || true
	$(CILIUM1_CLUSTER_CLI) install \
		--chart-directory=cilium/install/kubernetes/cilium \
		--helm-values=cilium/contrib/testing/kind-common.yaml \
		--helm-values=cilium/contrib/testing/kind-values.yaml \
		--helm-values=$(MULTI1_CUSTOM_VALUES_FILE) \
		--version=
	@echo "  SHARE cilium-ca from $(KIND_CILIUM1_CLUSTER) to $(KIND_CILIUM2_CLUSTER)"
	$(CILIUM1_KUBECTL) get secret -n kube-system cilium-ca -o yaml | \
		$(CILIUM2_KUBECTL) replace --force -f -
	@echo "  INSTALL cilium on $(KIND_CILIUM2_CLUSTER)"
	-@$(CILIUM2_CLUSTER_CLI) uninstall >/dev/null 2>&1 || true
	$(CILIUM2_CLUSTER_CLI) install \
		--chart-directory=cilium/install/kubernetes/cilium \
		--helm-values=cilium/contrib/testing/kind-common.yaml \
		--helm-values=cilium/contrib/testing/kind-values.yaml \
		--helm-values=$(MULTI2_CUSTOM_VALUES_FILE) \
		--version=
	@echo "  CONNECT ClusterMesh"
	$(CILIUM_CLI) clustermesh connect --context $(CILIUM1_CONTEXT) --destination-context $(CILIUM2_CONTEXT)
	$(CILIUM1_CLUSTER_CLI) clustermesh status --wait
	$(CILIUM2_CLUSTER_CLI) clustermesh status --wait
	$(CILIUM1_CLUSTER_CLI) config set debug true
	$(CILIUM2_CLUSTER_CLI) config set debug true

multi-deploy-test-workload:
	$(MAKE) -C athenz-cilium load-test-workload-image CILIUM_KIND_CLUSTER=$(KIND_CILIUM1_CLUSTER) CILIUM_CONTEXT=$(CILIUM1_CONTEXT)
	$(MAKE) -C athenz-cilium load-test-workload-image CILIUM_KIND_CLUSTER=$(KIND_CILIUM2_CLUSTER) CILIUM_CONTEXT=$(CILIUM2_CONTEXT)
	$(CILIUM2_KUBECTL) apply -f athenz-cilium/manifests/multi-cluster-echo.yaml
	$(CILIUM1_KUBECTL) apply -f athenz-cilium/manifests/multi-cluster-client.yaml
	$(CILIUM2_KUBECTL) -n default wait --for=condition=Ready pod/echo --timeout=180s
	$(CILIUM1_KUBECTL) -n default wait --for=condition=Ready pod/pod-worker --timeout=180s
	$(MAKE) -C athenz-cilium configure-multi-cluster-test-athenz-policy \
		ATHENZ_CONTEXT=$(ATHENZ_CONTEXT) \
		CILIUM1_CONTEXT=$(CILIUM1_CONTEXT) \
		CILIUM2_CONTEXT=$(CILIUM2_CONTEXT)

multi-clean-test-workload:
	$(CILIUM2_KUBECTL) delete -f athenz-cilium/manifests/multi-cluster-echo.yaml --ignore-not-found
	$(CILIUM1_KUBECTL) delete -f athenz-cilium/manifests/multi-cluster-client.yaml --ignore-not-found

multi-deploy-benchmark-workload:
	$(MAKE) -C athenz-cilium load-benchmark-workload-images CILIUM_KIND_CLUSTER=$(KIND_CILIUM1_CLUSTER) CILIUM_CONTEXT=$(CILIUM1_CONTEXT)
	$(MAKE) -C athenz-cilium load-benchmark-workload-images CILIUM_KIND_CLUSTER=$(KIND_CILIUM2_CLUSTER) CILIUM_CONTEXT=$(CILIUM2_CONTEXT)
	$(CILIUM2_KUBECTL) apply -f athenz-cilium/manifests/multi-cluster-benchmark-echo.yaml
	$(CILIUM1_KUBECTL) apply -f athenz-cilium/manifests/multi-cluster-benchmark-client.yaml
	$(CILIUM2_KUBECTL) -n default wait --for=condition=Ready pod/echo-plain pod/echo-auth --timeout=180s
	$(CILIUM1_KUBECTL) -n default rollout status deployment/vegeta --timeout=180s
	$(MAKE) -C athenz-cilium configure-multi-cluster-benchmark-athenz-policy \
		ATHENZ_CONTEXT=$(ATHENZ_CONTEXT) \
		CILIUM1_CONTEXT=$(CILIUM1_CONTEXT) \
		CILIUM2_CONTEXT=$(CILIUM2_CONTEXT)

multi-run-benchmark:
	@printf '\n===== multi-cluster benchmark: plain =====\n'; \
	vegeta_pod="$$( $(CILIUM1_KUBECTL) -n default get pod -l app=vegeta -o jsonpath='{.items[0].metadata.name}' )"; \
	$(CILIUM1_KUBECTL) -n default exec "$$vegeta_pod" -- /bin/sh -c \
		"echo 'GET http://echo-plain:3000/headers' \
		| vegeta attack -workers=$(BENCH_WORKERS) -rate=$(BENCH_RATE) -duration=$(BENCH_DURATION) -keepalive $(BENCH_KEEPALIVE) \
		| tee /data/plain.bin | vegeta report"; \
	printf '\n===== multi-cluster benchmark: auth =====\n'; \
	$(CILIUM1_KUBECTL) -n default exec "$$vegeta_pod" -- /bin/sh -c \
		"echo 'GET http://echo-auth:3000/headers' \
		| vegeta attack -workers=$(BENCH_WORKERS) -rate=$(BENCH_RATE) -duration=$(BENCH_DURATION) -keepalive $(BENCH_KEEPALIVE) \
		| tee /data/auth.bin | vegeta report"

multi-clean-benchmark-workload:
	$(CILIUM2_KUBECTL) delete -f athenz-cilium/manifests/multi-cluster-benchmark-echo.yaml --ignore-not-found
	$(CILIUM1_KUBECTL) delete -f athenz-cilium/manifests/multi-cluster-benchmark-client.yaml --ignore-not-found

multi-kind-delete:
	$(KIND) delete cluster --name $(KIND_ATHENZ_CLUSTER)
	$(KIND) delete cluster --name $(KIND_CILIUM1_CLUSTER)
	$(KIND) delete cluster --name $(KIND_CILIUM2_CLUSTER)
