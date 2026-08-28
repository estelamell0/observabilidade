package main

import rego.v1

deny contains msg if {
    # Suporta tanto Pods quanto Deployments
    container := input.spec.template.spec.containers[_] 
    endswith(container.image, ":latest")
    msg := sprintf("Container '%s' não pode usar a tag :latest", [container.name])
}
