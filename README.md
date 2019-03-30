# Calico Docker BIRD Route Reflector image

## Introduction

This directory contains the build scripts to create a Calico BIRD Route 
Reflector image that can be used to set up a cluster of Route Reflectors with a
[Calico Docker][calico-docker] cluster of nodes.

The default target of the Makefile creates a Docker image called 
calico/routereflector, the Calico DockerHub repo creates a publically 
accessible image of the same name.  If you just wish to use the current Route 
Reflector image, then you will not need to build the image locally.

For more details, refer to the main [Calico documentation](http://docs.projectcalico.org/master/usage/routereflector/calico-routereflector).

### Route reflector cluster

When starting a cluster of route reflectors, the Calico BIRD Route Reflector
takes care of creating a full mesh between all of the route reflectors in the 
cluster. When adding a new Route Reflector instance, add an entry into etcd.
All Route Reflector instances watch for new Route Reflectors and update their
peerings accordingly.

### Route reflector peering with Calico Docker nodes

The Calico BIRD Route Reflector image hooks into the same etcd datastore used
by the Calico Docker nodes to determine which nodes to peer with.

The peering between the Calico Docker nodes and each Route Reflector is 
entirely configured on the Calico Docker nodes (using [calicoctl][calicoctl]),
and not through any additional Route Reflector configuration.

## Using the Route Reflector image (with etcd datastore)

### Starting up a Route Reflector

On your Route Reflector host, ensure you have [Docker v1.6][docker] or greater
installed.

Run the following command to start the Route Reflector container image.

```
docker run -privileged -net=host -d                                \ 
           -e IP=<IPv4_RR>                                         \
           [-e IP6=<IPv6_RR>]                                      \
           -e ETCD_ENDPOINTS=<http://ETCD_IP:PORT>                 \
           calico/routereflector
```

Where:

-  `[]` indicates an optional parameter
-  `<IPv4_RR>` is the IPv4 address of the RR host (the BIRD instance binds to 
   the hosts IPv4 address)
-  `<IPv6_RR>` is the *optional* IPv6 address of the RR host (the BIRD6 instance
   binds to the hosts IPv6 address)
-  `<ETCD_IP:PORT>` is the colon separated IPv4 address and port of an etcd
   node in the etcd cluster.

#### Adding the Route Reflector into etcd

Add an entry in etcd for this Route Reflector.  This tells the Route Reflector
to participate in peering, and provides enough information to allow the Route
Reflector instances to automatically form a full BGP mesh.

The configuration for the Route Reflector is stored for IPv4 at:

	/calico/bgp/v1/rr_v4/<RR IPv4 address>
	
and IPv6 at:

	/calico/bgp/v1/rr_v6/<RR IPv6 address>

In all cases, the data is a JSON blob in the form:

        {
          "ip": "<IP address of BGP Peer>",
          "cluster_id": "<Cluster ID for this RR (see notes)>"
        }

To add this entry into etcd, you could use the following commands:
```
# IPv4 entries
curl -L http://<ETCD_IP:PORT>:2379/v2/keys/calico/bgp/v1/rr_v4/<IPv4_RR> -XPUT -d value="{\"ip\":\"<IPv4_RR>\",\"cluster_id\":\"<CLUSTER_ID>\"}"

# IPv6 entries
curl -L http://<ETCD_IP:PORT>:2379/v2/keys/calico/bgp/v1/rr_v6/<IPv6_RR> -XPUT -d value="{\"ip\":\"<IPv6_RR>\",\"cluster_id\":\"<CLUSTER_ID>\"}"
```
See [below](#topology-with-multiple-calico-bird-route-reflectors) for details 
about large networks and the use and format of the cluster ID.

Repeat the above instructions for every Route Reflector in the cluster.

### Route Reflector with TLS/SSL Etcd

If you are running secure etcd, you will need to pass in additional options
and set environment variables for the certificate and key files associated
with your etcd instance.

When starting the Route Reflector container image, you need to mount the
certificate files and environment variable filepaths for each file:
```
docker run --privileged --net=host -d                              \
           -e IP=<IPv4_RR>                                         \
           [-e IP6=<IPv6_RR>]                                      \
           -e ETCD_ENDPOINTS=<https://ETCD_IP:PORT>                \
           -v <FULL_PATH_TO_CERT_DIR>:<MOUNT_DIR>                  \
           -e ETCD_CA_CERT_FILE=<MOUNT_DIR>/<CA_FILE>              \
           -e ETCD_CERT_FILE=<MOUNT_DIR>/<CERT_FILE>               \
           -e ETCD_KEY_FILE=<MOUNT_DIR>/<KEY_FILE>                 \
           calico/routereflector
```
Where `<FULL_PATH_TO_CERT_DIR>` is a directory on the host that contains
the certificate files (you can mount multiple directories with additional
`-v <DIR>` parameters if they are in separate directories, but be sure
to choose different `<MOUNT_DIR>` locations if this is the case).

You will also need to pass the certificate and key files as parameters
in the curl statement when adding entries:
```
# IPv4 entries
curl --cacert <path_to_ca_cert> --cert <path_to_cert> --key <path_to_key> -L https://<ETCD_IP:PORT>:2379/v2/keys/calico/bgp/v1/rr_v4/<IPv4_RR> -XPUT -d value="{\"ip\":\"<IPv4_RR>\",\"cluster_id\":\"<CLUSTER_ID>\"}"
# IPv6 entries
curl --cacert <path_to_ca_cert> --cert <path_to_cert> --key <path_to_key> -L https://<ETCD_IP:PORT>:2379/v2/keys/calico/bgp/v1/rr_v6/<IPv6_RR> -XPUT -d value="{\"ip\":\"<IPv6_RR>\",\"cluster_id\":\"<CLUSTER_ID>\"}"
```

## Using the Route Reflector image (with Kubernetes API datastore)

If you are using Kuberenetes as the datastore for Calico, the routereflector
image does support this, but only for a single route reflector.  It is not
possible with this image to set up a cluster of route reflectors.

### Starting up the Route Reflector

On your Route Reflector host, ensure you have [Docker v1.6][docker] or greater
installed.

You will need a kubeconfig file that you need to mount into the route reflector
container.

Run the following command to start the Route Reflector container image.

```
docker run --privileged --net=host -d                              \
           -e DATASTORE_TYPE=kubernetes                            \
           -e KUBECONFIG=/kubeconfig                               \
           -e IP=<IPv4_RR>                                         \
           -v <KUBECONFIG_FILE_PATH>:/kubeconfig                   \
           calico/routereflector
```

Where:

-  `<IPv4_RR>` is the IPv4 address of the RR host (the BIRD instance binds to
   the hosts IPv4 address)
-  `<KUBECONFIG_FILE_PATH>` is the path to the kubeconfig file.

When using Kubernetes API as the datastore, this route reflector image only works
as a single standalone reflector.

## Running a kubernetes sidecar container that interacts with routereflector

The control sockets for `bird` and `bird6` are opened in the `/sockets/` folder of the container. This allows us to share the sockets accross containers in the same kubernetes pod easily. One nice case would be to expose metrics using another open source project called [bird_exporter](https://github.com/czerwonk/bird_exporter)

We can do this ***fairly*** easily using a kubernetes an `emptyDir` kubernetes volume.

This example creates a deployment of a single pod containing two containers (`calico-reflector` and `calico-reflector-metrics`). They interact with each other using the controll sockets of `bird` and `bird6` by mounting a kubernetes `emptyVolume` on both container filesystems. (You'll need to provide an ETCD cluster and specify the values for *IP* and *ETCD_ENDPOINTS* for your environment)

The advantage of doing it this way means we can avoid bloat in the `routereflector` image for customers that don't need this functionality and make this reasonably easy to expand to different use cases.

```yaml
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: calico-bgp-reflector-1
  namespace: kube-system
  labels:
    calico-component: bgp-reflector
    k8s-app: calico-bgp-reflector-1
  annotations:
    scheduler.alpha.kubernetes.io/critical-pod: ''
spec:
  selector:
    matchLabels:
      calico-component: bgp-reflector
  replicas: 1
  strategy:
    type: Recreate
  template:
    metadata:
      name: calico-bgp-reflector-1
      namespace: kube-system
      labels:
        k8s-app: calico-bgp-reflector-1
        calico-component: bgp-reflector
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: calico-component
                operator: In
                values:
                - bgp-reflector
            topologyKey: "kubernetes.io/hostname"
      hostNetwork: true
      volumes:
      - name: socketsshare
        emptyDir: {}
      containers:
      - name: calico-reflector
        volumeMounts:
        - name: socketsshare
          mountPath: /sockets
        image: calico/routereflector
        securityContext:
          privileged: true
        env:
          - name: IP
            value: "<YOURIP>"
          - name: ETCD_ENDPOINTS
            value: <"ETCD_ADDRESS>"
      - name: calico-reflector-metrics
        volumeMounts:
        - name: socketsshare
          mountPath: /sockets
        image: czerwonk/bird_exporter
        command: ["./bird_exporter"]
        args:
        - "-format.new=true"
        - "-bird.socket=/sockets/bird.ctl"
        - "-bird.socket6=/sockets/bird6.ctl"
...

---
apiVersion: v1
kind: Service
metadata:
  namespace: kube-system
  labels:
    k8s-app: calico-bgp-reflector-1
  name: calico-bgp-reflector-1
spec:
  ports:
  - port: 179
    protocol: TCP
    targetPort: 179
    name: bgp-tcp
  - port: 179
    protocol: UDP
    targetPort: 179
    name: bgp-udp
  - port: 9324
    protocol: TCP
    targetPort: 9234
    name: metrics
  selector:
    k8s-app: calico-bgp-reflector-1
  type: ClusterIP
...
```