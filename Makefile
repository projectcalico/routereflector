.PHONEY: clean

# These variables can be overridden by setting an environment variable.
LOCAL_IP_ENV?=$(shell ip route get 8.8.8.8 | head -1 | cut -d' ' -f8)

CONFD_REPO?=calico/confd
CONFD_VER?=v1.0.0-beta1-4-g4619952
CONFD_CONTAINER_NAME=${CONFD_REPO}:${CONFD_VER}

default: clean calicorr.created

calicorr.created: $(BUILD_FILES) dist/confd
	docker build -t calico/routereflector .
	touch calicorr.created

clean:
	-rm *.created
	-rm -rf dist

dist/confd: dist
	-docker rm -f calico-confd
	# Latest confd binaries are stored in automated builds of calico/confd.
	# To get them, we create (but don't start) a container from that image.
	docker pull $(CONFD_CONTAINER_NAME)
	docker create --name calico-confd $(CONFD_CONTAINER_NAME)
	# Then we copy the files out of the container.  Since docker preserves
	# mtimes on its copy, check the file really did appear, then touch it
	# to make sure that downstream targets get rebuilt.
	docker cp calico-confd:/bin/confd $@ && test -e $@ && touch $@
	-docker rm -f calico-confd
	chmod +x $@

dist:
	mkdir -p dist
