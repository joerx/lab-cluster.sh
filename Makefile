PACKAGE_NAME ?= $(shell basename $(CURDIR))
COMMIT ?= $(shell git rev-parse --short HEAD)
VERSION ?= v0.1.0-$(COMMIT)
APP_VERSION ?= $(VERSION)

.PHONY: default
default: package

out:
	mkdir -p out

out/cluster-bootstrap-argo-$(VERSION).tgz: out
	helm package --version $(VERSION) --app-version $(APP_VERSION) -d out charts/bootstrap-argo/

out/cluster-bootstrap-secrets-$(VERSION).tgz: out
	helm package --version $(VERSION) --app-version $(APP_VERSION) -d out charts/bootstrap-secrets/

.PHONY: package
package: out/cluster-bootstrap-argo-$(VERSION).tgz out/cluster-bootstrap-secrets-$(VERSION).tgz

.PHONY: clean
clean:
	rm -rf out

.PHONY: release
release:
	gh release create $(VERSION) --title "Release $(VERSION)" --target main --generate-notes
