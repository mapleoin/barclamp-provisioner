
name "provisioner-base"
description "Provisioner Base role - Apt and Networking"
run_list(
         "recipe[utils]", 
         "recipe[barclamp]" 
)
default_attributes()
override_attributes()
