NAME=dit4c-helper-upload-webdav
VERSION=$(shell git describe --dirty --tags)

.DEFAULT_GOAL := dist/$(NAME).linux.amd64.aci
.PHONY: clean test deploy

ACBUILD_VERSION=0.4.0
RKT_VERSION=1.17.0
ACBUILD=build/acbuild
RKT=build/rkt/rkt
GPG=gpg2

dist/bintray-descriptor.json:
	@echo "$$BINTRAY_DESCRIPTOR_JSON" > $@

dist/$(NAME).linux.amd64.aci: build/acbuild build/client-base.aci build/jwt *.sh | dist
	rm -rf .acbuild
	sudo -v
	sudo $(ACBUILD) --debug begin ./build/client-base.aci
	sudo $(ACBUILD) environment add DIT4C_IMAGE ""
	sudo $(ACBUILD) environment add DIT4C_IMAGE_ID ""
	sudo $(ACBUILD) environment add DIT4C_IMAGE_SERVER ""
	sudo $(ACBUILD) environment add DIT4C_IMAGE_UPLOAD_NOTIFICATION_URL ""
	sudo $(ACBUILD) environment add DIT4C_INSTANCE_PRIVATE_KEY_PKCS1 ""
	sudo $(ACBUILD) environment add DIT4C_INSTANCE_PRIVATE_KEY_OPENPGP ""
	sudo $(ACBUILD) environment add DIT4C_INSTANCE_PRIVATE_KEY_OPENPGP_PASSPHRASE ""
	sudo $(ACBUILD) environment add DIT4C_INSTANCE_JWT_KID ""
	sudo $(ACBUILD) environment add DIT4C_INSTANCE_JWT_ISS ""
	sudo $(ACBUILD) copy build/jwt /usr/bin/jwt
	sudo $(ACBUILD) copy run.sh /opt/bin/run.sh
	sudo $(ACBUILD) set-name $(NAME)
	sudo $(ACBUILD) set-exec -- /opt/bin/run.sh
	sudo $(ACBUILD) write --overwrite $@
	sudo $(ACBUILD) end
	sudo chown $(shell id -nu) $@

dist/%.aci.asc: dist/%.aci signing.key
	$(eval TMP_PUBLIC_KEYRING := $(shell mktemp -p ./build))
	$(eval TMP_SECRET_KEYRING := $(shell mktemp -p ./build))
	$(eval GPG_FLAGS := --batch --no-default-keyring --keyring $(TMP_PUBLIC_KEYRING) --secret-keyring $(TMP_SECRET_KEYRING) )
	$(GPG) $(GPG_FLAGS) --import signing.key
	rm -f $@
	$(GPG) $(GPG_FLAGS) --armour --detach-sign $<
	rm $(TMP_PUBLIC_KEYRING) $(TMP_SECRET_KEYRING)

build dist:
	mkdir -p $@

build/client-base.aci: $(RKT)
	$(eval RKT_TMPDIR := $(shell mktemp -d -p ./build))
	$(eval RKT_UUID_FILE := $(shell mktemp -p ./build))
	sudo -v && sudo $(RKT) --dir=$(RKT_TMPDIR) \
		run --insecure-options=image --uuid-file-save=$(RKT_UUID_FILE) \
		--dns=8.8.8.8 \
		docker://alpine:edge \
		--exec /bin/sh -- -c \
		"apk add --update gnupg curl && rm -rf /var/cache/apk/*"
	sudo $(RKT) --dir=$(RKT_TMPDIR) export --overwrite `cat $(RKT_UUID_FILE)` $@
	sudo chown $(shell id -nu) $@
	sudo $(RKT) --dir=$(RKT_TMPDIR) gc --grace-period=0s
	sudo rm -rf $(RKT_TMPDIR) $(RKT_UUID_FILE)

build/acbuild: | build
	curl -sL https://github.com/appc/acbuild/releases/download/v${ACBUILD_VERSION}/acbuild-v${ACBUILD_VERSION}.tar.gz | tar xz -C build
	mv build/acbuild-v${ACBUILD_VERSION}/acbuild $@
	-rm -rf build/acbuild-v${ACBUILD_VERSION}

build/jwt: | $(RKT)
	$(eval RKT_TMPDIR := $(shell mktemp -d -p ./build))
	sudo -v && sudo $(RKT) --dir=$(RKT_TMPDIR) run \
		--dns=8.8.8.8 --insecure-options=image \
    --volume output-dir,kind=host,source=`pwd`/build \
    docker://golang:alpine \
    --set-env CGO_ENABLED=0 \
    --set-env GOOS=linux \
    --mount volume=output-dir,target=/output \
    --exec /bin/sh --  -c "apk add --update git make && /usr/local/go/bin/go get -v --ldflags '-extldflags \"-static\"' github.com/knq/jwt/cmd/jwt && install -t /output -o $(shell id -u) -g $(shell id -g) /go/bin/*"
	sudo -v && sudo $(RKT) --dir=$(RKT_TMPDIR) gc --grace-period=0s
	sudo rm -rf $(RKT_TMPDIR)

build/bats: | build
	curl -sL https://github.com/sstephenson/bats/archive/master.zip > build/bats.zip
	unzip -d build build/bats.zip
	mv build/bats-master $@
	rm build/bats.zip

$(RKT): | build
	curl -sL https://github.com/coreos/rkt/releases/download/v${RKT_VERSION}/rkt-v${RKT_VERSION}.tar.gz | tar xz -C build
	mv build/rkt-v${RKT_VERSION} build/rkt

test: build/bats $(RKT) dist/$(NAME).linux.amd64.aci
	sudo -v && echo "" && build/bats/bin/bats -t test

clean:
	-rm -rf build .acbuild dist

deploy: dist/$(NAME).linux.amd64.aci.asc
