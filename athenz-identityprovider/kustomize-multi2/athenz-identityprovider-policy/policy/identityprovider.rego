package identityprovider

import data.config.constraints.athenz.domain.name as athenz_domain_name
import data.config.constraints.athenz.domain.prefix as athenz_domain_prefix
import data.config.constraints.athenz.domain.suffix as athenz_domain_suffix
import data.config.constraints.athenz.namespace.trimprefix as athenz_namespace_trimprefix
import data.config.constraints.athenz.namespace.trimsuffix as athenz_namespace_trimsuffix
import data.config.constraints.athenz.identityprovider.service as expected_athenz_provider
import data.config.constraints.cert.expiry.maxminutes as cert_expiry_time_max
import data.config.constraints.cert.expiry.defaultminutes as cert_expiry_time_default
import data.config.constraints.cert.refresh as cert_refresh_default
import data.config.constraints.cert.sandns as expected_cert_sandns
import data.config.constraints.keys.jwks.url as jwks_url
import data.config.constraints.keys.jwks.force_cache_duration_seconds as jwks_force_cache_duration_seconds
import data.config.constraints.keys.apinodes.url as api_node_url
import data.config.constraints.keys.static as public_key
import data.config.constraints.kubernetes.namespaces as expected_namespaces
import data.config.constraints.kubernetes.serviceaccount.names as expected_serviceaccounts
import data.config.debug
import data.kubernetes.pods

import future.keywords.every

log(prefix, value) = true {
    debug
    prefix
    value
    print("Debug identityprovider.rego:", sprintf("%s: %v", [prefix, value]))
} else = true

raw_attestation := object.get(input, "attestationData", "")

parsed_attestation := parsed {
    raw_attestation != ""
    parsed := json.unmarshal(raw_attestation)
    is_object(parsed)
} else = {}

attestation_mode := "cilium-identity" {
    object.get(parsed_attestation, "mode", "") == "cilium-identity"
} else = "service-account-jwt"

service_account_jwt := token {
    attestation_mode == "cilium-identity"
    token := object.get(parsed_attestation, "delegateToken", "")
} else = raw_attestation

unverified_jwt := decoded_jwt {
    decoded_jwt := io.jwt.decode(service_account_jwt)
} else = [{}, {}]

keys := raw_jwks {
    raw_jwks := http.send({
        "url": jwks_url,
        "method": "GET",
        "force_cache": (jwks_force_cache_duration_seconds > 0),
        "force_cache_duration_seconds": jwks_force_cache_duration_seconds,
    }).raw_body
    jwks := json.unmarshal(raw_jwks)
    jwks.keys[_].kid == unverified_jwt[0].kid
    log("Key ID matched in JWKs", sprintf("JWT kid:%s, JWK Set:%s", [unverified_jwt[0].kid, json.marshal(jwks)]))
} else := raw_jwks {
    raw_node_list := http.send({
        "url": api_node_url,
        "method": "GET",
    }).raw_body
    node_list := json.unmarshal(raw_node_list)
    node_list.items[i].status.addresses[j].type == "InternalIP"
    node_jwks_url := sprintf("https://%s/openid/v1/jwks", [node_list.items[i].status.addresses[j].address])
    log("Querying each Node URL", node_jwks_url)
    raw_jwks := http.send({
        "url": node_jwks_url,
        "method": "GET",
        "tls_insecure_skip_verify": true,
    }).raw_body
    jwks := json.unmarshal(raw_jwks)
    jwks.keys[_].kid == unverified_jwt[0].kid
    log("Key ID matched in JWKs", sprintf("Node:%s, JWT kid:%s, JWK Set:%s", [node_jwks_url, unverified_jwt[0].kid, json.marshal(jwks)]))
} else = public_key {
    log("Failed to retrieve JWKs. Using the default public_key:", json.marshal(public_key))
}

service_account_token_config := object.get(object.get(object.get(data.config.constraints, "kubernetes", {}), "serviceaccount", {}), "token", {})

service_account_token_issuers := issuers {
    issuers := object.get(service_account_token_config, "issuers", [])
    count(issuers) > 0
} else = [issuer] {
    issuer := object.get(service_account_token_config, "issuer", "")
    issuer != ""
} else = []

