PACKAGE_NAME ?= $(shell basename $(CURDIR))
COMMIT ?= $(shell git rev-parse --short HEAD)
VERSION ?= 0.0.0-$(COMMIT)
APP_VERSION ?= $(VERSION)

out:
	mkdir -p out

out/bootstrap-argo-$(VERSION).tgz: out
	helm package --version $(VERSION) --app-version $(APP_VERSION) -d out charts/bootstrap-argo/

out/bootstrap-secrets-$(VERSION).tgz: out
	helm package --version $(VERSION) --app-version $(APP_VERSION) -d out charts/bootstrap-secrets/

.PHONY: package
package: out/bootstrap-argo-$(VERSION).tgz out/bootstrap-secrets-$(VERSION).tgz

.PHONY: clean
clean:
	rm -rf out

release:
# 	gh release create $(VERSION) --title "Release $(VERSION)" --target main --generate-notes
	gh release create $(VERSION) --title "Release $(VERSION)" --target tf-based-bootstrap --generate-notes
