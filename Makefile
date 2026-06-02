
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
