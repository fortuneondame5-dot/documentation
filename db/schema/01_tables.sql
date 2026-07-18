-- Active l'extension UUID pour la génération des clés
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Type énuméré pour les opérateurs de téléphonie mobile
CREATE TYPE mobile_operator AS ENUM ('ORANGE', 'VODACOM', 'AFRICELL', 'AIRTEL');

-- Type énuméré pour le statut de la réclamation du dépôt
CREATE TYPE deposit_status AS ENUM ('PENDING', 'VALIDATED', 'REJECTED');

-- Type énuméré pour le type de mouvement dans le grand livre (Ledger)
CREATE TYPE ledger_entry_type AS ENUM ('CREDIT', 'DEBIT');

-- Table des soldes utilisateurs (Lecture seule pour l'interface client)
CREATE TABLE public.users_balance (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    balance NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CONSTRAINT positive_balance CHECK (balance >= 0.00),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Table des réclamations de dépôts initiées par les utilisateurs
CREATE TABLE public.deposit_claims (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    transaction_id VARCHAR(100) NOT NULL UNIQUE,
    operator mobile_operator NOT NULL,
    claimed_amount NUMERIC(12, 2) NOT NULL CONSTRAINT positive_claimed_amount CHECK (claimed_amount > 0),
    sender_phone VARCHAR(20) NOT NULL,
    status deposit_status NOT NULL DEFAULT 'PENDING',
    operator_raw_response JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    validated_at TIMESTAMP WITH TIME ZONE
);

-- Index pour accélérer les vérifications de n8n sur les réclamations en attente
CREATE INDEX idx_deposit_claims_status_tx ON public.deposit_claims(status, transaction_id);

-- Grand livre comptable (Double-entrée, immuable)
CREATE TABLE public.ledger_entries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    amount NUMERIC(12, 2) NOT NULL CONSTRAINT non_zero_amount CHECK (amount <> 0),
    entry_type ledger_entry_type NOT NULL,
    reference_id UUID NOT NULL, -- Référence vers l'entité source (ex: deposit_claims.id ou purchases.id)
    reference_table VARCHAR(50) NOT NULL, -- Nom de la table source pour traçabilité
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Index pour la reconstruction rapide du solde à partir du grand livre
CREATE INDEX idx_ledger_entries_user_id ON public.ledger_entries(user_id);

-- Table de suivi de la Trésorerie d'Acquisition vers Trésorerie d'Entreprise
CREATE TABLE public.treasury_vault (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    operator mobile_operator NOT NULL,
    acquisition_wallet_phone VARCHAR(20) NOT NULL UNIQUE,
    current_balance NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    threshold_volume NUMERIC(12, 2) NOT NULL DEFAULT 500.00, -- Seuil volumétrique en USD/CDF pour déclencher le transfert
    last_sweep_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);