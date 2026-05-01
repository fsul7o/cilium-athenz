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
$ kubectl config use-context kind-cilium
$ kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/HEAD/examples/kubernetes/servicemesh/mutual-auth-example.yaml
$ kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/HEAD/examples/kubernetes/servicemesh/cnp-with-mutual-auth.yaml

$ kubectl exec -it pod-worker -- curl -s -o /dev/null -w "%{http_code}" http://echo:3000/headers
200
$ kubectl exec -it pod-worker -- curl http://echo:3000/headers-1
Access denied

$ kubectl delete -f https://raw.githubusercontent.com/cilium/cilium/HEAD/examples/kubernetes/servicemesh/mutual-auth-example.yaml
$ kubectl delete -f https://raw.githubusercontent.com/cilium/cilium/HEAD/examples/kubernetes/servicemesh/cnp-with-mutual-auth.yaml
```

## cleanup
```
make kind-delete

make clean-cilium
```