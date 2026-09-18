-- =========================================================================
-- SISTEMA ELO DINÁMICO PARA TETRIS NOW (0006_sistema_elo_dinamico.sql)
-- Reglas de Negocio:
-- 1. Ganar otorga entre +60 y +100 puntos según rapidez e intensidad.
-- 2. Perder descuenta entre -50 y -90 puntos bajo el mismo criterio.
-- 3. Abandono voluntario / rendición aplica la penalización máxima de -90 puntos.
-- 4. Piso de rating seguro en 100 puntos (no negativo).
-- 5. Todo estrictamente contenido en el esquema 'tetris'.
-- =========================================================================

CREATE OR REPLACE FUNCTION tetris.actualizar_rating_elo(
    p_winner_user_id UUID,
    p_loser_user_id UUID,
    p_payload JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'tetris', 'public'
AS $$
DECLARE
    v_r_winner INT;
    v_r_loser INT;
    v_winner_delta INT := 60;
    v_loser_delta INT := 50;
    v_duration_seconds NUMERIC;
    v_lines_sent INT;
    v_max_combo INT;
    v_speed_factor NUMERIC := 0.0;
    v_intensity_factor NUMERIC := 0.0;
    v_is_surrender BOOLEAN := false;
BEGIN
    -- Asegurar existencia de registros de rating
    INSERT INTO tetris.ratings (user_id, rating, wins, losses, matches_played)
    VALUES (p_winner_user_id, 1000, 0, 0, 0)
    ON CONFLICT (user_id) DO NOTHING;

    INSERT INTO tetris.ratings (user_id, rating, wins, losses, matches_played)
    VALUES (p_loser_user_id, 1000, 0, 0, 0)
    ON CONFLICT (user_id) DO NOTHING;

    SELECT rating INTO v_r_winner FROM tetris.ratings WHERE user_id = p_winner_user_id;
    SELECT rating INTO v_r_loser FROM tetris.ratings WHERE user_id = p_loser_user_id;

    -- Extraer métricas de combate si vienen en p_payload
    v_is_surrender := COALESCE((p_payload->>'is_surrender')::BOOLEAN, false);
    v_duration_seconds := COALESCE((p_payload->>'duration_seconds')::NUMERIC, 60.0);
    v_lines_sent := COALESCE((p_payload->>'lines_sent')::INT, 4);
    v_max_combo := COALESCE((p_payload->>'max_combo')::INT, 1);

    -- Si el cliente envió deltas ya calculados por el motor
    IF p_payload ? 'elo_delta_winner' AND p_payload ? 'elo_delta_loser' THEN
        v_winner_delta := LEAST(100, GREATEST(60, (p_payload->>'elo_delta_winner')::INT));
        v_loser_delta := LEAST(90, GREATEST(50, ABS((p_payload->>'elo_delta_loser')::INT)));
    ELSE
        -- Cálculo de factor de velocidad: partidas rápidas (<45s) dan factor 1.0, lentas (>180s) factor 0.0
        v_speed_factor := LEAST(1.0, GREATEST(0.0, (180.0 - LEAST(180.0, GREATEST(30.0, v_duration_seconds))) / 150.0));

        -- Factor de intensidad basado en ataques enviados y combos
        v_intensity_factor := LEAST(1.0, GREATEST(0.0, (v_lines_sent / 12.0 * 0.6) + (v_max_combo / 5.0 * 0.4)));

        -- Ganador: 60 base + hasta 40 puntos adicionales (60 a 100)
        v_winner_delta := LEAST(100, GREATEST(60, ROUND(60 + (v_speed_factor * 20.0) + (v_intensity_factor * 20.0))));

        -- Perdedor: 50 base + penalización por ser aplastado rápido / nula intensidad (50 a 90)
        IF v_is_surrender THEN
            v_loser_delta := 90;
        ELSE
            v_loser_delta := LEAST(90, GREATEST(50, ROUND(50 + (v_speed_factor * 20.0) + ((1.0 - v_intensity_factor) * 20.0))));
        END IF;
    END IF;

    -- Actualizar al Ganador
    UPDATE tetris.ratings
    SET rating = v_r_winner + v_winner_delta,
        wins = wins + 1,
        matches_played = matches_played + 1,
        updated_at = now()
    WHERE user_id = p_winner_user_id;

    -- Actualizar al Perdedor (con piso de 100 de ELO)
    UPDATE tetris.ratings
    SET rating = GREATEST(100, v_r_loser - v_loser_delta),
        losses = losses + 1,
        matches_played = matches_played + 1,
        updated_at = now()
    WHERE user_id = p_loser_user_id;

    RETURN jsonb_build_object(
        'winner_delta', v_winner_delta,
        'loser_delta', -v_loser_delta,
        'winner_new_rating', v_r_winner + v_winner_delta,
        'loser_new_rating', GREATEST(100, v_r_loser - v_loser_delta)
    );
END;
$$;

-- Actualizar penalización de abandono a -90 puntos ELO con piso de 100
CREATE OR REPLACE FUNCTION tetris.penalizar_abandono(p_match_id uuid, p_user_id uuid)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = tetris, public
AS $$
DECLARE
  v_rating int;
  v_penalty int := 90;
BEGIN
  SELECT rating INTO v_rating FROM tetris.ratings WHERE user_id = p_user_id;
  IF v_rating IS NULL THEN
    RETURN;
  END IF;

  UPDATE tetris.ratings
    SET rating = GREATEST(100, rating - v_penalty),
        losses = losses + 1,
        matches_played = matches_played + 1,
        updated_at = now()
    WHERE user_id = p_user_id;
END;
$$;

-- Permisos de ejecución
GRANT EXECUTE ON FUNCTION tetris.actualizar_rating_elo(UUID, UUID, JSONB) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION tetris.penalizar_abandono(UUID, UUID) TO authenticated, service_role;
