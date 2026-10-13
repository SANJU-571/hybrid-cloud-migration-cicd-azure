# Full production-style profile - every service from the design document.
# WARNING: DDoS Network Protection alone is ~US$2,950/month.
# Only deploy on a funded/sponsored subscription, and destroy promptly.
environment               = "full"
location                  = "canadacentral"
connectivity_mode         = "vpn"
enable_app_gateway_waf    = true
enable_front_door         = true
enable_ddos_protection    = true
enable_defender_for_cloud = true
deploy_onprem_test_vms    = true
web_instance_min          = 2
web_instance_max          = 6
storage_replication       = "GZRS"
backup_geo_redundant      = true
monthly_budget_usd        = 4000
