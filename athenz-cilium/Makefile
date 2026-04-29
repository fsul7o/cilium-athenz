SHELL := /bin/sh

KUBECTL ?= kubectl
LOCAL_CONTEXT ?= kind-cilium-athenz
LOCAL_KUBECTL ?= $(KUBECTL) --context $(LOCAL_CONTEXT)
REMOTE_CONTEXT ?= kind-cilium
REMOTE_KUBECTL ?= $(KUBECTL) --context $(REMOTE_CONTEXT)
REMOTE_SECRET_NAMESPACE ?= kube-system
REMOTE_ATHENZ_CACERT_SECRET ?= athenz-cacert
REMOTE_ATHENZ_ZTS_DNS_NAME ?= athenz-zts-server.athenz
KIND_CUSTOM_VALUES_FILE ?= ../cilium/contrib/testing/kind-custom.yaml
LOCAL_ZTS_ENDPOINT_IP ?=

ATHENZ_SERVICE_DOMAIN ?= cilium
REGISTER_PROVIDER_SERVICE ?= cilium.identityprovider
DNS_SUFFIX ?= svc.cluster.local
REGISTER_SERVICEACCOUNT ?=
CILIUM_AGENT_SERVICEACCOUNT ?= cilium-agent
CILIUM_OPERATOR_SERVICEACCOUNT ?= cilium-operator

help:
	@printf '%s\n' \
		'Usage:' \
		'  make -C athenz-cilium <target>' \
		'' \
		'Main targets:' \
		'  setup-athenz-cilium-services  Register cilium-agent/cilium-operator in Athenz' \
		'  sync-remote-athenz-cacert     Copy athenz-cacert Secret into the remote cluster' \
		'  sync-kind-athenz-zts-hostaliases Update kind-custom.yaml hostAliases for athenz-zts-server.athenz'

sync-remote-athenz-cacert:
	@tmp_ca="$$(mktemp /tmp/athenz-cacert.XXXXXX.pem)"; \
	$(LOCAL_KUBECTL) -n athenz get secret $(REMOTE_ATHENZ_CACERT_SECRET) -o jsonpath='{.data.ca\.cert\.pem}' \
		| openssl base64 -d -A > "$$tmp_ca"; \
	$(REMOTE_KUBECTL) -n $(REMOTE_SECRET_NAMESPACE) create secret generic $(REMOTE_ATHENZ_CACERT_SECRET) \
		--from-file=ca.cert.pem="$$tmp_ca" \
		--dry-run=client -o yaml | $(REMOTE_KUBECTL) apply -f -; \
	rm -f "$$tmp_ca"

sync-kind-athenz-zts-hostaliases:
	@test -n "$(LOCAL_ZTS_ENDPOINT_IP)" || { echo 'missing LOCAL_ZTS_ENDPOINT_IP'; exit 1; }
	@test -f "$(KIND_CUSTOM_VALUES_FILE)" || { echo "missing $(KIND_CUSTOM_VALUES_FILE)"; exit 1; }
	@perl -0pi -e 's/(hostAliases:\n(?:[^\n]*\n)*?\s*- ip: )"[^"]*"\n(\s*hostnames:\n\s*- $(REMOTE_ATHENZ_ZTS_DNS_NAME))/$${1}"$(LOCAL_ZTS_ENDPOINT_IP)"\n$${2}/g' "$(KIND_CUSTOM_VALUES_FILE)"

