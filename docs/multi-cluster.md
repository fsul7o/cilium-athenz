# Multi-Cluster

Athenz acts as an external shared CA, enabling mTLS authentication across multiple Cilium clusters connected via ClusterMesh. Each cluster obtains certificates from the same Athenz ZTS, so cross-cluster identity verification works without federation complexity.

## Architecture

```
┌─ Athenz cluster (kind-cilium-athenz) ───────────────────────────────────────────┐
│                                                                                 │
│  ┌─────────────┐   ┌─────────────┐  ┌─────────────────┐  ┌─────────────────┐    │
│  │ Athenz ZMS  │   │ Athenz ZTS  │  │ IdP (cilium1)   │  │ IdP (cilium2)   │    │
│  │ (policy)    │   │ (cert issue)│  │ ns: idp-cilium1 │  │ ns: idp-cilium2 │    │
│  └──────▲──────┘   └──▲──────────┘  └───────▲─────────┘  └───────▲─────────┘    │
│         │             │                     │                    │              │
└─────────┼─────────────┼─────────────────────┼────────────────────┼──────────────┘
          │             │                     │                    │
          │             │  Docker network: kind-cilium             │
          │             │                     │                    │
┌─────────┼─────────────┼─────────────────────┼──────┐ ┌──────────-┼─────────────┐
│         │             │                     │      │ │           │             │
│  ┌──────┴──────┐  ┌───┴──────────┐   ┌──────┴───┐  │ │  ┌───────-┴───┐  ┌────┐ │
│  │  Operator   │  │ Cilium Agent │   │ [client] │  │ │  │Cilium Agent│  │echo│ │
│  │             │  │ (mTLS certs) │   │          │  │ │  │(mTLS certs)│  │    │ │
│  └─────────────┘  └───────┬──────┘   └────┬─────┘  │ │  └──────┬─────┘  └────┘ │
│                           │               │        │ │         │               │
│                           │  mTLS handshake (port 4250)        │               │
│                           │◄──────────────────────────────────►│               │
│                           │               │        │ │         │               │
│                           │         data traffic   │ │         │               │
│                           └───────────────┼────────┼─┼─────────┘               │
│                                           │        │ │                         │
│  cilium1 (id=1)                           │        │ │  cilium2 (id=2)         │
│  pod CIDR: 10.1.0.0/16                    │        │ │  pod CIDR: 10.2.0.0/16  │
└───────────────────────────────────────────┴────────┘ └─────────────────────────┘
```

## Quick Start

```bash
# 0. Submodule setup
git submodule update --init --recursive

# 1. Apply patch files to submodules
make patch

# 2. Create three kind clusters (Athenz + cilium1 + cilium2)
make multi-kind-setup

# 3. Deploy Athenz (ZMS + ZTS)
make multi-deploy-athenz

# 4. Deploy identity providers (one per Cilium cluster)
make multi-deploy-identityprovider

# 5. Deploy Cilium with ClusterMesh + Athenz mTLS
make multi-deploy-cilium

# 6. Deploy cross-cluster test workload
make multi-deploy-test-workload
```

## Testing

Verify cross-cluster mTLS authentication and policy enforcement:

```bash
# Allowed: client in cilium1 → echo in cilium2 via global Service
kubectl --context kind-cilium1 exec -it pod-worker -- \
  curl -s -o /dev/null -w "%{http_code}" http://echo:3000/headers
# Expected: 200

# Denied: unauthorized path
kubectl --context kind-cilium1 exec -it pod-worker -- \
  curl -s -o /dev/null -w "%{http_code}" http://echo:3000/headers-1
# Expected: 403
```

Verify mTLS is active (check BPF auth map on the node hosting the echo pod):

```bash
# Find the cilium agent pod on the node where echo runs
ECHO_NODE=$(kubectl --context kind-cilium2 get pod echo -o jsonpath='{.spec.nodeName}')
CILIUM_POD=$(kubectl --context kind-cilium2 -n kube-system get pods -l k8s-app=cilium \
  --field-selector spec.nodeName=$ECHO_NODE -o jsonpath='{.items[0].metadata.name}')

# Check auth map entries (should show spire auth type with valid expiration)
kubectl --context kind-cilium2 -n kube-system exec $CILIUM_POD -c cilium-agent -- \
  cilium-dbg bpf auth list

# SRC IDENTITY   DST IDENTITY   REMOTE NODE ID   AUTH TYPE   EXPIRATION
# 176488         81723          21937            spire       2026-07-06 15:16:14 +0000 UTC
```

