SHELL := /bin/sh

KUBECTL ?= kubectl
ATHENZ_CONTEXT ?= kind-cilium-athenz
ATHENZ_KUBECTL ?= $(KUBECTL) --context $(ATHENZ_CONTEXT)
CILIUM_CONTEXT ?= kind-cilium
CILIUM_KUBECTL ?= $(KUBECTL) --context $(CILIUM_CONTEXT)
CILIUM1_CONTEXT ?=
CILIUM2_CONTEXT ?=
CILIUM_KIND_CLUSTER ?= $(patsubst kind-%,%,$(CILIUM_CONTEXT))
CILIUM_SECRET_NAMESPACE ?= kube-system
ATHENZ_CACERT_SECRET ?= athenz-cacert
ATHENZ_ZTS_DNS_NAME ?= athenz-zts-server.athenz
ATHENZ_ZMS_DNS_NAME ?= athenz-zms-server.athenz
KIND_CUSTOM_VALUES_FILE ?= ../cilium/contrib/testing/kind-custom.yaml
ATHENZ_ENDPOINT_IP ?=

ATHENZ_SERVICE_DOMAIN ?= cilium
REGISTER_PROVIDER_SERVICE ?= cilium.identityprovider
DNS_SUFFIX ?= svc.cluster.local
REGISTER_SERVICEACCOUNT ?=
CILIUM_AGENT_SERVICEACCOUNT ?= cilium-agent
CILIUM_OPERATOR_SERVICEACCOUNT ?= cilium-operator
CILIUM_OPERATOR_SYNC_ROLE ?= cilium_operator_service_sync
CILIUM_OPERATOR_SYNC_POLICY ?= cilium_operator_service_sync
TEST_WORKLOAD_FILE ?= manifests/test-workload.yaml
TEST_NAMESPACE ?= default
TEST_ECHO_POD ?= echo
TEST_CLIENT_POD ?= pod-worker
TEST_ECHO_IMAGE ?= gcr.io/k8s-staging-ingressconformance/echoserver:v20221109-7ee2f3e
TEST_ROLE ?= demo_clients
TEST_POLICY ?= demo_clients_to_echo
TEST_POLICY_ACTION ?= GET
TEST_POLICY_PORT ?= 3000
TEST_POLICY_PATH ?= /headers
BENCHMARK_WORKLOAD_FILE ?= manifests/benchmark-workload.yaml
BENCH_NAMESPACE ?= default
BENCH_VEGETA_DEPLOYMENT ?= vegeta
BENCH_VEGETA_LABEL ?= app=vegeta
BENCH_VEGETA_IMAGE ?= ghcr.io/ctyano/docker-vegeta:latest
BENCH_PLAIN_ECHO_POD ?= echo-plain
BENCH_AUTH_ECHO_POD ?= echo-auth
BENCH_PLAIN_SERVICE ?= echo-plain
BENCH_AUTH_SERVICE ?= echo-auth
BENCH_ROLE ?= benchmark_clients
BENCH_POLICY ?= benchmark_clients_to_echo_auth
BENCH_POLICY_ACTION ?= GET
BENCH_POLICY_PORT ?= 3000
BENCH_POLICY_PATH ?= /headers
BENCH_RATE ?= 100
BENCH_WORKERS ?= 100
BENCH_DURATION ?= 30s
BENCH_KEEPALIVE ?= false
ATHENZ_CLI_DEPLOYMENT ?= deployment/athenz-cli

help:
	@printf '%s\n' \
		'Usage:' \
		'  make -C athenz-cilium <target>' \
		'' \
		'Main targets:' \
		'  setup-athenz-cilium-services  Register cilium-agent/cilium-operator in Athenz' \
		'  load-test-workload-image     Pull/load the echo test image into the cilium kind cluster' \
		'  deploy-test-workload         Deploy demo workload and seed Athenz role/policy' \
		'  deploy-benchmark-workload    Deploy vegeta plus plain/auth benchmark services' \
		'  run-benchmark                Run plain then auth vegeta benchmarks' \
		'  clean-benchmark-workload     Remove benchmark workload from the cilium cluster' \
		'  clean-test-workload          Remove demo workload from the cilium cluster' \
		'  sync-cilium-athenz-cacert     Copy athenz-cacert Secret into the cilium cluster' \
		'  sync-kind-athenz-hostaliases  Update kind-custom.yaml hostAliases for athenz-zts-server.athenz/athenz-zms-server.athenz'

