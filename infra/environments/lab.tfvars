# Lab profile - every layer of the design runs for real, at the lowest cost.
# Approx. US$12-15/day while running. Destroy after demos.
environment            = "lab"
location               = "canadacentral"
connectivity_mode      = "peering" # switch to "vpn" to demo the IPsec tunnel (+~US$10/day, 30-45 min build)
enable_app_gateway_waf = true
enable_front_door      = false
enable_ddos_protection = false
deploy_onprem_test_vms = true
web_instance_min       = 2
web_instance_max       = 4
monthly_budget_usd     = 150
