package ci

import rego.v1

# Reprova o gate de SAST quando há findings críticos
deny contains msg if {
    input.gate == "sast"
    input.findings.critical > 0
    msg := sprintf("Gate SAST reprovado: %d findings críticos", [input.findings.critical])
}
