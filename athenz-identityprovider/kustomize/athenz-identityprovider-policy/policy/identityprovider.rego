package identityprovider

import data.config.constraints.cert.expiry.maxminutes as cert_expiry_time_max
import data.config.constraints.cert.expiry.defaultminutes as cert_expiry_time_default
import data.config.constraints.cert.refresh as cert_refresh_default

cert_expiry_time := cert_expiry {
    requested := object.get(object.get(input, "attributes", {}), "certExpiryTime", cert_expiry_time_default)
    requested <= cert_expiry_time_max
    cert_expiry := requested
} else = cert_expiry {
    requested := object.get(object.get(input, "attributes", {}), "certExpiryTime", cert_expiry_time_default)
    requested > cert_expiry_time_max
    cert_expiry := cert_expiry_time_max
} else = cert_expiry_time_default

instance := response
refresh := response

response := {
    "domain": domain,
    "service": service,
    "provider": provider,
    "attributes": {
        "instanceId": object.get(attributes, "instanceId", ""),
        "sanIP": object.get(attributes, "sanIP", ""),
        "clientIP": object.get(attributes, "clientIP", ""),
        "sanURI": object.get(attributes, "sanURI", ""),
        "sanDNS": object.get(attributes, "sanDNS", ""),
        "certExpiryTime": cert_expiry_time,
        "certRefresh": cert_refresh_default,
    },
} {
    domain := object.get(input, "domain", "")
    service := object.get(input, "service", "")
    provider := object.get(input, "provider", "")
    attributes := object.get(input, "attributes", {})

    domain != ""
    service != ""
    provider != ""
}

response := {
    "allow": false,
    "status": {
        "reason": "missing required input",
    },
} {
    object.get(input, "domain", "") == ""
} else := {
    "allow": false,
    "status": {
        "reason": "missing required input",
    },
} {
    object.get(input, "service", "") == ""
} else := {
    "allow": false,
    "status": {
        "reason": "missing required input",
    },
} {
    object.get(input, "provider", "") == ""
}