## Benchmark

Compare latency between plain (no auth) and Athenz-authenticated cross-cluster paths:

```bash
make multi-deploy-benchmark-workload
make multi-run-benchmark
make multi-clean-benchmark-workload
```

### Example Results

| Metric | Plain | Auth (mTLS + policy) |
|--------|------:|---------------------:|
| Requests | 3000 @ 100 rps | 3000 @ 100 rps |
| Mean latency | 379 us | 1.06 ms |
| P50 latency | 342 us | 620 us |
| P95 latency | 552 us | 1.12 ms |
| P99 latency | 1.01 ms | 5.58 ms |
| Max latency | 15.5 ms | 126.0 ms |
| Success ratio | 100% | 100% |

<details>
<summary>Raw output</summary>

```
===== multi-cluster benchmark: plain =====
Requests      [total, rate]            3000, 100.03
Duration      [total, attack, wait]    29.991116598s, 29.990644806s, 471.792µs
Latencies     [mean, 50, 95, 99, max]  379.475µs, 342µs, 551.75µs, 1.008958ms, 15.479042ms
Bytes In      [total, mean]            765000, 255.00
Bytes Out     [total, mean]            0, 0.00
Success       [ratio]                  100.00%
Status Codes  [code:count]             200:3000
Error Set:

===== multi-cluster benchmark: auth =====
Requests      [total, rate]            3000, 100.03
Duration      [total, attack, wait]    29.991198514s, 29.990642222s, 556.292µs
Latencies     [mean, 50, 95, 99, max]  1.060983ms, 620.042µs, 1.116709ms, 5.578334ms, 126.031375ms
Bytes In      [total, mean]            1368000, 456.00
Bytes Out     [total, mean]            0, 0.00
Success       [ratio]                  100.00%
Status Codes  [code:count]             200:3000
Error Set:
```

</details>

## Cleanup

```bash
make multi-kind-delete
```

## How Multi-Cluster mTLS Works

Cilium's standard mTLS (SPIRE-based) does not support multi-cluster because each cluster has an independent SPIRE server with its own trust domain. By using Athenz as an external shared CA:

1. **Shared Trust Domain** — All clusters obtain certificates from the same Athenz ZTS, so certificates issued to any cluster are verifiable by all others.
2. **ClusterMesh Integration** — Cilium's ClusterMesh synchronizes node information across clusters. The agent-to-agent mTLS handshake (port 4250) works cross-cluster because remote node IPs are already known.
3. **Cross-Cluster Policy** — The Cilium Operator resolves remote cluster identities from Athenz service tags when generating CiliumNetworkPolicies, enabling policy enforcement for cross-cluster traffic.
4. **Per-Cluster Identity Providers** — Each Cilium cluster has a dedicated Identity Provider (deployed in separate namespaces) that validates pod attestation against its target cluster's Kubernetes API.

### Cross-Cluster Request Flow

```
client (cilium1)
    │
    │ 1. curl http://echo:3000/headers
    │    DNS: echo.default.svc.cluster.local → ClusterIP
    ▼
CoreDNS (cilium1)
    │
    │ 2. Returns ClusterIP for global Service "echo"
    ▼
eBPF datapath (cilium1)
    │
    │ 3. ClusterMesh knows echo backend is in cilium2
    │    DNAT to echo Pod IP (10.2.x.x)
    ▼
Cilium Agent (cilium1)
    │
    │ 4. Policy requires authentication → check BPF auth map
    │    If no entry: trigger mTLS handshake with cilium2 Agent (port 4250)
    │    Cache result in BPF auth map
    ▼
VXLAN tunnel (Docker network: kind-cilium)
    │
    │ 5. Encapsulated packet forwarded to cilium2 node
    ▼
eBPF datapath (cilium2)
    │
    │ 6. Decapsulate → Envoy L7 proxy enforces HTTP policy
    │    GET /headers → allow, GET /headers-1 → 403
    ▼
echo Pod (cilium2)
```
