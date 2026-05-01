
KIND ?= kind
KUBECTL ?= kubectl
CILIUM_CLI ?= cilium
KIND_LOCAL_CLUSTER ?= cilium-athenz
KIND_REMOTE_CLUSTER ?= cilium
KIND_REMOTE_NETWORK ?= kind-$(KIND_REMOTE_CLUSTER)
ATHENZ_LOCAL_CONTEXT ?= kind-$(KIND_LOCAL_CLUSTER)
CILIUM_REMOTE_CONTEXT ?= kind-$(KIND_REMOTE_CLUSTER)
ATHENZ_CONTROL_PLANE ?= $(KIND_LOCAL_CLUSTER)-control-plane
REAL_KUBECTL ?= $(shell command -v kubectl 2>/dev/null || printf '%s' kubectl)
LOCAL_KUBECTL ?= $(KUBECTL) --context $(ATHENZ_LOCAL_CONTEXT)
REMOTE_KUBECTL ?= $(KUBECTL) --context $(CILIUM_REMOTE_CONTEXT)
REMOTE_CILIUM_CLI ?= $(CILIUM_CLI) --context $(CILIUM_REMOTE_CONTEXT)
KUBECTL_CONTEXT_WRAPPER_DIR := $(abspath hack/bin/kubectl-context)
LOCAL_KUBECTL_ENV := PATH="$(KUBECTL_CONTEXT_WRAPPER_DIR):$$PATH" REAL_KUBECTL="$(REAL_KUBECTL)" KUBECTL_CONTEXT="$(ATHENZ_LOCAL_CONTEXT)"
ATHENZ_REPO_URL ?= https://github.com/fsul7o/athenz.git
ATHENZ_GIT_REF ?= master

patch:
	rsync -av --exclude=".gitkeep" patchfiles/cilium/* cilium
	rsync -av --exclude=".gitkeep" patchfiles/athenz-distribution/* athenz-distribution

.PHONY: patch kind-setup kind-prepare-identityprovider kind-delete deploy-athenz clean-athenz prepare-cilium-athenz deploy-cilium clean-cilium deploy-identityprovider clean-identityprovider

kind-setup:
	$(KIND) create cluster --name $(KIND_LOCAL_CLUSTER)
	CLUSTER_NAME=$(KIND_REMOTE_CLUSTER) $(MAKE) -C cilium kind
	$(MAKE) kind-prepare-identityprovider

kind-prepare-identityprovider:
	@docker network inspect "$(KIND_REMOTE_NETWORK)" >/dev/null 2>&1 || { echo "missing remote kind docker network: $(KIND_REMOTE_NETWORK)"; exit 1; }
	@for node in $$($(KIND) get nodes --name "$(KIND_LOCAL_CLUSTER)"); do \
		echo "tune inotify on $$node"; \
		docker exec "$$node" sysctl -w fs.inotify.max_user_watches=1048576 >/dev/null; \
		docker exec "$$node" sysctl -w fs.inotify.max_user_instances=512 >/dev/null; \
		if docker inspect "$$node" --format '{{json .NetworkSettings.Networks}}' | grep -q '"$(KIND_REMOTE_NETWORK)"'; then \
			echo "$$node already attached to $(KIND_REMOTE_NETWORK)"; \
		else \
			echo "attach $$node to $(KIND_REMOTE_NETWORK)"; \
			docker network connect "$(KIND_REMOTE_NETWORK)" "$$node"; \
		fi; \
	done

kind-delete:
	$(KIND) delete cluster --name $(KIND_LOCAL_CLUSTER)
	$(KIND) delete cluster --name $(KIND_REMOTE_CLUSTER)

deploy-athenz: 
	$(LOCAL_KUBECTL_ENV) $(MAKE) -C athenz-distribution clean-kubernetes-athenz
	@if [ -n "$(ATHENZ_GIT_REF)" ] || [ "$(ATHENZ_REPO_URL)" != "https://github.com/AthenZ/athenz.git" ]; then \
		$(LOCAL_KUBECTL_ENV) $(MAKE) -C athenz-distribution load-docker-images; \
		$(LOCAL_KUBECTL_ENV) $(MAKE) -C athenz-distribution buildx-athenz-zms-server buildx-athenz-zts-server; \
		$(LOCAL_KUBECTL_ENV) $(MAKE) -C athenz-distribution load-kubernetes-images KIND_CLUSTER_NAME=$(KIND_LOCAL_CLUSTER); \
	fi
	$(LOCAL_KUBECTL_ENV) $(MAKE) -C athenz-distribution deploy-kubernetes-athenz KIND_CLUSTER_NAME=$(KIND_LOCAL_CLUSTER)

clean-athenz:
	$(LOCAL_KUBECTL_ENV) $(MAKE) -C athenz-distribution clean-kubernetes-athenz

prepare-cilium-athenz:
	@athenz_ip="$$(docker inspect "$(ATHENZ_CONTROL_PLANE)" --format '{{with index .NetworkSettings.Networks "$(KIND_REMOTE_NETWORK)"}}{{.IPAddress}}{{end}}')"; \
	test -n "$$athenz_ip" || { echo "failed to determine IP for $(ATHENZ_CONTROL_PLANE) on $(KIND_REMOTE_NETWORK)"; exit 1; }; \
	$(MAKE) -C athenz-cilium sync-remote-athenz-cacert sync-kind-athenz-hostaliases setup-athenz-cilium-services \
		LOCAL_CONTEXT=$(ATHENZ_LOCAL_CONTEXT) \
		REMOTE_CONTEXT=$(CILIUM_REMOTE_CONTEXT) \
		LOCAL_ATHENZ_ENDPOINT_IP="$$athenz_ip"

deploy-cilium: prepare-cilium-athenz
	kind load docker-image quay.io/cilium/cilium-envoy:v1.35.9-1773656288-7b052e66eb2cfc5ac130ce0a5be66202a10d83be --name cilium

	$(MAKE) -C cilium kind-image KIND_CLUSTER_NAME=$(KIND_REMOTE_CLUSTER)
	$(MAKE) -C cilium kind-install-cilium KIND_CLUSTER_NAME=$(KIND_REMOTE_CLUSTER) CILIUM_CLI="$(REMOTE_CILIUM_CLI)"

clean-cilium:
	$(MAKE) -C cilium kind-uninstall-cilium KIND_CLUSTER_NAME=$(KIND_REMOTE_CLUSTER) CILIUM_CLI="$(REMOTE_CILIUM_CLI)"

deploy-identityprovider:
	$(MAKE) -C athenz-identityprovider build-athenz-identityprovider LOCAL_CONTEXT=$(ATHENZ_LOCAL_CONTEXT) REMOTE_CONTEXT=$(CILIUM_REMOTE_CONTEXT)

cleanup-identityprovider:
	$(MAKE) -C athenz-identityprovider clean-athenz-identityprovider LOCAL_CONTEXT=$(ATHENZ_LOCAL_CONTEXT) REMOTE_CONTEXT=$(CILIUM_REMOTE_CONTEXT)

kind-cleanup:
	$(KIND) delete cluster --name $(KIND_LOCAL_CLUSTER)
	$(KIND) delete cluster --name $(KIND_REMOTE_CLUSTER)
