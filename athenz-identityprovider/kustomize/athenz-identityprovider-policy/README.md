# athenz-identityprovider policy

## Configuration for Open Policy Agent

### [config.yaml](policy/config.yaml)

Some can be overwritten by environment variable

  | environment variable name   | config field                                                | default value | example value                                                                                               | description                                                                                                       |
  | -----                       | -----                                                       | -----         | -----                                                                                                       | -----                                                                                                             |
  | N/A                         | config.debug                                                | ``            | `true`                                                                                                      | Set `true` to enable debug logging                                                                                |
  | N/A                         | config.constraints.athenz.domain.name                       | `""`          | `"athenz"`                                                                                                  | Athenz Domain name for the identity certificates (K8s Namespace will be set implicitly if this is empty)          |
  | N/A                         | config.constraints.athenz.domain.prefix                     | `""`          | `cloud-tld.region.`                                                                                         | Athenz Domain prefix to restrict issueing identity certificates                                                   |
  | N/A                         | config.constraints.athenz.domain.suffix                     | `""`          | `.copperargos.provider`                                                                                     | Athenz Domain suffix to restrict issueing identity certificates                                                   |
  | N/A                         | config.constraints.athenz.namespace.trimprefix              | `""`          | `prefix-`                                                                                                   | Any prefix string to trim from Kubernetes Namespace to compare with the Athenz Domain in identity certificates    |
  | N/A                         | config.constraints.athenz.namespace.trimsuffix              | `""`          | `-suffix`                                                                                                   | Any suffix string to trim from Kubernetes Namespace to compare with the Athenz Domain in identity certificates    |
  | N/A                         | config.constraints.athenz.identityprovider.service          | `""`          | `identityprovider`                                                                                          | A full name of Athenz Service for the cloud provider service                                                      |
  | N/A                         | config.constraints.cert.expiry.defaultminutes               | ``            | `43200`                                                                                                     | Default certificate expiry minutes if there are no specified value from the client                                |
  | N/A                         | config.constraints.cert.expiry.maxminutes                   | ``            | `43200`                                                                                                     | Maximum certificate expiry minutes to limit the client request                                                    |
  | N/A                         | config.constraints.cert.refresh                             | ``            | `true`                                                                                                      | To allow refreshing identity certificates                                                                         |
  | N/A                         | config.constraints.cert.sandns.[].glob                      | `[]`          | `[{"glob": "*.*.svc.cluster.local"}, {"glob": "**.zts.athenz.cloud"}]`                                      | SAN DNS constraints for server certificate                                                                        |
  | N/A                         | config.constraints.keys.jwks.url                            | ``            | `http://127.0.0.1:8001/openid/v1/jwks`                                                                      | An URL to retrieve JWK Set for verifying Kubernetes Service Account Token                                         |
  | N/A                         | config.constraints.keys.jwks.cacert                         | ``            | `/var/run/secrets/kubernetes.io/serviceaccount/ca.crt`                                                      | A CA certificate file path to intract with the JWK Set endpoint                                                   |
  | N/A                         | config.constraints.keys.jwks.force_cache_duration_seconds   | ``            | `3600`                                                                                                      | Cache duration for the retrieved JWK Set (set `0` to disable caching)                                             |
  | N/A                         | config.constraints.keys.apinodes.url                        | ``            | `http://127.0.0.1:8001/api/v1/nodes`                                                                        | API Endpoint URL (most likely kube-apiserver) to retrieve JWK Set endpoints                                       |
  | N/A                         | config.constraints.keys.static                              | ``            | `""`                                                                                                        | A static keys to verify Kubernetes Service Account Token (in pem or jwks format)                                  |
  | N/A                         | config.constraints.kubernetes.namespaces                    | `[]`          | `["kube-system"]`                                                                                           | Kubernetes Namespaces to restrict accepting Kubernetes Service Account Token                                      |
  | N/A                         | config.constraints.kubernetes.serviceaccount.names          | `[]`          | `["identityprovider"]`                                                                                      | Kubernetes Service Account names to restrict accepting Kubernetes Service Account Token                           |
  | N/A                         | config.constraints.kubernetes.serviceaccount.token.issuer   | ``            | `https://kubernetes.default.svc.cluster.local`                                                              | Kubernetes Service Account issuer to restrict accepting Kubernetes Service Account Token                          |
  | N/A                         | config.constraints.kubernetes.serviceaccount.token.audience | ``            | `https://kubernetes.default.svc`                                                                            | Kubernetes Service Account audience to restrict accepting Kubernetes Service Account Token                        |