service_account_token_audiences := audiences {
    audiences := object.get(service_account_token_config, "audiences", [])
    count(audiences) > 0
} else = [audience] {
    audience := object.get(service_account_token_config, "audience", "")
    audience != ""
} else = []

constraints := {
    "cert": keys,
} {
    keys
}

verified_jwt := decoded {
    keys
    issuer := service_account_token_issuers[_]
    audience := service_account_token_audiences[_]
    decoded := io.jwt.decode_verify(service_account_jwt, {
        "cert": keys,
        "iss": issuer,
        "aud": audience,
    })
    decoded[0] == true
} else = decoded {
    keys
    issuer := service_account_token_issuers[_]
    count(service_account_token_audiences) == 0
    decoded := io.jwt.decode_verify(service_account_jwt, {
        "cert": keys,
        "iss": issuer,
    })
    decoded[0] == true
} else = decoded {
    keys
    count(service_account_token_issuers) == 0
    audience := service_account_token_audiences[_]
    decoded := io.jwt.decode_verify(service_account_jwt, {
        "cert": keys,
        "aud": audience,
    })
    decoded[0] == true
} else = decoded {
    decoded := io.jwt.decode_verify(service_account_jwt, constraints)
    decoded[0] == true
} else = [false, {}, {}] {
    constraints
}

jwt_kubernetes_claim := extracted_claim {
    extracted_claim := object.get(verified_jwt[2], "kubernetes.io", {})
} else = {}

jwt_claim_issuer := object.get(verified_jwt[2], "iss", "")

jwt_claim_audiences := audiences {
    aud := object.get(verified_jwt[2], "aud", [])
    is_array(aud)
    audiences := aud
} else = [aud] {
    aud := object.get(verified_jwt[2], "aud", "")
    is_string(aud)
    aud != ""
} else = []

issuer_attestation := true {
    count(service_account_token_issuers) == 0
} else = true {
    service_account_token_issuers[_] == jwt_claim_issuer
}

audience_attestation := true {
    count(service_account_token_audiences) == 0
} else = true {
    service_account_token_audiences[_] == jwt_claim_audiences[_]
}

expected_athenz_domain := concat("", [athenz_domain_prefix, athenz_domain_name, athenz_domain_suffix]) {
    athenz_domain_name != ""
} else = concat("", [athenz_domain_prefix, trimed_namespace, athenz_domain_suffix]) {
    jwt_kubernetes_claim.namespace
    some phrase in [athenz_namespace_trimprefix, athenz_namespace_trimsuffix]
    phrase != ""
    trimed_namespace := trim_suffix(trim_prefix(jwt_kubernetes_claim.namespace, athenz_namespace_trimprefix), athenz_namespace_trimsuffix)
} else = concat("", [athenz_domain_prefix, jwt_kubernetes_claim.namespace, athenz_domain_suffix]) {
    jwt_kubernetes_claim.namespace
}

namespace_attestation := true {
    count(expected_namespaces) > 0
    expected_namespaces[_] == jwt_kubernetes_claim.namespace
} else = true {
    count(expected_namespaces) == 0
}

serviceaccount_attestation := true {
    count(expected_serviceaccounts) > 0
    expected_serviceaccounts[_] == jwt_kubernetes_claim.serviceaccount.name
} else = true {
    count(expected_serviceaccounts) == 0
}

sandns_attestation := true {
    count(expected_cert_sandns) > 0
    sandns := split(object.get(object.get(input, "attributes", {}), "sanDNS", ""), ",")
    every dns in sandns {
        glob.match(expected_cert_sandns[_].glob, [], dns)
    }
} else = true {
    count(expected_cert_sandns) == 0
}

pod_identity_attestation(pod) {
    pod_metadata := object.get(pod, "metadata", {})
    pod_spec := object.get(pod, "spec", {})
    jwt_kubernetes_claim.namespace == object.get(pod_metadata, "namespace", "")
    jwt_kubernetes_claim.pod.uid == object.get(pod_metadata, "uid", "")
    jwt_kubernetes_claim.serviceaccount.name == object.get(pod_spec, "serviceAccountName", "")
}

