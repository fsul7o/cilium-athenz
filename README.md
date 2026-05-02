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

## cleanup
```
make kind-delete

make clean-cilium
```
