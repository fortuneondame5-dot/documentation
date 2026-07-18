-- Activer la sécurité Row Level Security (RLS) sur toutes les tables sensibles
ALTER TABLE public.users_balance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deposit_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ledger_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.treasury_vault ENABLE ROW LEVEL SECURITY;

-----------------------------------------
-- POLITIQUES POUR USERS_BALANCE
-----------------------------------------
-- L'utilisateur peut uniquement lire son propre solde
CREATE POLICY select_own_balance ON public.users_balance
    FOR SELECT
    USING (auth.uid() = user_id);

-- Interdiction totale de modification ou d'insertion directe par l'utilisateur
CREATE POLICY deny_insert_on_balance ON public.users_balance FOR INSERT WITH CHECK (false);
CREATE POLICY deny_update_on_balance ON public.users_balance FOR UPDATE USING (false);
CREATE POLICY deny_delete_on_balance ON public.users_balance FOR DELETE USING (false);

-----------------------------------------
-- POLITIQUES POUR DEPOSIT_CLAIMS
-----------------------------------------
-- L'utilisateur peut insérer ses propres réclamations
CREATE POLICY insert_own_deposit_claim ON public.deposit_claims
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- L'utilisateur peut voir l'historique de ses propres réclamations
CREATE POLICY select_own_deposit_claims ON public.deposit_claims
    FOR SELECT
    USING (auth.uid() = user_id);

-- Interdiction pour l'utilisateur de modifier ou de supprimer ses réclamations de dépôt
CREATE POLICY deny_update_on_deposit_claims ON public.deposit_claims FOR UPDATE USING (false);
CREATE POLICY deny_delete_on_deposit_claims ON public.deposit_claims FOR DELETE USING (false);

-----------------------------------------
-- POLITIQUES POUR LEDGER_ENTRIES
-----------------------------------------
-- L'utilisateur peut uniquement lire ses entrées de grand livre
CREATE POLICY select_own_ledger_entries ON public.ledger_entries
    FOR SELECT
    USING (auth.uid() = user_id);

-- Interdiction totale de modification, insertion ou suppression directe du Ledger
CREATE POLICY deny_insert_on_ledger ON public.ledger_entries FOR INSERT WITH CHECK (false);
CREATE POLICY deny_update_on_ledger ON public.ledger_entries FOR UPDATE USING (false);
CREATE POLICY deny_delete_on_ledger ON public.ledger_entries FOR DELETE USING (false);

-----------------------------------------
-- POLITIQUES POUR TREASURY_VAULT
-----------------------------------------
-- Seul le rôle de service (n8n/admin) a accès à la trésorerie. Zéro accès utilisateur.
CREATE POLICY deny_all_on_treasury ON public.treasury_vault
    FOR ALL
    USING (false);
FICHIER: /n8n/workflows/04_n8n_deposit_verification.json
code
JSON
{
  "name": "MBOKA_ELENGI_Deposit_Verification",
  "nodes": [
    {
      "parameters": {
        "pollTimes": {
          "item": [
            {
              "mode": "everyMinute"
            }
          ]
        },
        "documentId": "deposit_claims",
        "event": "row_inserted",
        "filters": {
          "status": "PENDING"
        }
      },
      "name": "Supabase Trigger - New Pending Claim",
      "type": "n8n-nodes-base.supabaseTrigger",
      "typeVersion": 1,
      "position": [250, 300]
    },
    {
      "parameters": {
        "url": "https://api.gateway-sms.local/v1/messages",
        "authentication": "predefinedCredentialType",
        "nodeCredentialType": "httpBasicAuth",
        "options": {},
        "queryParameters": {
          "operator": "={{$node[\"Supabase Trigger - New Pending Claim\"].json[\"operator\"]}}",
          "query": "={{$node[\"Supabase Trigger - New Pending Claim\"].json[\"transaction_id\"]}}"
        }
      },
      "name": "Fetch Operator SMS Gateway Logs",
      "type": "n8n-nodes-base.httpRequest",
      "typeVersion": 4,
      "position": [470, 300],
      "retryOnFail": true,
      "maxRetries": 3,
      "waitBetweenRetries": 5000
    },
    {
      "parameters": {
        "conditions": {
          "string": [
            {
              "value1": "={{$node[\"Fetch Operator SMS Gateway Logs\"].json[\"status\"]}}",
              "value2": "SUCCESS"
            },
            {
              "value1": "={{$node[\"Fetch Operator SMS Gateway Logs\"].json[\"transaction_id\"]}}",
              "value2": "={{$node[\"Supabase Trigger - New Pending Claim\"].json[\"transaction_id\"]}}"
            }
          ],
          "number": [
            {
              "value1": "={{$node[\"Fetch Operator SMS Gateway Logs\"].json[\"amount\"]}}",
              "value2": "={{$node[\"Supabase Trigger - New Pending Claim\"].json[\"claimed_amount\"]}}"
            }
          ]
        }
      },
      "name": "Validate Core Fields",
      "type": "n8n-nodes-base.if",
      "typeVersion": 1,
      "position": [690, 300]
    },
    {
      "parameters": {
        "operation": "callProcedure",
        "schema": "public",
        "procedure": "validate_and_credit_deposit",
        "parameters": {
          "p_claim_id": "={{$node[\"Supabase Trigger - New Pending Claim\"].json[\"id\"]}}",
          "p_verified_amount": "={{$node[\"Fetch Operator SMS Gateway Logs\"].json[\"amount\"]}}",
          "p_operator_raw_data": "={{$node[\"Fetch Operator SMS Gateway Logs\"].json}}"
        }
      },
      "name": "Execute Postgres Atomic Crediting",
      "type": "n8n-nodes-base.supabase",
      "typeVersion": 1,
      "position": [920, 200]
    },
    {
      "parameters": {
        "operation": "update",
        "table": "deposit_claims",
        "id": "={{$node[\"Supabase Trigger - New Pending Claim\"].json[\"id\"]}}",
        "fields": {
          "status": "REJECTED",
          "operator_raw_response": "={{$node[\"Fetch Operator SMS Gateway Logs\"].json}}"
        }
      },
      "name": "Mark Claim as Rejected",
      "type": "n8n-nodes-base.supabase",
      "typeVersion": 1,
      "position": [920, 420]
    }
  ],
  "connections": {
    "Supabase Trigger - New Pending Claim": {
      "main": [
        [
          {
            "node": "Fetch Operator SMS Gateway Logs",
            "index": 0
          }
        ]
      ]
    },
    "Fetch Operator SMS Gateway Logs": {
      "main": [
        [
          {
            "node": "Validate Core Fields",
            "index": 0
          }
        ]
      ]
    },
    "Validate Core Fields": {
      "main": [
        [
          {
            "node": "Execute Postgres Atomic Crediting",
            "index": 0
          }
        ],
        [
          {
            "node": "Mark Claim as Rejected",
            "index": 0
          }
        ]
      ]
    }
  }
}