pod_network_attestation(pod) {
    requested_san_ip := object.get(object.get(input, "attributes", {}), "sanIP", "")
    pod_status := object.get(pod, "status", {})
    requested_san_ip == object.get(pod_status, "podIP", "")
} else {
    requested_san_ip := object.get(object.get(input, "attributes", {}), "sanIP", "")
    pod_spec := object.get(pod, "spec", {})
    pod_status := object.get(pod, "status", {})
    object.get(pod_spec, "hostNetwork", false)
    requested_san_ip == object.get(pod_status, "hostIP", "")
}

attestated_pod := pod {
    namespace_pods := object.get(pods, jwt_kubernetes_claim.namespace, {})
    pod := object.get(namespace_pods, jwt_kubernetes_claim.pod.name, {})
    pod_identity_attestation(pod)
    pod_network_attestation(pod)
} else = pod {
    raw_pod := http.send({
        "url": sprintf("http://127.0.0.1:8001/api/v1/namespaces/%s/pods/%s", [jwt_kubernetes_claim.namespace, jwt_kubernetes_claim.pod.name]),
        "method": "GET",
    }).raw_body
    pod := json.unmarshal(raw_pod)
    pod_identity_attestation(pod)
    pod_network_attestation(pod)
} else = false

delegated_identity := object.get(parsed_attestation, "identity", "")
delegated_pod := object.get(parsed_attestation, "pod", {})
delegated_endpoint := object.get(parsed_attestation, "endpoint", {})
delegated_pod_namespace := object.get(delegated_pod, "namespace", "")
delegated_pod_name := object.get(delegated_pod, "name", "")
delegated_pod_uid := object.get(delegated_pod, "uid", "")
delegated_pod_ip := object.get(delegated_pod, "ip", "")
delegated_endpoint_name := name {
    name := object.get(delegated_endpoint, "name", "")
    name != ""
} else = delegated_pod_name {
    delegated_pod_name != ""
}

delegated_pod_identity_attestation(pod) {
    pod_metadata := object.get(pod, "metadata", {})
    delegated_pod_namespace == object.get(pod_metadata, "namespace", "")
    delegated_pod_name == object.get(pod_metadata, "name", "")
    delegated_pod_uid == object.get(pod_metadata, "uid", "")
}

delegated_pod_network_attestation(pod) {
    delegated_pod_ip != ""
    delegated_pod_ip == object.get(object.get(pod, "status", {}), "podIP", "")
} else {
    delegated_pod_ip != ""
    object.get(object.get(pod, "spec", {}), "hostNetwork", false)
    delegated_pod_ip == object.get(object.get(pod, "status", {}), "hostIP", "")
}

attestated_delegated_pod := pod {
    delegated_pod_namespace != ""
    delegated_pod_name != ""
    namespace_pods := object.get(pods, delegated_pod_namespace, {})
    pod := object.get(namespace_pods, delegated_pod_name, {})
    delegated_pod_identity_attestation(pod)
    delegated_pod_network_attestation(pod)
} else = pod {
    delegated_pod_namespace != ""
    delegated_pod_name != ""
    raw_pod := http.send({
        "url": sprintf("http://127.0.0.1:8001/api/v1/namespaces/%s/pods/%s", [delegated_pod_namespace, delegated_pod_name]),
        "method": "GET",
    }).raw_body
    pod := json.unmarshal(raw_pod)
    delegated_pod_identity_attestation(pod)
    delegated_pod_network_attestation(pod)
} else = false

attestated_cilium_identity := cilium_identity {
    attestation_mode == "cilium-identity"
    delegated_identity != ""
    raw_identity := http.send({
        "url": sprintf("http://127.0.0.1:8001/apis/cilium.io/v2/ciliumidentities/%s", [delegated_identity]),
        "method": "GET",
    }).raw_body
    cilium_identity := json.unmarshal(raw_identity)
    object.get(object.get(cilium_identity, "metadata", {}), "name", "") == delegated_identity
} else = false

