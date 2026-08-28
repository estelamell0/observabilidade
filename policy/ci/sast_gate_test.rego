package ci

import rego.v1

test_reprova_com_critico if {
    deny[_] with input as {"gate": "sast", "findings": {"critical": 2}}
}

test_aprova_sem_critico if {
    count(deny) == 0 with input as {"gate": "sast", "findings": {"critical": 0}}
}
