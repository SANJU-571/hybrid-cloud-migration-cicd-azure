# Lowest-cost profile (~US$3-4/day): same network, security, data, backup
# and monitoring design, but the web tier sits behind a Standard Load
# Balancer instead of Application Gateway WAF_v2.
environment            = "lowcost"
location               = "canadacentral"
connectivity_mode      = "peering"
enable_app_gateway_waf = false
enable_front_door      = false
enable_ddos_protection = false
enable_aks             = false
deploy_onprem_test_vms = true
web_instance_min       = 2
web_instance_max       = 3
monthly_budget_usd     = 75