endpoint_network_attestation(cep) {
    delegated_pod_ip != ""
    addressing := object.get(object.get(object.get(cep, "status", {}), "networking", {}), "addressing", [])
    some i
    object.get(addressing[i], "ipv4", "") == delegated_pod_ip
} else {
    delegated_pod_ip != ""
    addressing := object.get(object.get(object.get(cep, "status", {}), "networking", {}), "addressing", [])
    some i
    object.get(addressing[i], "ipv6", "") == delegated_pod_ip
}

attestated_cilium_endpoint := cep {
    attestation_mode == "cilium-identity"
    delegated_pod_namespace != ""
    delegated_endpoint_name != ""
    delegated_identity != ""
    raw_cep := http.send({
        "url": sprintf("http://127.0.0.1:8001/apis/cilium.io/v2/namespaces/%s/ciliumendpoints/%s", [delegated_pod_namespace, delegated_endpoint_name]),
        "method": "GET",
    }).raw_body
    cep := json.unmarshal(raw_cep)
    object.get(object.get(cep, "metadata", {}), "namespace", "") == delegated_pod_namespace
    to_number(delegated_identity) == object.get(object.get(object.get(cep, "status", {}), "identity", {}), "id", -1)
    endpoint_network_attestation(cep)
} else = false

delegated_state_attestation {
    attestated_delegated_pod != false
    attestated_cilium_identity != false
    attestated_cilium_endpoint != false
}

cert_expiry_time := cert_expiry {
    input.attributes.certExpiryTime <= cert_expiry_time_max
    cert_expiry := input.attributes.certExpiryTime
} else = cert_expiry {
    input.attributes.certExpiryTime > cert_expiry_time_max
    cert_expiry := cert_expiry_time_max
} else = cert_expiry_time_default

instance := response
refresh := response

