COMPOSE ?= docker compose
TF_DIR  ?= terraform
TF_VARS ?= -var-file=environments/lab/terraform.tfvars

.PHONY: up down logs ps load seed reset tf-init tf-plan tf-apply tf-destroy

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f --tail=100 otel-collector

ps:
	$(COMPOSE) ps

load:
	$(COMPOSE) --profile load up -d

seed:
	./loadgen/generate.sh localhost

reset:
	$(COMPOSE) --profile load down -v

tf-init:
	cd $(TF_DIR) && terraform init

tf-plan:
	cd $(TF_DIR) && terraform plan "$(TF_VARS)" -out=tfplan

tf-apply:
	cd $(TF_DIR) && terraform apply tfplan

tf-destroy:
	cd $(TF_DIR) && terraform destroy "$(TF_VARS)"
