###############################################################################
# The build architecture is select by setting the ARCH variable.
# # For example: When building on ppc64le you could use ARCH=ppc64le make <....>.
# # When ARCH is undefined it defaults to amd64.
ARCH?=amd64
ifeq ($(ARCH),amd64)
	ARCHTAG?=
endif

ifeq ($(ARCH),ppc64le)
	ARCHTAG:=-ppc64le
endif

ifeq ($(ARCH),s390x)
	ARCHTAG:=-s390x
endif

.PHONEY: clean

# These variables can be overridden by setting an environment variable.
LOCAL_IP_ENV?=$(shell ip route get 8.8.8.8 | head -1 | cut -d' ' -f8)

CONFD_REPO?=calico/confd
CONFD_VER?=v1.1.0-rc1
CONFD_CONTAINER_NAME=${CONFD_REPO}:${CONFD_VER}

default: clean calicorr.created

calicorr.created: $(BUILD_FILES) dist/confd
	docker build -t calico/routereflector$(ARCHTAG) -f Dockerfile$(ARCHTAG) .
	touch calicorr.created

clean:
	-rm *.created
	-rm -rf dist
	-docker rmi -f calico/routereflector
	-docker rmi -f quay.io/calico/routereflector

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

release: clean
ifndef VERSION
	$(error VERSION is undefined - run using make release VERSION=vX.Y.Z)
endif
	# Check for uncommitted changes.
	if git describe --always --dirty | grep dirty; \
	then echo "Current git working tree has uncommitted changes. Commit, stash or discard those before releasing." ;false; fi

	git tag $(VERSION)

	# Build docker image.
	$(MAKE) calicorr.created

	# Retag images with correct version and quay
	docker tag calico/routereflector calico/routereflector:$(VERSION)
	docker tag calico/routereflector quay.io/calico/routereflector:$(VERSION)
	docker tag calico/routereflector quay.io/calico/routereflector:latest

	# Check that images were created recently and that the IDs of the versioned and latest images match
	@docker images --format "{{.CreatedAt}}\tID:{{.ID}}\t{{.Repository}}:{{.Tag}}" calico/routereflector
	@docker images --format "{{.CreatedAt}}\tID:{{.ID}}\t{{.Repository}}:{{.Tag}}" calico/routereflector:$(VERSION)

	@echo ""
	@echo "# Push the created tag to GitHub"
	@echo "  git push origin $(VERSION)"
	@echo ""
	@echo "# Now, create a GitHub release from the tag, and add release notes."
	@echo "# To find commit messages for the release notes:  git log --oneline <old_release_version>...$(VERSION)"
	@echo ""
	@echo "# Now push the newly created release images."
	@echo ""
	@echo "  docker push calico/routereflector:$(VERSION)"
	@echo "  docker push quay.io/calico/routereflector:$(VERSION)"
	@echo ""
	@echo "# For the final release only, push the latest tag"
	@echo "# DO NOT PUSH THESE IMAGES FOR RELEASE CANDIDATES OR ALPHA RELEASES"
	@echo ""
	@echo "  docker push calico/routereflector:latest"
	@echo "  docker push quay.io/calico/routereflector:latest"
	@echo ""
	@echo "See RELEASING.md for detailed instructions."
