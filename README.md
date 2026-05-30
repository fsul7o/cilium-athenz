# cilium-athenz

## setup
```
make patch
make kind-setup
make deploy-athenz
make deploy-identityprovider
make deploy-cilium
```

## testing
```
$ make deploy-test-workload

$ kubectl --context kind-cilium -n default exec -it pod-worker -- curl -s -o /dev/null -w "%{http_code}" http://echo:3000/headers
200
$ kubectl --context kind-cilium -n default exec -it pod-worker -- curl http://echo:3000/headers-1
Access denied

$ make clean-test-workload
```

## benchmark
`athenz-distribution` の `loadtest` と同じように、remote kind クラスタ内の `vegeta` から `plain` と `auth` の 2 経路を比較できます。

```
$ make deploy-benchmark-workload

$ make run-benchmark
===== benchmark: plain =====
...
===== benchmark: auth =====
...

$ make clean-benchmark-workload
```

デフォルト値は `BENCH_RATE=100` `BENCH_WORKERS=100` `BENCH_DURATION=30s` `BENCH_KEEPALIVE=false` です。必要なら `make run-benchmark BENCH_RATE=200 BENCH_DURATION=60s` のように上書きできます。

## cleanup
```
make kind-delete

make clean-cilium
```
