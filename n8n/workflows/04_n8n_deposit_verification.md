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
FICHIER: /docs/architecture_security_specs.md
code
Markdown
# Spécifications Techniques : Flux de Dépôt et Sécurisation - MBOKA ELENGI

## 1. Flux Transactionnel (Dépôts Mobile Money)
Le traitement de la réconciliation des dépôts repose sur un modèle asynchrone sécurisé, éliminant les injections ou modifications frauduleuses de solde par le client.

### Cinématique d'un Dépôt
1. **Initiation** : L'utilisateur effectue un transfert de fonds de manière externe sur l'un de nos numéros d'acquisition marchands (Orange Money, M-Pesa/Vodacom, Africell Money, Airtel Money).
2. **Déclaration** : L'utilisateur colle l'ID de transaction reçu par SMS dans l'application mobile.
3. **Persistance Initiale** : L'ID, l'opérateur, le numéro émetteur et le montant revendiqué sont insérés dans la table `deposit_claims`. L'état par défaut est `PENDING`.
4. **Surveillance & Capture** : Le webhook ou déclencheur planifié de n8n intercepte l'insertion de l'état `PENDING`.
5. **Vérification Externe** : n8n effectue une requête API HTTP vers la passerelle de logs SMS de nos téléphones d'acquisition ou les API opérateurs pour récupérer le SMS de confirmation officiel correspondant à l'ID de transaction soumis.
6. **Réconciliation Comptable (Comptable Virtuel)** :
   - n8n compare l'expéditeur, le montant et l'ID de transaction réclamés avec la preuve opérateur.
   - Si les données correspondent exactement : Appel de la procédure stockée atomique `validate_and_credit_deposit`.
   - En cas d'incohérence ou d'ID inexistant : Mise à jour du statut en `REJECTED`.

---

## 2. Sécurisation et Isolation des Données (Zero Trust Client)
L'application cliente est considérée comme un environnement non sécurisé. Par conséquent, aucune requête SQL directe de type `UPDATE` ou `INSERT` sur les tables financières n'est autorisée depuis le frontend.

### Stratégie d'isolation
- **Vue Lecture Seule** : L'application cliente ne peut accéder qu'aux soldes (`users_balance`) et historiques via des requêtes `SELECT` restrictives protégées par des politiques RLS (Row Level Security).
- **Immuabilité (Ledger Pattern)** : Le solde de l'utilisateur n'est jamais modifié par une commande directe. Chaque crédit ou débit génère une écriture immuable dans `ledger_entries`. Le solde final dans `users_balance` est le reflet de la somme algébrique du grand livre, recalculé et mis à jour de façon atomique via la procédure stockée PostgreSQL.
- **Rôle de "Comptable" de n8n** : n8n n'a pas d'accès direct de modification sur la table `users_balance`. Il doit obligatoirement transiter par la procédure stockée `validate_and_credit_deposit()`. La fonction valide en premier lieu l'état `PENDING` de la réclamation sous un verrou d'écriture (`FOR UPDATE`), interdisant le rejeu d'une transaction (Replay Attack).

---

## 3. Gestion de la Trésorerie (Acquisition -> Trésorerie d'Entreprise)
Pour maximiser les marges et réduire l'impact des frais d'opérateurs mobiles (Push/Pull, frais de transfert), le rapatriement des fonds des comptes d'acquisition vers la trésorerie de l'entreprise s'appuie sur une règle de déclenchement mixte.

### Logique d'Équilibrage (Sweeping Logic)
* **Seuil de volume** : **$500.00 USD** (ou équivalent CDF) par opérateur [1].
* **Seuil temporel (Backup)** : Toutes les **24 heures** (à 23h00 UTC, période de charge réseau faible).
* **Raisonnement de rentabilité** : Les frais fixes d'opérateurs sur les retraits de masse sont dégressifs ou plafonnés à partir de paliers spécifiques. Effectuer des transferts constants pour de petites sommes détruit la marge brute. Un déclenchement par bloc de $500.00 amortit de façon optimale les frais fixes par transaction de transfert.

---

## 4. Gestion des Erreurs et Circuit Breaker
Pour éliminer les risques de désynchronisation de l'état financier de l'utilisateur lors de défaillances réseau ou de pannes n8n.

### Mécanisme "Circuit Breaker" et Fiabilité n8n
1. **Échec de l'appel Passerelle Opérateur** : n8n est configuré avec une stratégie de rejeu automatique (`retryOnFail: true`, 3 tentatives espacées de 5 secondes).
2. **Persistance en cas de Crash complet** : Si le service n8n est éteint au moment de la transaction, les transactions en attente restent à l'état `PENDING` dans Supabase. Lors du redémarrage de n8n, le processus reprend les réclamations là où elles s'étaient arrêtées (aucune perte de transaction, état idempotent).
3. **Sécurité d'Achat (Anti-Double Débit)** : Lors d'un achat initié par l'utilisateur :
   - L'achat est encapsulé dans une transaction PostgreSQL globale.
   - Le système vérifie si le solde dans `users_balance` est suffisant.
   - Si l'appel externe de confirmation de l'achat échoue, la transaction de débit sur la base de données subit un rollback complet (`ROLLBACK`). Le solde de l'utilisateur reste intact tant que l'acquittement de la commande d'achat n'est pas validé à 100%.
