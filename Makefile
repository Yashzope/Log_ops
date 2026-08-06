# =============================================================================
# LogOps — common Make targets (Git Bash / WSL / Linux / macOS)
# =============================================================================

.PHONY: secrets tf-plan tf-apply local-up local-kafka lite health smoke destroy help

help:
	@echo "LogOps targets:"
	@echo "  make secrets      - create .env and fill random passwords"
	@echo "  make lite         - fastest local demo (no Airflow)"
	@echo "  make local-kafka  - full compose + local Kafka + processor"
	@echo "  make tf-plan      - terraform init/validate/plan"
	@echo "  make tf-apply     - terraform apply"
	@echo "  make health       - run health-check.sh"
	@echo "  make smoke        - run smoke-test.sh"
	@echo "  make destroy      - terraform destroy (careful!)"

secrets:
	bash scripts/generate-secrets.sh

lite:
	bash scripts/start-local.sh 2>/dev/null || true
	docker compose -f docker-compose.lite.yml up -d --build

tf-plan:
	bash scripts/setup-terraform.sh

tf-apply:
	cd aws-infra && terraform apply -input=false -auto-approve

local-up:
	export AIRFLOW_UID=$$(id -u); docker compose up -d --build

local-kafka:
	bash scripts/start-local.sh

health:
	bash scripts/health-check.sh

smoke:
	bash scripts/smoke-test.sh

destroy:
	cd aws-infra && terraform destroy