response = {
    "domain": input.domain,
    "service": input.service,
    "provider": input.provider,
    "attributes": {
        "instanceId": input.attributes.instanceId,
        "sanIP": input.attributes.sanIP,
        "clientIP": input.attributes.clientIP,
        "sanURI": input.attributes.sanURI,
        "sanDNS": input.attributes.sanDNS,
        "certExpiryTime": cert_expiry_time,
        "certRefresh": cert_refresh_default,
    },
} {
    verified_jwt[0] == true
    issuer_attestation
    audience_attestation
    input.domain == expected_athenz_domain
    input.service == jwt_kubernetes_claim.serviceaccount.name
    input.provider == expected_athenz_provider
    namespace_attestation
    serviceaccount_attestation
    sandns_attestation
    attestated_pod != false
} else = {
    "domain": input.domain,
    "service": input.service,
    "provider": input.provider,
    "attributes": {
        "instanceId": input.attributes.instanceId,
        "sanIP": input.attributes.sanIP,
        "clientIP": input.attributes.clientIP,
        "sanURI": input.attributes.sanURI,
        "sanDNS": input.attributes.sanDNS,
        "certExpiryTime": cert_expiry_time,
        "certRefresh": cert_refresh_default,
    },
} {
    attestation_mode == "cilium-identity"
    verified_jwt[0] == true
    issuer_attestation
    audience_attestation
    input.domain == expected_athenz_domain
    input.provider == expected_athenz_provider
    namespace_attestation
    serviceaccount_attestation
    sandns_attestation
    delegated_identity != ""
    input.service == delegated_identity
    delegated_state_attestation
} else = {
    "allow": false,
    "status": {
        "reason": "empty input",
    },
} {
    not input
    log("response", "empty input")
} else = {
    "allow": false,
    "status": {
        "reason": "empty input: empty attestation data",
    },
} {
    raw_attestation == ""
    log("response", "empty input: empty attestation data")
} else = {
    "allow": false,
    "status": {
        "reason": sprintf("invalid jwt: failed to verify the service account token signature: claims[%v], constraints[%v]", [unverified_jwt[1], constraints]),
    },
} {
    verified_jwt[0] == false
    log("response", sprintf("invalid jwt: failed to verify the service account token signature: claims[%v], constraints[%v]", [unverified_jwt[1], constraints]))
} else = {
    "allow": false,
    "status": {
        "reason": sprintf("invalid jwt claims: iss[%v] aud[%v] expected_issuers[%v] expected_audiences[%v]", [jwt_claim_issuer, jwt_claim_audiences, service_account_token_issuers, service_account_token_audiences]),
    },
} {
    verified_jwt[0] == true
    not issuer_attestation
} else = {
    "allow": false,
    "status": {
        "reason": sprintf("invalid jwt claims: iss[%v] aud[%v] expected_issuers[%v] expected_audiences[%v]", [jwt_claim_issuer, jwt_claim_audiences, service_account_token_issuers, service_account_token_audiences]),
    },
} {
    verified_jwt[0] == true
    issuer_attestation
    not audience_attestation
} else = {
    "allow": false,
    "status": {
        "reason": sprintf("invalid input: input athenz provider service mismatched: input[%v], configuration[%v]", [object.get(input, "provider", ""), expected_athenz_provider]),
    },
} {
    input.provider != expected_athenz_provider
    log("response", sprintf("invalid input: input athenz provider service mismatched: input[%v], configuration[%v]", [object.get(input, "provider", ""), expected_athenz_provider]))
} else = {
    "allow": false,
    "status": {
        "reason": sprintf("invalid input: input athenz domain mismatched: input[%v], configuration[%v]", [object.get(input, "domain", ""), expected_athenz_domain]),
    },
} {
    input.domain != expected_athenz_domain
    log("response", sprintf("invalid input: input athenz domain mismatched: input[%v], configuration[%v]", [object.get(input, "domain", ""), expected_athenz_domain]))
} else = {
    "allow": false,
    "status": {
        "reason": sprintf("invalid input: input athenz service mismatched: input[%v], token_claims[%v]", [object.get(input, "service", ""), jwt_kubernetes_claim]),
    },
} {
    attestation_mode != "cilium-identity"
    input.service != jwt_kubernetes_claim.serviceaccount.name
    log("response", sprintf("invalid input: input athenz service mismatched: input[%v], token_claims[%v]", [object.get(input, "service", ""), jwt_kubernetes_claim]))
} else = {
    "allow": false,
    "status": {
        "reason": sprintf("invalid delegated input: target service and cilium identity mismatched: service[%v], identity[%v]", [object.get(input, "service", ""), delegated_identity]),
    },
} {
    attestation_mode == "cilium-identity"
    input.service != delegated_identity
    log("response", sprintf("invalid delegated input: target service and cilium identity mismatched: service[%v], identity[%v]", [object.get(input, "service", ""), delegated_identity]))
} else = {
    "allow": false,
    "status": {
        "reason": sprintf("invalid input: input attributes mismatched: input[%v], kube-apiserver[%v]", [object.get(input, "attributes", ""), attestated_pod]),
    },
} {
    attestation_mode != "cilium-identity"
    attestated_pod == false
    log("response", sprintf("invalid input: input attributes mismatched: input[%v], kube-apiserver[%v]", [object.get(input, "attributes", ""), attestated_pod]))
} else = {
    "allow": false,
    "status": {
        "reason": sprintf("invalid delegated input: cilium identity or pod/endpoint state mismatched: identity[%v], pod[%v], cep[%v]", [attestated_cilium_identity, attestated_delegated_pod, attestated_cilium_endpoint]),
    },
} {
    attestation_mode == "cilium-identity"
    not delegated_state_attestation
    log("response", sprintf("invalid delegated input: cilium identity or pod/endpoint state mismatched: identity[%v], pod[%v], cep[%v]", [attestated_cilium_identity, attestated_delegated_pod, attestated_cilium_endpoint]))
} else = {
    "allow": false,
    "status": {
        "reason": "no matching validations found",
    },
} {
    log("response", "no matching validations found")
    log("data.config", data.config)
    log("input", input)
    log("constraints", constraints)
    log("unverified_jwt", unverified_jwt)
    log("jwt_kubernetes_claim", jwt_kubernetes_claim)
    log("attestated_pod", attestated_pod)
    log("attestated_delegated_pod", attestated_delegated_pod)
    log("attestated_cilium_identity", attestated_cilium_identity)
    log("attestated_cilium_endpoint", attestated_cilium_endpoint)
}