sync-cilium-athenz-cacert:
	@tmp_ca="$$(mktemp /tmp/athenz-cacert.XXXXXX.pem)"; \
	$(ATHENZ_KUBECTL) -n athenz get secret $(ATHENZ_CACERT_SECRET) -o jsonpath='{.data.ca\.cert\.pem}' \
		| openssl base64 -d -A > "$$tmp_ca"; \
	$(CILIUM_KUBECTL) -n $(CILIUM_SECRET_NAMESPACE) create secret generic $(ATHENZ_CACERT_SECRET) \
		--from-file=ca.cert.pem="$$tmp_ca" \
		--dry-run=client -o yaml | $(CILIUM_KUBECTL) apply -f -; \
	rm -f "$$tmp_ca"

sync-kind-athenz-hostaliases:
	@test -n "$(ATHENZ_ENDPOINT_IP)" || { echo 'missing ATHENZ_ENDPOINT_IP'; exit 1; }
	@test -f "$(KIND_CUSTOM_VALUES_FILE)" || { echo "missing $(KIND_CUSTOM_VALUES_FILE)"; exit 1; }
	@perl -0pi -e 's/(hostAliases:\n(?:[^\n]*\n)*?\s*- ip: )"[^"]*"\n(\s*hostnames:\n\s*- $(ATHENZ_ZTS_DNS_NAME)\n\s*- $(ATHENZ_ZMS_DNS_NAME))/$${1}"$(ATHENZ_ENDPOINT_IP)"\n$${2}/g' "$(KIND_CUSTOM_VALUES_FILE)"

sync-kind-athenz-zts-hostaliases: sync-kind-athenz-hostaliases