### Verification keys for Kubernetes ServiceAccount Token

In order to verify the Kubernetes ServiceAccount Token, at least one option must be specified.

1. JWK Set Endpoint
   - `config.constraints.keys.jwks.url`
   - `config.constraints.keys.jwks.cacert`
   - `config.constraints.keys.jwks.force_cache_duration_seconds`
2. API Endpoint URL (most likely kube-apiserver) to retrieve JWK Set endpoints
   - `config.constraints.keys.apinodes.url`
3. A static keys to verify Kubernetes Service Account Token (in pem or jwks format)
   - `config.constraints.keys.static`

## How to test

### Test rego files for opa

```
opa test -v --v0-compatible {policy,test}/*.rego {policy,test}/*.yaml
```

to see test coverage,

```
opa test -cv --v0-compatible {policy,test}/*.rego {policy,test}/*.yaml
```

### How to prepare for the test

#### How to generate key pairs

```
openssl genrsa 2048 > test/private.key.pem
```

```
openssl rsa -in test/private.key.pem -pubout > test/public.key.pem
```

#### How to generate a test jwk

```
step crypto jwk create --alg RS256 --kid jIoPyoDK6l7wdT2vEh_4b9sUGwCuVBz1L9z4hbd4Vbo --from-pem=test/private.key.pem --no-password --insecure -f test/public.jwk.json test/private.jwk.json
```

#### How to generate a test jwt

```
cat test/mock.yaml | yq .mock.jwt.body | dasel -ryaml -wjson | step crypto jws sign --alg RS256 --kid jIoPyoDK6l7wdT2vEh_4b9sUGwCuVBz1L9z4hbd4Vbo --key test/private.key.pem
```

### How to test verifying jwt

#### With JWK file

```
cat test/mock.yaml | yq .mock.jwk > test/public.jwk.json
```

```
cat test/mock.yaml | yq .mock.instance.input.attestationData | step crypto jwt verify --key test/public.jwk.json --iss https://kubernetes.default.svc.cluster.local --aud https://kubernetes.default.svc
```

#### With PEM file

```
cat test/mock.yaml | yq .mock.instance.input.attestationData | step crypto jwt verify --key test/public.key.pem --alg RS256 --iss https://kubernetes.default.svc.cluster.local --aud https://kubernetes.default.svc
```

### How to test with server

#### How to run server

```
opa run --server --config-file=$(pwd)/local/config.yaml --addr=http://127.0.0.1:8181 --ignore=.* --disable-telemetry --v0-compatible policy/*.rego local/policy/config.yaml
```

#### How to input Kubernetes Pod data

```
curl -svX PUT -H"Content-Type:application/json" -H"Authorization: Bearer $(cat test/mock.yaml | yq .mock.instance.input.attestationData)" -d"$(cat test/mock.yaml | yq .mock.pods -ojson)" http://127.0.0.1:8181/v1/data/kubernetes/pods
```

#### How to make attestation request

```
curl -svX POST -H'Content-Type:application/json' -d@test/request.json http://127.0.0.1:8181/v0/data/identityprovider/instance
```

```
curl -svX POST -H'Content-Type:application/json' -d@test/request.json http://127.0.0.1:8181/v0/data/identityprovider/refresh
```

