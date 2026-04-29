
KIND ?= kind
KIND_LOCAL_CLUSTER ?= cilium-athenz
KIND_REMOTE_CLUSTER ?= cilium
KIND_REMOTE_NETWORK ?= kind-$(KIND_REMOTE_CLUSTER)

patch:
	rsync -av --exclude=".gitkeep" patchfiles/cilium/* cilium

.PHONY: kind-setup kind-prepare-identityprovider

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
	kubectl config use-context kind-cilium-athenz
	$(MAKE) -C athenz-distribution clean-kubernetes-athenz
	$(MAKE) -C athenz-distribution deploy-kubernetes-athenz

clean-athenz:
	kubectl config use-context kind-cilium-athenz
	$(MAKE) -C athenz-distribution clean-kubernetes-athenz

deploy-cilium:
	kubectl config use-context kind-cilium
	kind load docker-image quay.io/cilium/cilium-envoy:v1.35.9-1773656288-7b052e66eb2cfc5ac130ce0a5be66202a10d83be --name cilium

	$(MAKE) -C cilium kind-image
	$(MAKE) -C cilium kind-install-cilium

clean-cilium:
	kubectl config use-context kind-cilium
	$(MAKE) -C cilium kind-uninstall-cilium

deploy-identityprovider:
	kubectl config use-context kind-cilium-athenz
	$(MAKE) -C athenz-identityprovider build-athenz-identityprovider
