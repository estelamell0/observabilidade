package main

import rego.v1

deny contains msg if {
    # Suporta tanto Pods quanto Deployments
    container := input.spec.template.spec.containers[_] 
    # c := input.spec.containers[_] - ERRADO
    not container.securityContext.runAsNonRoot
    msg := sprintf("Container '%s' deve rodar como non-root (securityContext.runAsNonRoot = true)", [container.name])
}
