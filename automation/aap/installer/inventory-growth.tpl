# AAP 2.7 containerized installer - growth topology, all-in-one on aap-01.
# Derived from the `inventory-growth` example shipped in the setup tarball.
# Dollar-brace placeholders are filled by installer/render.sh from .env.
# The rendered file holds credentials, so it lives in installer/.rendered/ (gitignored)
# and is shredded on aap-01 after the install.

[automationgateway]
${AAP_FQDN}

[automationcontroller]
${AAP_FQDN}

[automationhub]
${AAP_FQDN}

[automationeda]
${AAP_FQDN}

[automationmetrics]
${AAP_FQDN}

[database]
${AAP_FQDN}

[all:vars]
ansible_connection=local

# Common
postgresql_admin_username=postgres
postgresql_admin_password=${AAP_PG_PASSWORD}
registry_username=${REDHAT_REGISTRY_USERNAME}
registry_password=${REDHAT_REGISTRY_PASSWORD}
redis_mode=standalone

# Platform gateway. Single entry point is the Envoy proxy on 443 (gateway nginx on 8446 is internal)
gateway_admin_password=${AAP_ADMIN_PASSWORD}
gateway_pg_host=${AAP_FQDN}
gateway_pg_password=${AAP_PG_PASSWORD}
gateway_main_url=https://${AAP_HOST}

# Automation controller
controller_admin_password=${AAP_ADMIN_PASSWORD}
controller_pg_host=${AAP_FQDN}
controller_pg_password=${AAP_PG_PASSWORD}
controller_percent_memory_capacity=0.5

# Automation hub
hub_admin_password=${AAP_ADMIN_PASSWORD}
hub_pg_host=${AAP_FQDN}
hub_pg_password=${AAP_PG_PASSWORD}
hub_seed_collections=false

# Event-Driven Ansible
eda_admin_password=${AAP_ADMIN_PASSWORD}
eda_pg_host=${AAP_FQDN}
eda_pg_password=${AAP_PG_PASSWORD}

# Automation metrics (new in 2.7)
automationmetrics_pg_host=${AAP_FQDN}
automationmetrics_pg_password=${AAP_PG_PASSWORD}
automationmetrics_controller_read_pg_host=${AAP_FQDN}
automationmetrics_controller_read_pg_password=${AAP_PG_PASSWORD}
