SHELL := /bin/sh
.DEFAULT_GOAL := build-athenz-identityprovider

ifeq ($(DOCKER_REGISTRY),)
DOCKER_REGISTRY := ghcr.io/ctyano/
endif

KUBECTL ?= kubectl
ATHENZ_CONTEXT ?= kind-cilium-athenz
ATHENZ_KUBECTL ?= $(KUBECTL) --context $(ATHENZ_CONTEXT)
CILIUM_CONTEXT ?= kind-cilium
CILIUM_KUBECTL ?= $(KUBECTL) --context $(CILIUM_CONTEXT)
KIND ?= kind
KUSTOMIZE_DIR ?= kustomize
KUSTOMIZE_APPLY_DIR ?= $(KUSTOMIZE_DIR)
CILIUM_RBAC_DIR ?= cilium
CILIUM_SECRET_NAME ?= identityprovider-remote-cluster
CILIUM_KUBECONFIG ?= /tmp/athenz-identityprovider-$(CILIUM_CONTEXT).kubeconfig
WAIT_TIMEOUT ?= 180s
PRIVATE_KEY_FILE ?= private.key.pem
SERVICE_CERT_FILE ?= service.cert.pem
TLS_SECRET_MANIFEST ?= $(KUSTOMIZE_DIR)/secret.yaml
CILIUM_KIND_CLUSTER_NAME ?= $(patsubst kind-%,%,$(CILIUM_CONTEXT))
CILIUM_KIND_CONTROL_PLANE ?= $(CILIUM_KIND_CLUSTER_NAME)-control-plane
IDENTITYPROVIDER_DEPLOYMENT ?= identityprovider-deployment
IDENTITYPROVIDER_JWT_SECRET ?= identityprovider-jwt

KUSTOMIZE_NAMESPACE := $(shell sed -n 's/^namespace:[[:space:]]*//p' $(KUSTOMIZE_DIR)/kustomization.yaml | head -n 1)
IDENTITYPROVIDER_NAMESPACE := $(shell sed -n 's/^IDENTITYPROVIDER_NAMESPACE=//p' $(KUSTOMIZE_DIR)/athenz-identityprovider.env | tail -n 1)
IDENTITYPROVIDER_ENDPOINT_HOST := $(shell sed -n 's/^IDENTITYPROVIDER_ENDPOINT_HOST=//p' $(KUSTOMIZE_DIR)/athenz-identityprovider.env | tail -n 1)
ATHENZ_SERVICE_DOMAIN_CONFIG := $(shell sed -n 's/^ATHENZ_DOMAIN=//p' $(KUSTOMIZE_DIR)/athenz-sia/athenz-sia.env | tail -n 1)
SERVICEACCOUNT := $(shell sed -n 's/^SERVICEACCOUNT=//p' $(KUSTOMIZE_DIR)/athenz-sia/athenz-sia.env | tail -n 1)
PROVIDER_SERVICE := $(shell sed -n 's/^PROVIDER_SERVICE=//p' $(KUSTOMIZE_DIR)/athenz-sia/athenz-sia.env | tail -n 1)
DNS_SUFFIX := $(shell sed -n 's/^DNS_SUFFIX=//p' $(KUSTOMIZE_DIR)/athenz-sia/athenz-sia.env | tail -n 1)
ENDPOINT := $(shell sed -n 's/^ENDPOINT=//p' $(KUSTOMIZE_DIR)/athenz-sia/athenz-sia.env | tail -n 1)
CERT_SECRET := $(shell sed -n 's/^CERT_SECRET=//p' $(KUSTOMIZE_DIR)/athenz-sia/athenz-sia.env | tail -n 1)
ATHENZ_SERVICE_DOMAIN := $(if $(ATHENZ_SERVICE_DOMAIN_CONFIG),$(ATHENZ_SERVICE_DOMAIN_CONFIG),$(KUSTOMIZE_NAMESPACE))
ATHENZ_PROVIDER_SERVICE := $(ATHENZ_SERVICE_DOMAIN).$(SERVICEACCOUNT)
IDENTITYPROVIDERS_ROLE := identityproviders
IDENTITYPROVIDERS_POLICY := identityproviders

