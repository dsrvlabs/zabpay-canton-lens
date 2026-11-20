# canton-lens (ZabPay 익스플로러) — 서버에서 docker compose 로 직접 띄우는 배포
#
# 이 Makefile 은 ZabPay 배포용 포크(dsrvlabs/zabpay-canton-lens)에만 있다.
# 원본(dsrvlabs/canton-lens)에는 없고, 원본의 배포 절차(docker/compose.yaml 머리말)를
# 그대로 감싼다:
#   docker compose -f docker/compose.yaml up -d --build
#
# 레지스트리 push 없음 — 이미지는 이 명령을 돌리는 서버에서 소스로 직접 빌드된다
# (compose.yaml 의 build.context: .. 가 저장소 루트를 읽는다).
#
# docker/.env 는 레포에 없다 (.gitignore 가 .env* 를 막고 .env.example 만 예외).
# fetch-secrets 가 AWS Secrets Manager 에서 받아 그 자리에 만든다.
#
# 값을 바꿨을 때 무엇을 돌려야 하는지는 값이 읽히는 시점에 달려 있다:
#   VITE_* (프론트 번들에 박힘)      → make deploy   (이미지 재빌드)
#   그 밖의 값 (백엔드 기동 시 읽음) → make restart  (재빌드 없음)

.PHONY: fetch-secrets build-env deploy restart stop ps logs check clean help

.DEFAULT_GOAL := help

SECRET_ID ?=
COMPOSE := docker compose -f docker/compose.yaml

## Setup
fetch-secrets: ## Secrets Manager → docker/.env (SECRET_ID=<이름|ARN> 필요)
	@test -n "$(SECRET_ID)" || { echo "fetch-secrets: SECRET_ID 필요 (make fetch-secrets SECRET_ID=<arn>)"; exit 1; }
	./tools/fetch-secrets.sh "$(SECRET_ID)"

build-env: ## docker/.env 가 있고 compose.yaml 의 필수 변수를 채우는지 확인 (값은 출력 안 함)
	@test -f docker/.env || { echo "build-env: docker/.env 없음 — fetch-secrets 먼저"; exit 1; }
	@$(COMPOSE) config --quiet
	@echo "build-env: ok (docker/.env)"

## Deploy
deploy: build-env ## 이미지 빌드 후 기동 (up -d --build)
	$(COMPOSE) up -d --build

restart: build-env ## 재빌드 없이 다시 기동 — 백엔드 값만 바뀌었을 때
	$(COMPOSE) up -d --force-recreate

stop: ## 컨테이너 내림 (down)
	$(COMPOSE) down

## Inspect
ps: ## 컨테이너 상태
	$(COMPOSE) ps

logs: ## 컨테이너 로그 (follow)
	$(COMPOSE) logs -f --tail=200

check: ## 프론트(/)와 백엔드(/openapi.json)가 응답하는지 확인
	@port=$$($(COMPOSE) port frontend 80) || { echo "check: frontend 컨테이너가 떠 있지 않음"; exit 1; }; \
	for path in / /openapi.json; do \
	  ok=0; \
	  for i in 1 2 3 4 5 6 7 8 9 10; do \
	    if curl -fsS -o /dev/null "http://$$port$$path"; then ok=1; break; fi; \
	    sleep 3; \
	  done; \
	  test $$ok -eq 1 || { echo "check: http://$$port$$path 응답 없음"; exit 1; }; \
	  echo "check: ok http://$$port$$path"; \
	done

clean: ## 컨테이너와 로컬 빌드 이미지 삭제 (다음 deploy 에서 완전 재빌드)
	$(COMPOSE) down --rmi local

## Help
help: ## 도움말
	@echo ""
	@echo "canton-lens (ZabPay 익스플로러)"
	@echo ""
	@echo "Usage:"
	@echo "  make <target> [SECRET_ID=<id>]"
	@echo ""
	@echo "배포 순서:"
	@echo "  fetch-secrets → deploy → check"
	@echo ""
	@echo "Targets:"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""
