#!/bin/sh

nodes='
hbox1.atmtc.eu 10.90.0.1
hbox2.atmtc.eu 10.90.0.2
hbox3.atmtc.eu 10.90.0.3
'

template='---
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
nodeRegistration:
  kubeletExtraArgs:
  - name: node-ip
    value: ###wg_address###
  name: ###hostname###
  taints: []
localAPIEndpoint:
  advertiseAddress: ###wg_address###
  bindPort: 6443
bootstrapTokens:
  - token: ###token###
    ttl: "1h"
certificateKey: ###cert_key###
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: JoinConfiguration
nodeRegistration:
  kubeletExtraArgs:
  - name: node-ip
    value: ###wg_address###
  name: ###hostname### 
  taints: []
controlPlane:
  localAPIEndpoint:
    advertiseAddress: ###wg_address###
    bindPort: 6443
  certificateKey: ###cert_key###
discovery:
  bootstrapToken:
    apiServerEndpoint: "localhost:6444"
    token: ###token###
    unsafeSkipCAVerification: true
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
controlPlaneEndpoint: "localhost:6444"
networking:
  serviceSubnet: "10.96.0.0/16"
  podSubnet: "10.244.0.0/16"
caCertificateValidityPeriod: 876600h0m0s
certificateValidityPeriod: 876600h0m0s
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: "nftables"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
failSwapOn: false
memorySwap:
    swapBehavior: LimitedSwap
'

token=$( kubeadm token generate )
cert_key=$( kubeadm certs certificate-key )

printf "%s" "$nodes" | tail -n +2 | while IFS='' read line; do

    hostname=$( echo "$line" | cut -d ' ' -f 1 )
    wg_address=$( echo "$line" | cut -d ' ' -f 2 )

    printf "%s" "$template" | \
    sed "s/###hostname###/$hostname/g" | \
    sed "s/###wg_address###/$wg_address/g" | \
    sed "s/###token###/$token/g" | \
    sed "s/###cert_key###/$cert_key/g" \
    > "kubeadm-${hostname}-config.yaml"

done