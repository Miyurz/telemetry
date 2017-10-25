.PHONY: apply

VAR_FILES=-var-file="prod.tfvars"
PLAN_OUTPUT=tf-plan-op

init:
	terraform init

ifdef op
plan: validate
	terraform plan ${VAR_FILES} -out ${op}
else
plan: validate
	terraform plan ${VAR_FILES} -out ${PLAN_OUTPUT}
endif

ifdef op
apply: validate
	$(info op defined)
	@echo Output file  is $(op)
	terraform apply "$(op)"
else
apply: validate plan 
	$(info op undefined)
	terraform apply ${PLAN_OUTPUT}
endif

validate:
	terraform validate ${VAR_FILES}

destroy:
	terraform destroy ${VAR_FILES} -force

clean:
	rm -rf terraform.tfstate terraform.tfstate.backup 


ifdef verbose
run:
	ansible-playbook ${verbose} -i inventory prometheus-servers.yml
else
run:
	ansible-playbook -i inventory prometheus-servers.yml
endif
