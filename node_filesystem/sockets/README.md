# Sockets

bird and bird6 control sockets will go here in the running container.

This allows easy interaction with third party tools (such as bird_exporter) that wish to interact with bird.

## Example

We would like to monitor bird and use the third party tool `bird_exporter` which connects to the bird sockets and allows `prometheus` to collect metrics.

we *could* run `bird-exporter` in the same container but it probably not needed for all uses of calico/routereflector. This would also involve *building* bird-exporter for each target architecture and munging it into the relevant Dockerfile.

Instead putting the control sockets in `/sockets` allows us options to share this folder with other things. For example in kubernetes we can mount an `emptyDir` volume onto that location and share the sockets accross 2 containers in the same pod. This allows us to run `bird-exporter` in it's own container as a sidecar in a kubernetes pod and is extensible to any other application.