register-athenz-service:
	@test -n "$(REGISTER_SERVICEACCOUNT)" || { echo 'missing REGISTER_SERVICEACCOUNT'; exit 1; }
	$(LOCAL_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		curl \
			-sS \
			-d"{\"name\":\"$(ATHENZ_SERVICE_DOMAIN)\",\"adminUsers\":[\"user.athenz_admin\"]}" \
			-H"Content-Type: application/json" \
			--key /var/run/athenz/athenz_admin.private.pem \
			--cert /var/run/athenz/athenz_admin.cert.pem \
			"https://athenz-zms-server.athenz:4443/zms/v1/domain" || :
	$(LOCAL_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d sys.auth \
			set-domain-template \
			instance_provider \
			provider="$(REGISTER_PROVIDER_SERVICE)" \
			dnssuffix="$(DNS_SUFFIX)"
	$(LOCAL_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d sys.auth \
			set-domain-template \
			instance_provider \
			provider="$(REGISTER_PROVIDER_SERVICE)" \
			dnssuffix="$(DNS_SUFFIX)"
	$(LOCAL_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		curl \
			-sS \
			-X PUT \
			-H "Content-Type: application/json" \
			-d "{\"name\":\"$(REGISTER_SERVICEACCOUNT)\"}" \
			--key /var/run/athenz/athenz_admin.private.pem \
			--cert /var/run/athenz/athenz_admin.cert.pem \
			"https://athenz-zms-server.athenz:4443/zms/v1/domain/$(ATHENZ_SERVICE_DOMAIN)/service/$(REGISTER_SERVICEACCOUNT)"
	$(LOCAL_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			set-domain-template \
			identity_provisioning \
			instanceprovider="sys.auth.zts" \
			service="$(REGISTER_SERVICEACCOUNT)"
	$(LOCAL_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			set-domain-template \
			identity_provisioning \
			instanceprovider="$(REGISTER_PROVIDER_SERVICE)" \
			service="$(REGISTER_SERVICEACCOUNT)"

check-register-athenz-service:
	@test -n "$(REGISTER_SERVICEACCOUNT)" || { echo 'missing REGISTER_SERVICEACCOUNT'; exit 1; }
	SLEEP_SECONDS=5; \
	WAITING_THRESHOLD=60; \
	i=0; \
	while true; do \
		printf "\n***** Waiting for Athenz service $(REGISTER_SERVICEACCOUNT) ($$(( $$i * $${SLEEP_SECONDS} ))s/$${WAITING_THRESHOLD}s) *****\n"; \
		if $(LOCAL_KUBECTL) -n athenz exec deployment/athenz-cli -- \
			curl -sf \
				-H"Content-type: application/json" \
				-H"X-Auth-Request-Preferred-Username: user.athenz_admin" \
				"https://athenz-zts-server.athenz:4443/zts/v1/domain/$(ATHENZ_SERVICE_DOMAIN)/service/$(REGISTER_SERVICEACCOUNT)" >/dev/null \
			&& $(LOCAL_KUBECTL) -n athenz exec deployment/athenz-cli -- \
				curl -sf \
					-H"Content-type: application/json" \
					-H"X-Auth-Request-Preferred-Username: user.athenz_admin" \
					"https://athenz-zts-server.athenz:4443/zts/v1/access/launch/$(ATHENZ_SERVICE_DOMAIN):service.$(REGISTER_SERVICEACCOUNT)?principal=$(REGISTER_PROVIDER_SERVICE)" \
				| grep -q '"granted":true'; then \
			break; \
		fi; \
		echo "Waiting for ZTS to sync with ZMS..."; \
		sleep $${SLEEP_SECONDS}; \
		i=$$(( i + 1 )); \
		if [ $$i -eq $$(( $${WAITING_THRESHOLD} / $${SLEEP_SECONDS} )) ]; then \
			printf "\n\n** Waiting ($$(( $$i * $${SLEEP_SECONDS} ))s) reached threshold ($${WAITING_THRESHOLD}s) **\n\n"; \
			$(LOCAL_KUBECTL) -n athenz exec deployment/athenz-cli -- \
				zms-cli -z https://athenz-zms-server.athenz:4443/zms/v1 -key /var/run/athenz/athenz_admin.private.pem -cert /var/run/athenz/athenz_admin.cert.pem -d $(ATHENZ_SERVICE_DOMAIN) show-domain || :; \
			exit 1; \
		fi; \
	done

setup-athenz-cilium-services:
	$(MAKE) register-athenz-service check-register-athenz-service REGISTER_SERVICEACCOUNT=$(CILIUM_AGENT_SERVICEACCOUNT)
	$(MAKE) register-athenz-service check-register-athenz-service REGISTER_SERVICEACCOUNT=$(CILIUM_OPERATOR_SERVICEACCOUNT)