help:
	@printf '%s\n' \
		'Usage:' \
		'  make -C athenz-identityprovider' \
		'' \
		'Main targets:' \
		'  build-athenz-identityprovider   Full setup in one command (default)' \
		'  setup-athenz-identityprovider   Register in Athenz and generate Secret manifest' \
		'  deploy-athenz-identityprovider  Apply kustomize and verify rollout' \
		'  clean-athenz-identityprovider   Delete deployed resources, cilium cluster Secret, and RBAC' \
		'  deploy-cilium-rbac             Apply RBAC to the target cluster' \
		'  status-athenz-identityprovider Show deployment and Secret status' \
		'' \
		'Variables:' \
		'  ATHENZ_CONTEXT=kind-cilium-athenz' \
		'  CILIUM_CONTEXT=kind-cilium' \
		'  ATHENZ_KUBECTL=kubectl --context <athenz-context>' \
		'  CILIUM_KIND_CLUSTER_NAME='$(CILIUM_KIND_CLUSTER_NAME) \
		'  CILIUM_KUBECONFIG='$(CILIUM_KUBECONFIG) \
		'  ATHENZ_SERVICE_DOMAIN='$(ATHENZ_SERVICE_DOMAIN) \
		'  CILIUM_KUBECTL=kubectl --context <cilium-context>' \
		'  PRIVATE_KEY_FILE='$(PRIVATE_KEY_FILE)

check-cilium-context:
	@$(KUBECTL) config get-contexts $(CILIUM_CONTEXT) >/dev/null 2>&1 || { echo 'cilium context not found: $(CILIUM_CONTEXT)'; exit 1; }

generate-cilium-kubeconfig: check-cilium-context
	@mkdir -p "$$(dirname "$(CILIUM_KUBECONFIG)")"
	@tmp_kubeconfig="$(CILIUM_KUBECONFIG).tmp"; \
	$(KIND) get kubeconfig --name $(CILIUM_KIND_CLUSTER_NAME) --internal > "$$tmp_kubeconfig"; \
	control_plane_ip="$$(docker inspect $(CILIUM_KIND_CONTROL_PLANE) --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')"; \
	test -n "$$control_plane_ip" || { rm -f "$$tmp_kubeconfig"; echo 'failed to determine API server IP for $(CILIUM_KIND_CONTROL_PLANE)'; exit 1; }; \
	sed "s|server: https://$(CILIUM_KIND_CONTROL_PLANE):6443|server: https://$$control_plane_ip:6443|" "$$tmp_kubeconfig" > "$(CILIUM_KUBECONFIG)"; \
	rm -f "$$tmp_kubeconfig"
	@test -s "$(CILIUM_KUBECONFIG)" || { echo 'failed to generate $(CILIUM_KUBECONFIG)'; exit 1; }

check-private-key:
	@test -f $(PRIVATE_KEY_FILE) || { echo 'missing $(PRIVATE_KEY_FILE)'; exit 1; }

generate-private-key:
	@if [ -f "$(PRIVATE_KEY_FILE)" ]; then \
		echo "already exists: $(PRIVATE_KEY_FILE)"; \
	else \
		openssl genrsa -out - 4096 | openssl pkey -traditional -out $(PRIVATE_KEY_FILE); \
	fi

check-local-files:
	@test -f $(KUSTOMIZE_DIR)/kustomization.yaml || { echo 'missing $(KUSTOMIZE_DIR)/kustomization.yaml'; exit 1; }
	@test -f $(KUSTOMIZE_DIR)/deployment.yaml || { echo 'missing $(KUSTOMIZE_DIR)/deployment.yaml'; exit 1; }
	@test -f $(TLS_SECRET_MANIFEST) || { echo 'missing $(TLS_SECRET_MANIFEST); run make setup-athenz-identityprovider'; exit 1; }

clean-athenz-identityprovider: delete-cilium-kubeconfig-secret clean-cilium-rbac
	$(ATHENZ_KUBECTL) delete -k $(KUSTOMIZE_DIR) --ignore-not-found

deploy-cilium-rbac:
	$(CILIUM_KUBECTL) apply -k $(CILIUM_RBAC_DIR)

clean-cilium-rbac:
	$(CILIUM_KUBECTL) delete -k $(CILIUM_RBAC_DIR) --ignore-not-found

create-cilium-kubeconfig-secret: generate-cilium-kubeconfig
	$(ATHENZ_KUBECTL) -n $(IDENTITYPROVIDER_NAMESPACE) create secret generic $(CILIUM_SECRET_NAME) \
		--from-file=kubeconfig=$(CILIUM_KUBECONFIG) \
		--dry-run=client -o yaml | $(ATHENZ_KUBECTL) apply -f -

delete-cilium-kubeconfig-secret:
	$(ATHENZ_KUBECTL) -n $(IDENTITYPROVIDER_NAMESPACE) delete secret $(CILIUM_SECRET_NAME) --ignore-not-found

