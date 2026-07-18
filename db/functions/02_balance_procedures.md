-- Procédure stockée d'écriture dans le Ledger et mise à jour du solde (Atomique)
CREATE OR REPLACE FUNCTION public.validate_and_credit_deposit(
    p_claim_id UUID,
    p_verified_amount NUMERIC(12, 2),
    p_operator_raw_data JSONB
)
RETURNS BOOLEAN AS $$
DECLARE
    v_user_id UUID;
    v_status deposit_status;
    v_tx_id VARCHAR(100);
BEGIN
    -- 1. Verrouiller la ligne de réclamation pour éviter les Race Conditions
    SELECT user_id, status, transaction_id INTO v_user_id, v_status, v_tx_id
    FROM public.deposit_claims
    WHERE id = p_claim_id
    FOR UPDATE;

    -- 2. Sécurité : Vérifier que la réclamation est toujours en attente
    IF v_status <> 'PENDING' THEN
        RAISE EXCEPTION 'Transaction déjà traitée ou invalide. Statut actuel: %', v_status;
    END IF;

    -- 3. Mettre à jour l'état de la réclamation
    UPDATE public.deposit_claims
    SET status = 'VALIDATED',
        operator_raw_response = p_operator_raw_data,
        validated_at = timezone('utc'::text, now())
    WHERE id = p_claim_id;

    -- 4. Insérer l'écriture de crédit dans le grand livre (Ledger)
    INSERT INTO public.ledger_entries (
        user_id,
        amount,
        entry_type,
        reference_id,
        reference_table
    ) VALUES (
        v_user_id,
        p_verified_amount,
        'CREDIT',
        p_claim_id,
        'deposit_claims'
    );

    -- 5. Mettre à jour le solde utilisateur (ou l'insérer s'il n'existe pas)
    INSERT INTO public.users_balance (user_id, balance, updated_at)
    VALUES (v_user_id, p_verified_amount, timezone('utc'::text, now()))
    ON CONFLICT (user_id) DO UPDATE
    SET balance = public.users_balance.balance + p_verified_amount,
        updated_at = timezone('utc'::text, now());

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        -- Tout échoue ou tout réussit (Rollback automatique de la transaction PostgreSQL)
        RAISE EXCEPTION 'Échec de l''opération atomique de crédit : %', SQLERRM;
        RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
