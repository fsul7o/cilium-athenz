package system.authz

import data.config.constraints.keys.jwks.cacert as jwks_cacert_file
import data.config.constraints.keys.jwks.force_cache_duration_seconds as jwks_force_cache_duration_seconds
import data.config.constraints.keys.static as public_key
import data.config.constraints.kubernetes.serviceaccount.token.issuer as service_account_token_issuer
import data.config.constraints.kubernetes.serviceaccount.token.audience as service_account_token_audience
import data.config.debug
import data.kubernetes.pods

# Administrative writes into OPA are performed by sidecars running in the same pod.
# Those requests carry the local cluster service account token, so their JWTs must
# be validated against the local cluster API server rather than the remote cluster.
system_authz_keys := object.get(object.get(object.get(data.config.constraints, "system", {}), "authz", {}), "keys", {})
system_authz_jwks := object.get(system_authz_keys, "jwks", {})
system_authz_jwks_url := object.get(system_authz_jwks, "url", "http://127.0.0.1:8002/openid/v1/jwks")
system_authz_api_nodes := object.get(system_authz_keys, "apinodes", {})
system_authz_api_node_url := object.get(system_authz_api_nodes, "url", "http://127.0.0.1:8002/api/v1/nodes")

# we are preparing a logger function
log(prefix, value) = true {
    debug
    prefix
    value
    print("Debug system.authz.rego:", sprintf("%s: %v", [prefix, value]))
} else = true

# first, we are extracting the identity from the input
jwt := input.identity

# if we got the identity, then we are getting the public key for jwt verification
# to get the public key, we are first decoding the jwt from identity without public key verification
unverified_jwt := decoded_jwt {
    decoded_jwt := io.jwt.decode(jwt)
}

# and then we are extracting the verification key id from the decoded jwt to figure out which public key to use for the jwt verification
keys := jwks_cached {
    jwks_cached := http.send({
        "url": system_authz_jwks_url,
        "method": "GET",
        "force_cache": (jwks_force_cache_duration_seconds > 0),
        "force_cache_duration_seconds": jwks_force_cache_duration_seconds,
    }).raw_body
    json.unmarshal(jwks_cached).keys[_].kid == unverified_jwt[0].kid 
    log("Key ID matched in JWKs", sprintf("JWT kid:%s, JWK Set:%s", [unverified_jwt[0].kid, json.marshal(jwks_cached)]))
# if we fail to retrieve the jwk set from the api, we will still try to get them from the each host
} else := jwks_each_node {
    raw_node_list := http.send({
        "url": system_authz_api_node_url,
        "method": "GET",
    }).raw_body
    node_list := json.unmarshal(raw_node_list)
    node_list.items[i].status.addresses[j].type == "InternalIP"
    node_jwks_url := sprintf("https://%s/openid/v1/jwks", [node_list.items[i].status.addresses[j].address])
    jwks_each_node := http.send({
        "url": node_jwks_url,
        "method": "GET",
        "tls_insecure_skip_verify": true,
    }).raw_body
    json.unmarshal(jwks_each_node).keys[_].kid == unverified_jwt[0].kid 
    log("Key ID matched in JWKs", sprintf("Node:%s, JWT kid:%s, JWK Set:%s", [node_jwks_url, unverified_jwt[0].kid, json.marshal(jwks_each_node)]))
# if we fail to retrieve the jwk set with the key id even reaching to the each host, we will give up and use the pre-defined static key
} else = public_key {
    log("Failed to retrieve JWKs. Using the default public_key:", json.marshal(public_key))
}

# if we got the public key, then we are preparing the constraints for the jwt verification
constraints := {
    "iss": service_account_token_issuer,
    "aud": service_account_token_audience,
    "cert": keys,
} {
    service_account_token_issuer
    service_account_token_audience
    keys
}

# after the constraints is set, we are verifying the jwt
verified_jwt := io.jwt.decode_verify(jwt, constraints)

default allow = false

allow {
    "POST" == input.method
    ["v0", "data", "identityprovider", "instance"] == input.path
}
allow {
    "POST" == input.method
    ["v0", "data", "identityprovider", "refresh"] == input.path
}

allow {
    "PUT" == input.method
    ["v1", "data", "kubernetes", "pods"] == array.slice(input.path, 0, 4)
    verified_jwt
}
allow {
    "PATCH" == input.method
    ["v1", "data"] == input.path
    verified_jwt
}

allow {
    "GET" == input.method
    ["health"] == input.path
    count(pods) > 0
}

allow {
    "GET" == input.method
    ["metrics"] == input.path
}