register-athenz-identityprovider: generate-private-key
	$(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		curl \
			-sS \
			-d"{\"name\":\"$(ATHENZ_SERVICE_DOMAIN)\",\"adminUsers\":[\"user.athenz_admin\"]}" \
			-H"Content-Type: application/json" \
			--key /var/run/athenz/athenz_admin.private.pem \
			--cert /var/run/athenz/athenz_admin.cert.pem \
			"https://athenz-zms-server.athenz:4443/zms/v1/domain" || :
	$(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			add-service \
			$(SERVICEACCOUNT) \
			0 \
			"$$(openssl rsa -in $(PRIVATE_KEY_FILE) -pubout | base64 | tr -d '\r\n' | tr '\+\=\/' '\.\-\_')" || :
	$(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			add-public-key \
			$(SERVICEACCOUNT) \
			0 \
			"$$(openssl rsa -in $(PRIVATE_KEY_FILE) -pubout | base64 | tr -d '\r\n' | tr '\+\=\/' '\.\-\_')" || :
	$(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			set-service-endpoint \
			$(SERVICEACCOUNT) \
			https://$(IDENTITYPROVIDER_ENDPOINT_HOST)/v0/data/identityprovider
	$(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d sys.auth \
			set-domain-template \
			instance_provider \
			provider="$(ATHENZ_PROVIDER_SERVICE)" \
			dnssuffix="$(DNS_SUFFIX)"
	$(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			set-domain-template \
			instance_registration \
			instanceregisterer="user.athenz_admin" \
			service="$(SERVICEACCOUNT)"
	$(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			set-domain-template \
			identity_provisioning \
			instanceprovider="sys.auth.zts" \
			service="$(SERVICEACCOUNT)"
	$(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			set-domain-template \
			identity_provisioning \
			instanceprovider="$(ATHENZ_PROVIDER_SERVICE)" \
			service="$(SERVICEACCOUNT)"

configure-identityprovider-launch-policy:
	$(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			add-regular-role \
			$(IDENTITYPROVIDERS_ROLE) \
			$(ATHENZ_PROVIDER_SERVICE) || :
	$(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			add-member \
			$(IDENTITYPROVIDERS_ROLE) \
			$(ATHENZ_PROVIDER_SERVICE) || :
	$(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			add-policy \
			$(IDENTITYPROVIDERS_POLICY) \
			grant launch to $(IDENTITYPROVIDERS_ROLE) on '$(ATHENZ_SERVICE_DOMAIN):service.*' || :
	$(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			add-assertion \
			$(IDENTITYPROVIDERS_POLICY) \
			grant launch to $(IDENTITYPROVIDERS_ROLE) on '$(ATHENZ_SERVICE_DOMAIN):service.*' || :

check-register-athenz-identityprovider:
	SLEEP_SECONDS=5; \
	WAITING_THRESHOLD=60; \
	i=0; \
	while true; do \
		printf "\n***** Waiting for ZTS registration ($$(( $$i * $${SLEEP_SECONDS} ))s/$${WAITING_THRESHOLD}s) *****\n"; \
		if $(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
			curl -sf \
				-H"Content-type: application/json" \
				-H"X-Auth-Request-Preferred-Username: user.athenz_admin" \
				"https://athenz-zts-server.athenz:4443/zts/v1/domain/$(ATHENZ_SERVICE_DOMAIN)/service/$(SERVICEACCOUNT)" >/dev/null \
			&& $(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
				sh -c "chmod a+rw /tmp/.*.jwt ||:; zts-svccert -get-instance-register-token -zts $(ENDPOINT) -domain $(ATHENZ_SERVICE_DOMAIN) -service $(SERVICEACCOUNT) -provider $(PROVIDER_SERVICE) -instance $(ATHENZ_PROVIDER_SERVICE) -svc-key-file /var/run/athenz/athenz_admin.private.pem -svc-cert-file /var/run/athenz/athenz_admin.cert.pem -attestation-data /tmp/.identitydocument.jwt" >/dev/null; then \
			break; \
		fi; \
		echo "Waiting for ZTS to sync with ZMS..."; \
		sleep $${SLEEP_SECONDS}; \
		i=$$(( i + 1 )); \
		if [ $$i -eq $$(( $${WAITING_THRESHOLD} / $${SLEEP_SECONDS} )) ]; then \
			printf "\n\n** Waiting ($$(( $$i * $${SLEEP_SECONDS} ))s) reached threshold ($${WAITING_THRESHOLD}s) **\n\n"; \
			$(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
				zms-cli -z https://athenz-zms-server.athenz:4443/zms/v1 -key /var/run/athenz/athenz_admin.private.pem -cert /var/run/athenz/athenz_admin.cert.pem -d $(ATHENZ_SERVICE_DOMAIN) show-domain || :; \
			exit 1; \
		fi; \
	done
	SLEEP_SECONDS=5; \
	WAITING_THRESHOLD=60; \
	i=0; \
	while true; do \
		printf "\n***** Waiting for launch permission ($$(( $$i * $${SLEEP_SECONDS} ))s/$${WAITING_THRESHOLD}s) *****\n"; \
		if $(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
			curl -sf \
				-H"Content-type: application/json" \
				-H"X-Auth-Request-Preferred-Username: user.athenz_admin" \
				"https://athenz-zts-server.athenz:4443/zts/v1/access/launch/$(ATHENZ_SERVICE_DOMAIN):service.$(SERVICEACCOUNT)?principal=$(PROVIDER_SERVICE)" \
			| grep -q '"granted":true'; then \
			break; \
		fi; \
		echo "Waiting for ZTS to sync with ZMS..."; \
		sleep $${SLEEP_SECONDS}; \
		i=$$(( i + 1 )); \
		if [ $$i -eq $$(( $${WAITING_THRESHOLD} / $${SLEEP_SECONDS} )) ]; then \
			printf "\n\n** Waiting ($$(( $$i * $${SLEEP_SECONDS} ))s) reached threshold ($${WAITING_THRESHOLD}s) **\n\n"; \
			$(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
				zms-cli -z https://athenz-zms-server.athenz:4443/zms/v1 -key /var/run/athenz/athenz_admin.private.pem -cert /var/run/athenz/athenz_admin.cert.pem -d $(ATHENZ_SERVICE_DOMAIN) show-domain || :; \
			exit 1; \
		fi; \
	done

setup-athenz-identityprovider: register-athenz-identityprovider configure-identityprovider-launch-policy check-register-athenz-identityprovider
	$(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		sh -c "chmod a+rw /tmp/.*.jwt ||:; zts-svccert -get-instance-register-token -zts $(ENDPOINT) -domain $(ATHENZ_SERVICE_DOMAIN) -service $(SERVICEACCOUNT) -provider $(PROVIDER_SERVICE) -instance $(ATHENZ_PROVIDER_SERVICE) -svc-key-file /var/run/athenz/athenz_admin.private.pem -svc-cert-file /var/run/athenz/athenz_admin.cert.pem -attestation-data /tmp/.identitydocument.jwt"
	$(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		cat /tmp/.identitydocument.jwt > identitydocument.jwt
	$(ATHENZ_KUBECTL) -n $(IDENTITYPROVIDER_NAMESPACE) create secret generic $(IDENTITYPROVIDER_JWT_SECRET) \
		--from-file=identitydocument.jwt=identitydocument.jwt \
		--dry-run=client -o yaml > $(TLS_SECRET_MANIFEST)
	$(ATHENZ_KUBECTL) -n athenz exec -i deployment/athenz-cli -- \
		sh -c 'cat > /tmp/identityprovider.private.key.pem' < $(PRIVATE_KEY_FILE)
	$(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		sh -c "chmod a+rw /tmp/*.pem ||:; zts-svccert -zts $(ENDPOINT) -domain $(ATHENZ_SERVICE_DOMAIN) -service $(SERVICEACCOUNT) -provider $(PROVIDER_SERVICE) -instance $(ATHENZ_PROVIDER_SERVICE) -attestation-data /tmp/.identitydocument.jwt -dns-domain $(DNS_SUFFIX) -private-key /tmp/identityprovider.private.key.pem -cert-file /tmp/$(ATHENZ_PROVIDER_SERVICE).cert.pem -signer-cert-file /tmp/ca.cert.pem"
	$(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		cat /tmp/$(ATHENZ_PROVIDER_SERVICE).cert.pem > $(SERVICE_CERT_FILE)
	printf "\n---\n" >> $(TLS_SECRET_MANIFEST)
	$(ATHENZ_KUBECTL) -n $(IDENTITYPROVIDER_NAMESPACE) create secret tls $(CERT_SECRET) \
		--key $(PRIVATE_KEY_FILE) \
		--cert $(SERVICE_CERT_FILE) \
		--dry-run=client -o yaml >> $(TLS_SECRET_MANIFEST)


sync-athenz-cacert-to-namespace:
	@tmp_ca="$$(mktemp)"; \
	$(ATHENZ_KUBECTL) -n athenz get secret athenz-cacert -o jsonpath='{.data.ca\.cert\.pem}' | openssl base64 -d -A > "$$tmp_ca"; \
	$(ATHENZ_KUBECTL) -n $(IDENTITYPROVIDER_NAMESPACE) create secret generic athenz-cacert \
		--from-file=ca.cert.pem="$$tmp_ca" \
		--dry-run=client -o yaml | $(ATHENZ_KUBECTL) apply -f -; \
	rm -f "$$tmp_ca"

deploy-athenz-identityprovider: check-local-files
	$(ATHENZ_KUBECTL) apply -k $(KUSTOMIZE_APPLY_DIR)
	$(MAKE) sync-athenz-cacert-to-namespace
	$(MAKE) create-cilium-kubeconfig-secret
	$(ATHENZ_KUBECTL) -n $(IDENTITYPROVIDER_NAMESPACE) rollout restart deployment/$(IDENTITYPROVIDER_DEPLOYMENT)
	$(MAKE) test-athenz-identityprovider

build-athenz-identityprovider: generate-cilium-kubeconfig generate-private-key deploy-cilium-rbac setup-athenz-identityprovider deploy-athenz-identityprovider status-athenz-identityprovider
	@echo ""
	@echo "**************************************"
	@echo "**  Identity provider build complete *"
	@echo "**************************************"
	@echo ""

test-athenz-identityprovider:
	SLEEP_SECONDS=5; \
	WAITING_THRESHOLD=60; \
	i=0; \
	while true; do \
		printf "\n***** Waiting for identityprovider ($$(( $$i * $${SLEEP_SECONDS} ))s/$${WAITING_THRESHOLD}s) *****\n"; \
		if $(ATHENZ_KUBECTL) -n $(IDENTITYPROVIDER_NAMESPACE) rollout status deployment/$(IDENTITYPROVIDER_DEPLOYMENT) --timeout=5s >/dev/null 2>&1 \
			&& $(ATHENZ_KUBECTL) -n $(IDENTITYPROVIDER_NAMESPACE) exec deployment/$(IDENTITYPROVIDER_DEPLOYMENT) -c sia -- \
				ls -alF /var/run/athenz/tls.key /var/run/athenz/tls.crt /var/run/athenz/ca.crt >/dev/null; then \
			break; \
		fi; \
		echo "Waiting for Identity Provisioning..."; \
		sleep $${SLEEP_SECONDS}; \
		i=$$(( i + 1 )); \
		if [ $$i -eq $$(( $${WAITING_THRESHOLD} / $${SLEEP_SECONDS} )) ]; then \
			printf "\n\n** Waiting ($$(( $$i * $${SLEEP_SECONDS} ))s) reached threshold ($${WAITING_THRESHOLD}s) **\n\n"; \
			$(ATHENZ_KUBECTL) -n $(IDENTITYPROVIDER_NAMESPACE) get pods -l app=$(IDENTITYPROVIDER_DEPLOYMENT); \
			$(ATHENZ_KUBECTL) -n $(IDENTITYPROVIDER_NAMESPACE) logs deployment/$(IDENTITYPROVIDER_DEPLOYMENT) --all-containers=true || :; \
			$(ATHENZ_KUBECTL) -n $(IDENTITYPROVIDER_NAMESPACE) describe deployment $(IDENTITYPROVIDER_DEPLOYMENT) || :; \
			exit 1; \
		fi; \
	done
	$(ATHENZ_KUBECTL) -n $(IDENTITYPROVIDER_NAMESPACE) get all

status-athenz-identityprovider:
	$(ATHENZ_KUBECTL) -n $(IDENTITYPROVIDER_NAMESPACE) get deployment $(IDENTITYPROVIDER_DEPLOYMENT)
	$(ATHENZ_KUBECTL) -n $(IDENTITYPROVIDER_NAMESPACE) get pods -l app=$(IDENTITYPROVIDER_DEPLOYMENT)
	$(ATHENZ_KUBECTL) -n $(IDENTITYPROVIDER_NAMESPACE) get secret $(IDENTITYPROVIDER_JWT_SECRET)
	$(ATHENZ_KUBECTL) -n $(IDENTITYPROVIDER_NAMESPACE) get secret $(CERT_SECRET)
	$(ATHENZ_KUBECTL) -n $(IDENTITYPROVIDER_NAMESPACE) get secret $(CILIUM_SECRET_NAME)

logs-athenz-identityprovider:
	$(ATHENZ_KUBECTL) -n $(IDENTITYPROVIDER_NAMESPACE) logs deployment/$(IDENTITYPROVIDER_DEPLOYMENT) --all-containers=true --tail=200
