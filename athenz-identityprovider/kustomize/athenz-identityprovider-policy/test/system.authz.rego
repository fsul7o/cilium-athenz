package system.authz

import data.mock.instance.input as mock_input
import data.invalid.instance.input as invalid_input
#import data.mock.pem.public as mock_public_key
import data.mock.jwks_url as mock_jwks_url
import data.mock.jwks.public as mock_jwks_public
import data.mock.jwt_api_node as mock_jwt_api_node
import data.mock.api_node_url as mock_api_node_url
import data.mock.pods as mock_pods

test_default {
    allow == false
}

test_instance {
    allow == true
    with input as {
        "path": ["v0", "data", "identityprovider", "instance"],
        "method": "POST",
        "identity": {},
    }
}

test_refresh {
    allow == true
    with input as {
        "path": ["v0", "data", "identityprovider", "refresh"],
        "method": "POST",
        "identity": {},
    }
}

test_pods01 {
    allow == true
    with input as {
        "path": ["v1", "data", "kubernetes", "pods"],
        "method": "PUT",
        "identity": mock_input.attestationData,
    }
    with data.config.constraints.system.authz.keys.jwks.url as mock_jwks_url
}

test_pods02 {
    allow == true
    with input as {
        "path": ["v1", "data", "kubernetes", "pods"],
        "method": "PUT",
        "identity": mock_jwt_api_node,
    }
    with data.config.constraints.system.authz.keys.apinodes.url as mock_api_node_url
}

test_pods03 {
    allow == true
    with input as {
        "path": ["v1", "data", "kubernetes", "pods"],
        "method": "PUT",
        "identity": mock_input.attestationData,
    }
    with data.config.constraints.keys.static as mock_jwks_public
}

test_pods04 {
    allow == false
    with input as {
        "path": ["v1", "data", "kubernetes", "pods"],
        "method": "PUT",
        "identity": "invalid jwt",
    }
}

test_data {
    allow == true
    with input as {
        "path": ["v1", "data"],
        "method": "PATCH",
        "identity": mock_input.attestationData,
    }
    with data.config.constraints.system.authz.keys.jwks.url as mock_jwks_url
}

test_health {
    allow == true
    with input as {
        "path": ["health"],
        "method": "GET",
        "identity": {},
    }
    with data.kubernetes.pods as mock_pods
}

test_metrics {
    allow == true
    with input as {
        "path": ["metrics"],
        "method": "GET",
        "identity": {},
    }
}

# with debug enabled
test_debug1 {
    log("key", "value")
    with data.config.debug as true
}

# with debug disabled
test_debug2 {
    log("key", "value")
    with data.config.debug as false
}
