# Migrate kube-vip Services to Cilium

This migration replaces Flannel, kube-proxy, and the kube-vip Service controller with Cilium. Talos continues to own the API VIP at `10.3.3.8`. Argo CD, Traefik, and Minecraft retain `10.3.3.9`, `10.3.3.10`, and `10.3.3.11` respectively.

Use a maintenance window: this procedure stops workloads while changing the CNI. Existing pod sandboxes must be recreated, and nodes must reboot to remove Flannel interfaces and kube-proxy rules. This is a maintenance migration using Talos's existing pod CIDRs, rather than Cilium's [dual-overlay live migration](https://docs.cilium.io/en/stable/installation/k8s-install-migration/).

## 1. Prepare and pause GitOps

- Take an etcd snapshot and back up any application data that must survive draining. Keep a checkout of the previous repository revision for rollback.
- Confirm access to each Talos node's physical IP and to the Kubernetes API at `https://10.3.3.8:6443`. Do not depend on the Argo CD Service IP during the migration.
- Run `mise install`, reserve `10.3.3.9–11` outside DHCP, and verify all announcing nodes share the same LAN.
- Verify KubePrism is enabled on port `7445` on every node.
- Validate Kubernetes compatibility first. The repo targets `1.37`, which is newer than Cilium `1.20.2`'s [tested matrix](https://docs.cilium.io/en/stable/network/kubernetes/requirements/). Test pod DNS, cross-node traffic, ClusterIP, and TCP/UDP LoadBalancer traffic on that combination before the live migration. The [Cilium CLI connectivity test](https://docs.cilium.io/en/stable/operations/troubleshooting/#cilium-connectivity-tests) can help.

Before merging/pushing these changes to `main`, pause root auto-sync and the affected child applications. Children watch their sources independently, so pausing only the root would still allow the Service manifests to change. Pausing the root first prevents it from restoring their auto-sync policies.

```bash
kubectl -n argocd patch application root --type=merge \
  -p '{"spec":{"syncPolicy":{"automated":null}}}'
for app in kube-vip argocd-server-lb traefik minecraft; do
  kubectl -n argocd patch application "$app" --type=merge \
    -p '{"spec":{"syncPolicy":{"automated":null}}}'
done
```

Wait for any already-running Argo CD sync operations to finish before continuing. Keep the root paused until networking and the new Service configuration have been verified.

Render Cilium ahead of the outage, using the same release name and values as Argo CD:

```bash
helm template cilium cilium \
  --repo https://helm.cilium.io/ --version 1.20.2 \
  --namespace kube-system --values infra/cilium/values.yaml \
  > /tmp/homelab-cilium.yaml
```

## 2. Stop workloads and switch networking

Cordon all three nodes, then drain ordinary workloads. DaemonSets and the static control-plane pods remain. The drain deletes `emptyDir` data; resolve any PodDisruptionBudgets that prevent the planned outage before proceeding.

```bash
kubectl cordon talos-m2 talos-m4 talos-raider
for node in talos-m2 talos-m4 talos-raider; do
  kubectl drain "$node" --ignore-daemonsets --delete-emptydir-data
done

topf --topfconfig talos/topf.yaml apply \
  --allow-not-ready --skip-post-apply-checks

kubectl -n kube-system get daemonsets
```

The Talos patch disables Flannel and kube-proxy. If their old DaemonSets remain, remove them after confirming the names in the output above (Talos normally names them `kube-flannel` and `kube-proxy`):

```bash
kubectl -n kube-system delete daemonset kube-flannel kube-proxy --ignore-not-found
kubectl apply --server-side -f /tmp/homelab-cilium.yaml
# Temporarily let the host-network operator schedule while nodes are cordoned.
kubectl -n kube-system patch deployment cilium-operator --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/tolerations/-","value":{"key":"node.kubernetes.io/unschedulable","operator":"Exists","effect":"NoSchedule"}}]'
kubectl -n kube-system rollout status deployment/cilium-operator --timeout=5m
kubectl -n kube-system rollout status daemonset/cilium --timeout=5m
```

Cilium agents and the operator use host networking and can start while ordinary pods are Pending. The temporary operator toleration allows it to install Cilium's CRDs while nodes are cordoned; the subsequent Argo CD sync restores the chart's normal tolerations.

Reboot **one node at a time**, using its physical IP. For each node, wait for its Talos API and etcd service to recover before rebooting the next; never reboot a second control-plane node while the first is unavailable.

```bash
# Repeat separately for 10.3.3.198, 10.3.3.197, and 10.3.3.192.
talosctl -n <node-IP> reboot
talosctl -n <node-IP> service etcd
```

After all nodes have rebooted, verify every Cilium agent is ready, then allow workloads to return:

```bash
kubectl -n kube-system rollout status daemonset/cilium --timeout=5m
kubectl uncordon talos-m2 talos-m4 talos-raider
kubectl -n kube-system rollout status deployment/cilium-operator --timeout=5m
kubectl wait --for=condition=Ready nodes --all --timeout=5m
kubectl -n kube-system exec ds/cilium -- cilium-dbg status --verbose
```

Check pod DNS, the Kubernetes ClusterIP, and cross-node pod traffic before handing over Service advertisements. Recreate any remaining pods with old Flannel sandboxes; every non-host-network workload must use Cilium.

## 3. Hand over Service IPs

Stop kube-vip before installing the L2 policy, so both controllers cannot announce the same IPs. The old chart names its DaemonSet `kube-vip`; only the pods carry the chart's application labels:

```bash
kubectl -n kube-system get daemonset kube-vip
kubectl -n kube-system delete daemonset kube-vip
kubectl -n kube-system wait --for=delete pod \
  -l app.kubernetes.io/name=kube-vip --timeout=2m

kubectl wait --for=condition=Established \
  crd/ciliumloadbalancerippools.cilium.io \
  crd/ciliuml2announcementpolicies.cilium.io --timeout=2m
kubectl apply --server-side -f infra/cilium/config/
```

Apply the new labels and IP requests to the existing Services while their applications remain paused. These patches match the updated chart templates:

```bash
kubectl -n argocd patch service argocd-server-lb --type=merge \
  -p '{"metadata":{"labels":{"homelab.dsns.dev/load-balancer":"cilium"},"annotations":{"lbipam.cilium.io/ips":"10.3.3.9"}},"spec":{"loadBalancerIP":null,"externalTrafficPolicy":"Cluster"}}'
kubectl -n traefik patch service traefik --type=merge \
  -p '{"metadata":{"labels":{"homelab.dsns.dev/load-balancer":"cilium"},"annotations":{"lbipam.cilium.io/ips":"10.3.3.10"}},"spec":{"loadBalancerIP":null,"externalTrafficPolicy":"Cluster"}}'
kubectl -n minecraft patch service mc-proxy-service --type=merge \
  -p '{"metadata":{"labels":{"homelab.dsns.dev/load-balancer":"cilium"},"annotations":{"lbipam.cilium.io/ips":"10.3.3.11"}},"spec":{"loadBalancerIP":null,"externalTrafficPolicy":"Cluster"}}'

kubectl get services -A -l homelab.dsns.dev/load-balancer=cilium -o wide
kubectl -n kube-system get leases
```

Confirm all three Services have their original IPs and Cilium has L2 leases held by `talos-m4` or `talos-raider`. From another LAN machine, test Argo CD HTTPS, Traefik HTTPS, Minecraft TCP, and Minecraft voice-chat UDP. Test failover during the maintenance window by rebooting one announcing node and checking that its leases move to the other and the addresses recover.

Now publish the repository changes to `main` if they are not there already. Restore the root application and let it create the Cilium applications, restore the children's auto-sync policies, and take over the updated Services:

```bash
kubectl apply -f argocd/root-app.yaml
kubectl -n argocd get applications
kubectl get services -A -l homelab.dsns.dev/load-balancer=cilium -o wide
kubectl -n kube-system get leases
```

Verify the Cilium applications are Synced and Healthy, and no kube-vip pods have returned.

The old kube-vip Application has no resource finalizer, so removing it from the root's directory can leave its resources behind. The explicit DaemonSet deletion above stops advertisements. Remove its remaining RBAC and ServiceAccount after verification, using the old Application's resource inventory or manifests; check resource names before deleting shared `kube-system` objects.

## Rollback

Pause the root again before restoring the previous Git revision. Remove the Cilium L2 policy before allowing kube-vip to run, and keep the Cilium CNI running until workloads have been drained again. Restore the previous Talos patches and Flannel/kube-proxy configuration from the saved checkout.

When removing Cilium, first render and apply its chart with `--set cni.uninstall=true`, wait for the agent rollout, then delete the rendered chart resources. This enables removal of Cilium's CNI configuration on shutdown. Reboot nodes one at a time to clear the old datapath, and verify Flannel networking before uncordoning workloads. Restore the previous Service manifests, including `spec.loadBalancerIP`, and the kube-vip Application from the saved revision. Resume root auto-sync only after the previous Git configuration and live cluster agree.

A Git revert alone does not undo a CNI migration or restart pods in the old network.