register-athenz-service:
	@test -n "$(REGISTER_SERVICEACCOUNT)" || { echo 'missing REGISTER_SERVICEACCOUNT'; exit 1; }
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
			-d sys.auth \
			set-domain-template \
			instance_provider \
			provider="$(REGISTER_PROVIDER_SERVICE)" \
			dnssuffix="$(DNS_SUFFIX)"
	$(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d sys.auth \
			set-domain-template \
			instance_provider \
			provider="$(REGISTER_PROVIDER_SERVICE)" \
			dnssuffix="$(DNS_SUFFIX)"
	$(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		curl \
			-sS \
			-X PUT \
			-H "Content-Type: application/json" \
			-d "{\"name\":\"$(REGISTER_SERVICEACCOUNT)\"}" \
			--key /var/run/athenz/athenz_admin.private.pem \
			--cert /var/run/athenz/athenz_admin.cert.pem \
			"https://athenz-zms-server.athenz:4443/zms/v1/domain/$(ATHENZ_SERVICE_DOMAIN)/service/$(REGISTER_SERVICEACCOUNT)"
	$(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			set-domain-template \
			identity_provisioning \
			instanceprovider="sys.auth.zts" \
			service="$(REGISTER_SERVICEACCOUNT)"
	$(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			set-domain-template \
			identity_provisioning \
			instanceprovider="$(REGISTER_PROVIDER_SERVICE)" \
			service="$(REGISTER_SERVICEACCOUNT)"

configure-cilium-operator-zms-policy:
	$(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			add-regular-role \
			$(CILIUM_OPERATOR_SYNC_ROLE) \
			$(ATHENZ_SERVICE_DOMAIN).$(CILIUM_OPERATOR_SERVICEACCOUNT) || :
	$(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			add-member \
			$(CILIUM_OPERATOR_SYNC_ROLE) \
			$(ATHENZ_SERVICE_DOMAIN).$(CILIUM_OPERATOR_SERVICEACCOUNT) || :
	$(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			add-policy \
			$(CILIUM_OPERATOR_SYNC_POLICY) \
			grant update to $(CILIUM_OPERATOR_SYNC_ROLE) on '$(ATHENZ_SERVICE_DOMAIN):service.*' || :
	$(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			add-assertion \
			$(CILIUM_OPERATOR_SYNC_POLICY) \
			grant update to $(CILIUM_OPERATOR_SYNC_ROLE) on '$(ATHENZ_SERVICE_DOMAIN):service.*' || :
	$(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			add-assertion \
			$(CILIUM_OPERATOR_SYNC_POLICY) \
			grant delete to $(CILIUM_OPERATOR_SYNC_ROLE) on '$(ATHENZ_SERVICE_DOMAIN):service.*' || :

check-register-athenz-service:
	@test -n "$(REGISTER_SERVICEACCOUNT)" || { echo 'missing REGISTER_SERVICEACCOUNT'; exit 1; }
	SLEEP_SECONDS=5; \
	WAITING_THRESHOLD=60; \
	i=0; \
	while true; do \
		printf "\n***** Waiting for Athenz service $(REGISTER_SERVICEACCOUNT) ($$(( $$i * $${SLEEP_SECONDS} ))s/$${WAITING_THRESHOLD}s) *****\n"; \
		if $(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
			curl -sf \
				-H"Content-type: application/json" \
				-H"X-Auth-Request-Preferred-Username: user.athenz_admin" \
				"https://athenz-zts-server.athenz:4443/zts/v1/domain/$(ATHENZ_SERVICE_DOMAIN)/service/$(REGISTER_SERVICEACCOUNT)" >/dev/null \
			&& $(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
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
			$(ATHENZ_KUBECTL) -n athenz exec deployment/athenz-cli -- \
				zms-cli -z https://athenz-zms-server.athenz:4443/zms/v1 -key /var/run/athenz/athenz_admin.private.pem -cert /var/run/athenz/athenz_admin.cert.pem -d $(ATHENZ_SERVICE_DOMAIN) show-domain || :; \
			exit 1; \
		fi; \
	done

setup-athenz-cilium-services:
	$(MAKE) register-athenz-service check-register-athenz-service REGISTER_SERVICEACCOUNT=$(CILIUM_AGENT_SERVICEACCOUNT)
	$(MAKE) register-athenz-service check-register-athenz-service REGISTER_SERVICEACCOUNT=$(CILIUM_OPERATOR_SERVICEACCOUNT)
	$(MAKE) configure-cilium-operator-zms-policy

load-test-workload-image:
	@docker image inspect "$(TEST_ECHO_IMAGE)" >/dev/null 2>&1 || docker pull "$(TEST_ECHO_IMAGE)"
	kind load docker-image "$(TEST_ECHO_IMAGE)" --name "$(CILIUM_KIND_CLUSTER)"

load-benchmark-workload-images:
	@docker image inspect "$(TEST_ECHO_IMAGE)" >/dev/null 2>&1 || docker pull "$(TEST_ECHO_IMAGE)"
	@docker image inspect "$(BENCH_VEGETA_IMAGE)" >/dev/null 2>&1 || docker pull "$(BENCH_VEGETA_IMAGE)"
	kind load docker-image "$(TEST_ECHO_IMAGE)" --name "$(CILIUM_KIND_CLUSTER)"
	kind load docker-image "$(BENCH_VEGETA_IMAGE)" --name "$(CILIUM_KIND_CLUSTER)"

apply-test-workload: load-test-workload-image
	@test -f "$(TEST_WORKLOAD_FILE)" || { echo "missing $(TEST_WORKLOAD_FILE)"; exit 1; }
	$(CILIUM_KUBECTL) apply -f "$(TEST_WORKLOAD_FILE)"

apply-benchmark-workload: load-benchmark-workload-images
	@test -f "$(BENCHMARK_WORKLOAD_FILE)" || { echo "missing $(BENCHMARK_WORKLOAD_FILE)"; exit 1; }
	$(CILIUM_KUBECTL) apply -f "$(BENCHMARK_WORKLOAD_FILE)"

wait-test-workload:
	$(CILIUM_KUBECTL) -n $(TEST_NAMESPACE) wait --for=condition=Ready pod/$(TEST_ECHO_POD) pod/$(TEST_CLIENT_POD) --timeout=180s
	@for pod in "$(TEST_ECHO_POD)" "$(TEST_CLIENT_POD)"; do \
		i=0; \
		while true; do \
			identity_id="$$($(CILIUM_KUBECTL) -n $(TEST_NAMESPACE) get ciliumendpoint $$pod -o jsonpath='{.status.identity.id}' 2>/dev/null || true)"; \
			if [ -n "$$identity_id" ]; then \
				echo "$$pod cilium identity=$$identity_id"; \
				break; \
			fi; \
			i=$$((i + 1)); \
			if [ $$i -ge 60 ]; then \
				echo "timed out waiting for cilium identity on $$pod"; \
				exit 1; \
			fi; \
			sleep 2; \
		done; \
	done

wait-benchmark-workload:
	$(CILIUM_KUBECTL) -n $(BENCH_NAMESPACE) wait --for=condition=Ready pod/$(BENCH_PLAIN_ECHO_POD) pod/$(BENCH_AUTH_ECHO_POD) --timeout=180s
	$(CILIUM_KUBECTL) -n $(BENCH_NAMESPACE) rollout status deployment/$(BENCH_VEGETA_DEPLOYMENT) --timeout=180s
	@vegeta_pod="$$( $(CILIUM_KUBECTL) -n $(BENCH_NAMESPACE) get pod -l $(BENCH_VEGETA_LABEL) -o jsonpath='{.items[0].metadata.name}' )"; \
	test -n "$$vegeta_pod" || { echo "missing vegeta pod"; exit 1; }; \
	for pod in "$(BENCH_PLAIN_ECHO_POD)" "$(BENCH_AUTH_ECHO_POD)" "$$vegeta_pod"; do \
		i=0; \
		while true; do \
			identity_id="$$($(CILIUM_KUBECTL) -n $(BENCH_NAMESPACE) get ciliumendpoint $$pod -o jsonpath='{.status.identity.id}' 2>/dev/null || true)"; \
			if [ -n "$$identity_id" ]; then \
				echo "$$pod cilium identity=$$identity_id"; \
				break; \
			fi; \
			i=$$((i + 1)); \
			if [ $$i -ge 60 ]; then \
				echo "timed out waiting for cilium identity on $$pod"; \
				exit 1; \
			fi; \
			sleep 2; \
		done; \
	done

configure-test-athenz-policy:
	@src_id="$$($(CILIUM_KUBECTL) -n $(TEST_NAMESPACE) get ciliumendpoint $(TEST_CLIENT_POD) -o jsonpath='{.status.identity.id}')"; \
	dst_id="$$($(CILIUM_KUBECTL) -n $(TEST_NAMESPACE) get ciliumendpoint $(TEST_ECHO_POD) -o jsonpath='{.status.identity.id}')"; \
	test -n "$$src_id" || { echo 'missing source cilium identity'; exit 1; }; \
	test -n "$$dst_id" || { echo 'missing destination cilium identity'; exit 1; }; \
	resource="$(ATHENZ_SERVICE_DOMAIN):service.$$dst_id:$(TEST_POLICY_PORT)$(TEST_POLICY_PATH)"; \
	echo "configure Athenz test policy: cilium.$$src_id -> cilium.$$dst_id"; \
	for service_id in "$$src_id" "$$dst_id"; do \
		i=0; \
		while true; do \
			if $(ATHENZ_KUBECTL) -n athenz exec $(ATHENZ_CLI_DEPLOYMENT) -- \
				curl -sf \
					--key /var/run/athenz/athenz_admin.private.pem \
					--cert /var/run/athenz/athenz_admin.cert.pem \
					"https://athenz-zms-server.athenz:4443/zms/v1/domain/$(ATHENZ_SERVICE_DOMAIN)/service/$$service_id" >/dev/null; then \
				break; \
			fi; \
			i=$$((i + 1)); \
			if [ $$i -ge 60 ]; then \
				echo "timed out waiting for Athenz service $(ATHENZ_SERVICE_DOMAIN).$$service_id"; \
				exit 1; \
			fi; \
			sleep 2; \
		done; \
	done; \
	$(ATHENZ_KUBECTL) -n athenz exec $(ATHENZ_CLI_DEPLOYMENT) -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			delete-policy \
			$(TEST_POLICY) || :; \
	$(ATHENZ_KUBECTL) -n athenz exec $(ATHENZ_CLI_DEPLOYMENT) -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			add-regular-role \
			$(TEST_ROLE) \
			$(ATHENZ_SERVICE_DOMAIN).$$src_id || :; \
	$(ATHENZ_KUBECTL) -n athenz exec $(ATHENZ_CLI_DEPLOYMENT) -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			add-member \
			$(TEST_ROLE) \
			$(ATHENZ_SERVICE_DOMAIN).$$src_id || :; \
	$(ATHENZ_KUBECTL) -n athenz exec $(ATHENZ_CLI_DEPLOYMENT) -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			add-policy \
			$(TEST_POLICY) \
			grant $(TEST_POLICY_ACTION) to $(TEST_ROLE) on "$$resource" || :; \
	$(ATHENZ_KUBECTL) -n athenz exec $(ATHENZ_CLI_DEPLOYMENT) -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			add-assertion \
			$(TEST_POLICY) \
			grant $(TEST_POLICY_ACTION) to $(TEST_ROLE) on "$$resource" || :; \
	echo "Athenz role=$(TEST_ROLE) policy=$(TEST_POLICY)"; \
	echo "  member: $(ATHENZ_SERVICE_DOMAIN).$$src_id"; \
	echo "  resource: $$resource"

configure-benchmark-athenz-policy:
	@vegeta_pod="$$( $(CILIUM_KUBECTL) -n $(BENCH_NAMESPACE) get pod -l $(BENCH_VEGETA_LABEL) -o jsonpath='{.items[0].metadata.name}' )"; \
	test -n "$$vegeta_pod" || { echo "missing vegeta pod"; exit 1; }; \
	src_id="$$($(CILIUM_KUBECTL) -n $(BENCH_NAMESPACE) get ciliumendpoint $$vegeta_pod -o jsonpath='{.status.identity.id}')"; \
	dst_id="$$($(CILIUM_KUBECTL) -n $(BENCH_NAMESPACE) get ciliumendpoint $(BENCH_AUTH_ECHO_POD) -o jsonpath='{.status.identity.id}')"; \
	test -n "$$src_id" || { echo 'missing benchmark source cilium identity'; exit 1; }; \
	test -n "$$dst_id" || { echo 'missing benchmark destination cilium identity'; exit 1; }; \
	resource="$(ATHENZ_SERVICE_DOMAIN):service.$$dst_id:$(BENCH_POLICY_PORT)$(BENCH_POLICY_PATH)"; \
	echo "configure Athenz benchmark policy: cilium.$$src_id -> cilium.$$dst_id"; \
	for service_id in "$$src_id" "$$dst_id"; do \
		i=0; \
		while true; do \
			if $(ATHENZ_KUBECTL) -n athenz exec $(ATHENZ_CLI_DEPLOYMENT) -- \
				curl -sf \
					--key /var/run/athenz/athenz_admin.private.pem \
					--cert /var/run/athenz/athenz_admin.cert.pem \
					"https://athenz-zms-server.athenz:4443/zms/v1/domain/$(ATHENZ_SERVICE_DOMAIN)/service/$$service_id" >/dev/null; then \
				break; \
			fi; \
			i=$$((i + 1)); \
			if [ $$i -ge 60 ]; then \
				echo "timed out waiting for Athenz service $(ATHENZ_SERVICE_DOMAIN).$$service_id"; \
				exit 1; \
			fi; \
			sleep 2; \
		done; \
	done; \
	$(ATHENZ_KUBECTL) -n athenz exec $(ATHENZ_CLI_DEPLOYMENT) -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			delete-policy \
			$(BENCH_POLICY) || :; \
	$(ATHENZ_KUBECTL) -n athenz exec $(ATHENZ_CLI_DEPLOYMENT) -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			add-regular-role \
			$(BENCH_ROLE) \
			$(ATHENZ_SERVICE_DOMAIN).$$src_id || :; \
	$(ATHENZ_KUBECTL) -n athenz exec $(ATHENZ_CLI_DEPLOYMENT) -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			add-member \
			$(BENCH_ROLE) \
			$(ATHENZ_SERVICE_DOMAIN).$$src_id || :; \
	$(ATHENZ_KUBECTL) -n athenz exec $(ATHENZ_CLI_DEPLOYMENT) -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			add-policy \
			$(BENCH_POLICY) \
			grant $(BENCH_POLICY_ACTION) to $(BENCH_ROLE) on "$$resource" || :; \
	$(ATHENZ_KUBECTL) -n athenz exec $(ATHENZ_CLI_DEPLOYMENT) -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			add-assertion \
			$(BENCH_POLICY) \
			grant $(BENCH_POLICY_ACTION) to $(BENCH_ROLE) on "$$resource" || :; \
	echo "Athenz role=$(BENCH_ROLE) policy=$(BENCH_POLICY)"; \
	echo "  member: $(ATHENZ_SERVICE_DOMAIN).$$src_id"; \
	echo "  resource: $$resource"

deploy-test-workload: apply-test-workload wait-test-workload configure-test-athenz-policy
	@echo "test workload deployed"; \
	echo "verify with:"; \
	echo "  $(CILIUM_KUBECTL) -n $(TEST_NAMESPACE) exec $(TEST_CLIENT_POD) -- curl -s -o /dev/null -w '%{http_code}\n' http://echo:$(TEST_POLICY_PORT)/headers"

deploy-benchmark-workload: apply-benchmark-workload wait-benchmark-workload configure-benchmark-athenz-policy
	@echo "benchmark workload deployed"; \
	echo "run with:"; \
	echo "  $(MAKE) -C athenz-cilium run-benchmark ATHENZ_CONTEXT=$(ATHENZ_CONTEXT) CILIUM_CONTEXT=$(CILIUM_CONTEXT)"

run-benchmark:
	@printf '\n===== benchmark: plain =====\n'; \
	$(CILIUM_KUBECTL) -n $(BENCH_NAMESPACE) exec deployment/$(BENCH_VEGETA_DEPLOYMENT) -- /bin/sh -c \
		"echo 'GET http://$(BENCH_PLAIN_SERVICE):$(BENCH_POLICY_PORT)$(BENCH_POLICY_PATH)' \
		| vegeta attack -workers=$(BENCH_WORKERS) -rate=$(BENCH_RATE) -duration=$(BENCH_DURATION) -keepalive $(BENCH_KEEPALIVE) \
		| tee /data/plain.bin | vegeta report"; \
	printf '\n===== benchmark: auth =====\n'; \
	$(CILIUM_KUBECTL) -n $(BENCH_NAMESPACE) exec deployment/$(BENCH_VEGETA_DEPLOYMENT) -- /bin/sh -c \
		"echo 'GET http://$(BENCH_AUTH_SERVICE):$(BENCH_POLICY_PORT)$(BENCH_POLICY_PATH)' \
		| vegeta attack -workers=$(BENCH_WORKERS) -rate=$(BENCH_RATE) -duration=$(BENCH_DURATION) -keepalive $(BENCH_KEEPALIVE) \
		| tee /data/auth.bin | vegeta report"

MULTI_POLICY_SRC_ID ?=
MULTI_POLICY_DST_ID ?=
MULTI_POLICY_ROLE ?=
MULTI_POLICY_NAME ?=
MULTI_POLICY_ACTION ?= GET
MULTI_POLICY_PORT ?= 3000
MULTI_POLICY_PATH ?= /headers

configure-multi-cluster-test-athenz-policy:
	@test -n "$(CILIUM1_CONTEXT)" || { echo 'missing CILIUM1_CONTEXT'; exit 1; }
	@test -n "$(CILIUM2_CONTEXT)" || { echo 'missing CILIUM2_CONTEXT'; exit 1; }
	@src_id="$$($(KUBECTL) --context $(CILIUM1_CONTEXT) -n $(TEST_NAMESPACE) get ciliumendpoint $(TEST_CLIENT_POD) -o jsonpath='{.status.identity.id}')"; \
	dst_id="$$($(KUBECTL) --context $(CILIUM2_CONTEXT) -n $(TEST_NAMESPACE) get ciliumendpoint $(TEST_ECHO_POD) -o jsonpath='{.status.identity.id}')"; \
	test -n "$$src_id" || { echo 'missing source cilium identity (cluster1)'; exit 1; }; \
	test -n "$$dst_id" || { echo 'missing destination cilium identity (cluster2)'; exit 1; }; \
	$(MAKE) apply-multi-cluster-athenz-policy \
		MULTI_POLICY_SRC_ID="$$src_id" \
		MULTI_POLICY_DST_ID="$$dst_id" \
		MULTI_POLICY_ROLE=$(TEST_ROLE) \
		MULTI_POLICY_NAME=$(TEST_POLICY) \
		MULTI_POLICY_ACTION=$(TEST_POLICY_ACTION) \
		MULTI_POLICY_PORT=$(TEST_POLICY_PORT) \
		MULTI_POLICY_PATH=$(TEST_POLICY_PATH)

configure-multi-cluster-benchmark-athenz-policy:
	@test -n "$(CILIUM1_CONTEXT)" || { echo 'missing CILIUM1_CONTEXT'; exit 1; }
	@test -n "$(CILIUM2_CONTEXT)" || { echo 'missing CILIUM2_CONTEXT'; exit 1; }
	@vegeta_pod="$$( $(KUBECTL) --context $(CILIUM1_CONTEXT) -n $(BENCH_NAMESPACE) get pod -l $(BENCH_VEGETA_LABEL) -o jsonpath='{.items[0].metadata.name}' )"; \
	test -n "$$vegeta_pod" || { echo "missing vegeta pod"; exit 1; }; \
	src_id="$$($(KUBECTL) --context $(CILIUM1_CONTEXT) -n $(BENCH_NAMESPACE) get ciliumendpoint $$vegeta_pod -o jsonpath='{.status.identity.id}')"; \
	dst_id="$$($(KUBECTL) --context $(CILIUM2_CONTEXT) -n $(BENCH_NAMESPACE) get ciliumendpoint $(BENCH_AUTH_ECHO_POD) -o jsonpath='{.status.identity.id}')"; \
	test -n "$$src_id" || { echo 'missing benchmark source cilium identity (cluster1)'; exit 1; }; \
	test -n "$$dst_id" || { echo 'missing benchmark destination cilium identity (cluster2)'; exit 1; }; \
	$(MAKE) apply-multi-cluster-athenz-policy \
		MULTI_POLICY_SRC_ID="$$src_id" \
		MULTI_POLICY_DST_ID="$$dst_id" \
		MULTI_POLICY_ROLE=$(BENCH_ROLE) \
		MULTI_POLICY_NAME=$(BENCH_POLICY) \
		MULTI_POLICY_ACTION=$(BENCH_POLICY_ACTION) \
		MULTI_POLICY_PORT=$(BENCH_POLICY_PORT) \
		MULTI_POLICY_PATH=$(BENCH_POLICY_PATH)

apply-multi-cluster-athenz-policy:
	@test -n "$(MULTI_POLICY_SRC_ID)" || { echo 'missing MULTI_POLICY_SRC_ID'; exit 1; }
	@test -n "$(MULTI_POLICY_DST_ID)" || { echo 'missing MULTI_POLICY_DST_ID'; exit 1; }
	@resource="$(ATHENZ_SERVICE_DOMAIN):service.$(MULTI_POLICY_DST_ID):$(MULTI_POLICY_PORT)$(MULTI_POLICY_PATH)"; \
	echo "configure multi-cluster Athenz policy: cilium.$(MULTI_POLICY_SRC_ID) -> cilium.$(MULTI_POLICY_DST_ID)"; \
	for service_id in "$(MULTI_POLICY_SRC_ID)" "$(MULTI_POLICY_DST_ID)"; do \
		i=0; \
		while true; do \
			if $(ATHENZ_KUBECTL) -n athenz exec $(ATHENZ_CLI_DEPLOYMENT) -- \
				curl -sf \
					--key /var/run/athenz/athenz_admin.private.pem \
					--cert /var/run/athenz/athenz_admin.cert.pem \
					"https://athenz-zms-server.athenz:4443/zms/v1/domain/$(ATHENZ_SERVICE_DOMAIN)/service/$$service_id" >/dev/null; then \
				break; \
			fi; \
			i=$$((i + 1)); \
			if [ $$i -ge 60 ]; then \
				echo "timed out waiting for Athenz service $(ATHENZ_SERVICE_DOMAIN).$$service_id"; \
				exit 1; \
			fi; \
			sleep 2; \
		done; \
	done; \
	$(ATHENZ_KUBECTL) -n athenz exec $(ATHENZ_CLI_DEPLOYMENT) -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			delete-policy \
			$(MULTI_POLICY_NAME) || :; \
	$(ATHENZ_KUBECTL) -n athenz exec $(ATHENZ_CLI_DEPLOYMENT) -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			add-regular-role \
			$(MULTI_POLICY_ROLE) \
			$(ATHENZ_SERVICE_DOMAIN).$(MULTI_POLICY_SRC_ID) || :; \
	$(ATHENZ_KUBECTL) -n athenz exec $(ATHENZ_CLI_DEPLOYMENT) -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			add-member \
			$(MULTI_POLICY_ROLE) \
			$(ATHENZ_SERVICE_DOMAIN).$(MULTI_POLICY_SRC_ID) || :; \
	$(ATHENZ_KUBECTL) -n athenz exec $(ATHENZ_CLI_DEPLOYMENT) -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			add-policy \
			$(MULTI_POLICY_NAME) \
			grant $(MULTI_POLICY_ACTION) to $(MULTI_POLICY_ROLE) on "$$resource" || :; \
	$(ATHENZ_KUBECTL) -n athenz exec $(ATHENZ_CLI_DEPLOYMENT) -- \
		zms-cli \
			-z https://athenz-zms-server.athenz:4443/zms/v1 \
			-key /var/run/athenz/athenz_admin.private.pem \
			-cert /var/run/athenz/athenz_admin.cert.pem \
			-d $(ATHENZ_SERVICE_DOMAIN) \
			add-assertion \
			$(MULTI_POLICY_NAME) \
			grant $(MULTI_POLICY_ACTION) to $(MULTI_POLICY_ROLE) on "$$resource" || :; \
	echo "  role=$(MULTI_POLICY_ROLE) policy=$(MULTI_POLICY_NAME)"; \
	echo "  member: $(ATHENZ_SERVICE_DOMAIN).$(MULTI_POLICY_SRC_ID)"; \
	echo "  resource: $$resource"

clean-test-workload:
	@test -f "$(TEST_WORKLOAD_FILE)" || { echo "missing $(TEST_WORKLOAD_FILE)"; exit 1; }
	$(CILIUM_KUBECTL) delete -f "$(TEST_WORKLOAD_FILE)" --ignore-not-found

clean-benchmark-workload:
	@test -f "$(BENCHMARK_WORKLOAD_FILE)" || { echo "missing $(BENCHMARK_WORKLOAD_FILE)"; exit 1; }
	$(CILIUM_KUBECTL) delete -f "$(BENCHMARK_WORKLOAD_FILE)" --ignore-not-found
