# Both native and cross architecture builds are supported.
# The target architecture is select by setting the ARCH variable.
# When ARCH is undefined it is set to the detected host architecture.
# When ARCH differs from the host architecture a crossbuild will be performed.

# restore this when all arches work. For now, there are qemu issues related to cross-compile on s390x
#   see https://github.com/projectcalico/go-build/pull/32
#ARCHES=$(patsubst docker-image/Dockerfile.%,%,$(wildcard docker-image/Dockerfile.*))
ARCHES=amd64 arm64 ppc64le


# BUILDARCH is the host architecture
# ARCH is the target architecture
# we need to keep track of them separately
BUILDARCH ?= $(shell uname -m)
BUILDOS ?= $(shell uname -s | tr A-Z a-z)

# canonicalized names for host architecture
ifeq ($(BUILDARCH),aarch64)
        BUILDARCH=arm64
endif
ifeq ($(BUILDARCH),x86_64)
        BUILDARCH=amd64
endif

# unless otherwise set, I am building for my own architecture, i.e. not cross-compiling
ARCH ?= $(BUILDARCH)

# canonicalized names for target architecture
ifeq ($(ARCH),aarch64)
        override ARCH=arm64
endif
ifeq ($(ARCH),x86_64)
    override ARCH=amd64
endif

CONTAINER_NAME=calico/routereflector
GO_BUILD_VER ?= v0.16


.PHONY: clean image

IMAGE_CREATED_BASE=calicorr.created
IMAGE_CREATED_FILE=$(IMAGE_CREATED_BASE)-$(ARCH)



# These variables can be overridden by setting an environment variable.
LOCAL_IP_ENV?=$(shell ip route get 8.8.8.8 | head -1 | cut -d' ' -f8)

CONFD_REPO?=calico/confd
CONFD_VER?=v3.1.1
# problem is that calico/confd does not yet have for other archs, and archless is amd64
# so we will add a little logic here to handle it
ifeq ($(ARCH),amd64)
CONFD_CONTAINER_NAME=${CONFD_REPO}:${CONFD_VER}
else
CONFD_CONTAINER_NAME=${CONFD_REPO}:${CONFD_VER}-$(ARCH)
endif

default: clean image

.PHONY: ci cd
## Builds the code and runs all tests.
ci: $(IMAGE_CREATED_BASE)

## Deploys images to registry
cd:
ifndef CONFIRM
	$(error CONFIRM is undefined - run using make <target> CONFIRM=true)
endif
ifndef BRANCH_NAME
	$(error BRANCH_NAME is undefined - run using make <target> BRANCH_NAME=var or set an environment variable)
endif
	$(MAKE) tag-images push IMAGETAG=${BRANCH_NAME}
	$(MAKE) tag-images push IMAGETAG=$(shell git describe --tags --dirty --always --long)




# standard build target, but nothing to do
build:

image: $(IMAGE_CREATED_FILE)
$(IMAGE_CREATED_BASE): $(IMAGE_CREATED_FILE)
$(IMAGE_CREATED_FILE): $(BUILD_FILES) dist/confd-$(ARCH)
	docker build $(DOCKER_EXTRA_BUILD_ARGS) -t $(CONTAINER_NAME):latest-$(ARCH) -f Dockerfile.$(ARCH) .
ifeq ($(ARCH),amd64)
	docker tag $(CONTAINER_NAME):latest-$(ARCH) $(CONTAINER_NAME):latest
endif
	touch $(IMAGE_CREATED_FILE)

clean:
	-rm *.created
	-rm -rf dist
	-docker rmi -f $(CONTAINER_NAME)
	-docker rmi -f quay.io/$(CONTAINER_NAME)

dist/confd-$(ARCH): dist
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


###############################################################################
# tag and push images of any tag
###############################################################################
imagetag:
ifndef IMAGETAG
	$(error IMAGETAG is undefined - run using make <target> IMAGETAG=X.Y.Z)
endif


## push all arches
push-all: imagetag $(addprefix sub-push-,$(ARCHES))
sub-push-%:
	$(MAKE) push ARCH=$* IMAGETAG=$(IMAGETAG)

## push one arch
push: imagetag
	docker push $(CONTAINER_NAME):$(IMAGETAG)-$(ARCH)
	docker push quay.io/$(CONTAINER_NAME):$(IMAGETAG)-$(ARCH)
ifeq ($(ARCH),amd64)
	docker push $(CONTAINER_NAME):$(IMAGETAG)
	docker push quay.io/$(CONTAINER_NAME):$(IMAGETAG)
endif

## tag images of one arch
tag-images: imagetag
	docker tag $(CONTAINER_NAME):latest-$(ARCH) $(CONTAINER_NAME):$(IMAGETAG)-$(ARCH)
	docker tag $(CONTAINER_NAME):latest-$(ARCH) quay.io/$(CONTAINER_NAME):$(IMAGETAG)-$(ARCH)
ifeq ($(ARCH),amd64)
	docker tag $(CONTAINER_NAME):latest-$(ARCH) $(CONTAINER_NAME):$(IMAGETAG)
	docker tag $(CONTAINER_NAME):latest-$(ARCH) quay.io/$(CONTAINER_NAME):$(IMAGETAG)
endif

## tag images of all archs
tag-images-all: imagetag $(addprefix sub-tag-images-,$(ARCHES))
sub-tag-images-%:
	$(MAKE) tag-images ARCH=$* IMAGETAG=$(IMAGETAG)

###############################################################################



release: clean
ifndef VERSION
	$(error VERSION is undefined - run using make release VERSION=vX.Y.Z)
endif
	# Check for uncommitted changes.
	if git describe --always --dirty | grep dirty; \
	then echo "Current git working tree has uncommitted changes. Commit, stash or discard those before releasing." ;false; fi

	git tag $(VERSION)

	# Build docker image.
	$(MAKE) $(IMAGE_CREATED_FILE) DOCKER_EXTRA_BUILD_ARGS="--pull"

	# Retag images with correct version and quay
	$(MAKE) tag-images IMAGETAG=$(VERSION)
	$(MAKE) tag-images IMAGETAG=latest

	# Check that images were created recently and that the IDs of the versioned and latest images match
	@docker images --format "{{.CreatedAt}}\tID:{{.ID}}\t{{.Repository}}:{{.Tag}}" $(CONTAINER_NAME)
	@docker images --format "{{.CreatedAt}}\tID:{{.ID}}\t{{.Repository}}:{{.Tag}}" $(CONTAINER_NAME):$(VERSION)

	@echo ""
	@echo "# Push the created tag to GitHub"
	@echo "  git push origin $(VERSION)"
	@echo ""
	@echo "# Now, create a GitHub release from the tag, and add release notes."
	@echo "# To find commit messages for the release notes:  git log --oneline <old_release_version>...$(VERSION)"
	@echo ""
	@echo "# Now push the newly created release images."
	@echo ""
	@echo "  $(MAKE) push IMAGETAG=$(VERSION)"
	@echo ""
	@echo "# For the final release only, push the latest tag"
	@echo "# DO NOT PUSH THESE IMAGES FOR RELEASE CANDIDATES OR ALPHA RELEASES"
	@echo ""
	@echo "  $(MAKE) push IMAGETAG=latest"
	@echo ""
	@echo "See RELEASING.md for detailed instructions."
