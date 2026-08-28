#!/usr/bin/env python3
import hashlib
import json
import time

# Eventos simulados de aprovação no pipeline de CI/CD
events = [
    {"action": "PR_CREATED", "user": "dev1", "pr_id": 101, "repo": "api-pagamentos"},
    {"action": "SAST_SCAN", "status": "PASSED", "tools": "sonar", "pr_id": 101},
    {"action": "SCA_SCAN", "status": "PASSED", "tools": "snyk", "pr_id": 101},
    {"action": "PR_APPROVED", "user": "techlead", "pr_id": 101, "justification": "LGTM"},
    {"action": "MERGED", "user": "dev1", "pr_id": 101, "commit": "a1b2c3d4"},
    {"action": "IMAGE_BUILD", "image": "api-pagamentos:v1.2", "commit": "a1b2c3d4"},
    {"action": "IMAGE_SIGN", "image": "api-pagamentos:v1.2", "signer": "cosign-ci"},
    {"action": "DEPLOY_STAGING", "image": "api-pagamentos:v1.2", "env": "staging"},
    {"action": "PROD_APPROVAL", "user": "change-manager", "ticket": "CHG-9999", "env": "prod"},
    {"action": "DEPLOY_PROD", "image": "api-pagamentos:v1.2", "env": "prod"}
]

# Inicializa a trilha (chain)
audit_chain = []
# O hash do "gênesis" (antes do primeiro bloco)
previous_hash = "0000000000000000000000000000000000000000000000000000000000000000"

print("--- Gerando Trilha de Auditoria (Hash Chaining) ---\n")

for idx, event in enumerate(events):
    # Adicionamos metadata importante para auditoria
    event_record = {
        "index": idx,
        "timestamp": int(time.time() * 1000) + idx, # timestamp falso crescente
        "event_data": event,
        "previous_hash": previous_hash
    }
    
    # Serializamos deterministicamente (sort_keys=True é fundamental para consistência)
    event_bytes = json.dumps(event_record, sort_keys=True).encode('utf-8')
    
    # Calculamos o hash do evento atual
    current_hash = hashlib.sha256(event_bytes).hexdigest()
    
    event_record["hash"] = current_hash
    audit_chain.append(event_record)
    
    print(f"[{idx}] {event['action']} -> Hash: {current_hash[:8]}...")
    
    previous_hash = current_hash

print("\nTrilha gerada com sucesso e pronta para ir ao SIEM/S3 Object Lock (WORM).")

print("\n--- Simulando Auditoria (Verify Chain) ---")
print("1. Validando a trilha intacta...")

def verify_chain(chain):
    is_valid = True
    prev_hash = "0000000000000000000000000000000000000000000000000000000000000000"
    
    for i, record in enumerate(chain):
        # Remove o hash do próprio registro para recalcular
        record_copy = dict(record)
        expected_hash = record_copy.pop("hash")
        
        # Verifica se o elo anterior bate
        if record_copy["previous_hash"] != prev_hash:
            print(f"❌ [ERRO] Elo quebrado no índice {i}! previous_hash não bate.")
            is_valid = False
            break
            
        # Recalcula o hash atual
        recalculated_bytes = json.dumps(record_copy, sort_keys=True).encode('utf-8')
        recalculated_hash = hashlib.sha256(recalculated_bytes).hexdigest()
        
        if recalculated_hash != expected_hash:
            print(f"❌ [ERRO] Adulteração detectada no índice {i}! O hash gravado ({expected_hash[:8]}...) não corresponde ao conteúdo ({recalculated_hash[:8]}...).")
            is_valid = False
            break
            
        prev_hash = expected_hash
        
    if is_valid:
        print("✅ A trilha é válida e íntegra!")

verify_chain(audit_chain)

print("\n2. Simulando um atacante alterando a aprovação no banco de dados...")
print("Atacante altera o índice 3 (PR_APPROVED) mudando a justificativa.")

# Atacante adultera os dados (mas não consegue refazer todos os hashes da cadeia WORM)
audit_chain[3]["event_data"]["justification"] = "OVERRIDE - BYPASS SECURITY"

print("Validando novamente...")
verify_chain(audit_chain)
