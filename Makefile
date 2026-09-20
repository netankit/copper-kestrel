IMAGE ?= searchd:local
NAMESPACE ?= search

.PHONY: kind-up kind-down build deploy-local smoke logs

kind-up:
	kind create cluster --name searchd --config kind/cluster.yaml

kind-down:
	kind delete cluster --name searchd

build:
	docker build -t $(IMAGE) ./app

deploy-local: build
	kind load docker-image $(IMAGE) --name searchd
	kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	helm upgrade --install searchd ./helm \
		--namespace $(NAMESPACE) \
		--set image.repository=searchd \
		--set image.tag=local \
		--set image.pullPolicy=Never \
		--set storage.className=standard \
		--set storage.size=1Gi \
		--set resources.requests.cpu=100m \
		--set resources.requests.memory=128Mi \
		--set resources.limits.cpu=500m \
		--set resources.limits.memory=256Mi \
		--set env.indexLoadSeconds=90

smoke:
	kubectl -n $(NAMESPACE) port-forward svc/searchd-query 8080:8080 & \
	sleep 3; \
	for i in 1 2 3 4 5; do curl -s localhost:8080/search?q=test; echo; done; \
	curl -s -XPOST localhost:8080/ingest -d '[{"doc":"a"},{"doc":"b"}]'; echo; \
	kill %1

logs:
	kubectl -n $(NAMESPACE) logs -l app=searchd --tail=50
