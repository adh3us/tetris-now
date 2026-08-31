-- =========================================================================
-- ESQUEMA TETRIS, SISTEMA DE AMIGOS & INTEGRACIÓN ECOSISTEMA GAMEROS
-- Proyecto Supabase ID: bgwvtfgwhpinfotzyucn
-- =========================================================================

-- 1. Esquema y Rol
CREATE SCHEMA IF NOT EXISTS tetris;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'tetris_app') THEN
        CREATE ROLE tetris_app NOLOGIN;
    END IF;
END $$;

GRANT USAGE ON SCHEMA tetris TO anon, authenticated, service_role, tetris_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA tetris GRANT ALL ON TABLES TO authenticated, service_role, tetris_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA tetris GRANT ALL ON SEQUENCES TO authenticated, service_role, tetris_app;

-- 2. Tabla de Ratings ELO propio (Base 1000)
CREATE TABLE IF NOT EXISTS tetris.ratings (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    rating INT NOT NULL DEFAULT 1000,
    matches_played INT NOT NULL DEFAULT 0,
    wins INT NOT NULL DEFAULT 0,
    losses INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. Tabla de Partidas con soporte para Códigos de Sala Alfanuméricos
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'match_format' AND typnamespace = 'tetris'::regnamespace) THEN
        CREATE TYPE tetris.match_format AS ENUM ('1v1', '2v2');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'match_status' AND typnamespace = 'tetris'::regnamespace) THEN
        CREATE TYPE tetris.match_status AS ENUM ('pending', 'ready_check', 'in_progress', 'finished', 'en_disputa', 'cancelled');
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS tetris.match_tetris (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_code TEXT,
    tournament_id UUID,
    round_number INT DEFAULT 1,
    format tetris.match_format NOT NULL DEFAULT '1v1',
    status tetris.match_status NOT NULL DEFAULT 'pending',
    team_1_id UUID NOT NULL,
    team_2_id UUID NOT NULL,
    winner_team_id UUID,
    team_1_armor_tier SMALLINT NOT NULL DEFAULT 0 CHECK (team_1_armor_tier BETWEEN 0 AND 2),
    team_2_armor_tier SMALLINT NOT NULL DEFAULT 0 CHECK (team_2_armor_tier BETWEEN 0 AND 2),
    team_1_lines_sent INT NOT NULL DEFAULT 0,
    team_2_lines_sent INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    started_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ
);

ALTER TABLE tetris.match_tetris ADD COLUMN IF NOT EXISTS room_code TEXT;
CREATE INDEX IF NOT EXISTS idx_tetris_room_code ON tetris.match_tetris(room_code);

CREATE TABLE IF NOT EXISTS tetris.match_tetris_players (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id UUID NOT NULL REFERENCES tetris.match_tetris(id) ON DELETE CASCADE,
    team_id UUID NOT NULL,
    user_id UUID NOT NULL REFERENCES auth.users(id),
    gamer_tag TEXT NOT NULL,
    is_alive BOOLEAN NOT NULL DEFAULT true,
    lines_cleared INT NOT NULL DEFAULT 0,
    lines_sent INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_tetris_player_match UNIQUE (match_id, user_id)
);

CREATE TABLE IF NOT EXISTS tetris.reportes_resultado (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id UUID NOT NULL REFERENCES tetris.match_tetris(id) ON DELETE CASCADE,
    reporter_user_id UUID NOT NULL REFERENCES auth.users(id),
    winner_team_id UUID NOT NULL,
    reported_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_player_report UNIQUE (match_id, reporter_user_id)
);

-- 4. SISTEMA DE AMIGOS OFICIAL DE GAMEROS (public.amigos)
CREATE TABLE IF NOT EXISTS public.amigos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    solicitante_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    receptor_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    estado TEXT NOT NULL DEFAULT 'pendiente' CHECK (estado IN ('pendiente', 'aceptada', 'rechazada', 'bloqueada')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_amigos_relacion UNIQUE (solicitante_id, receptor_id)
);

-- 5. Seguridad RLS
ALTER TABLE tetris.ratings ENABLE ROW LEVEL SECURITY;
ALTER TABLE tetris.match_tetris ENABLE ROW LEVEL SECURITY;
ALTER TABLE tetris.match_tetris_players ENABLE ROW LEVEL SECURITY;
ALTER TABLE tetris.reportes_resultado ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.amigos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Lectura ratings" ON tetris.ratings;
CREATE POLICY "Lectura ratings" ON tetris.ratings FOR SELECT USING (true);

DROP POLICY IF EXISTS "Lectura partidas" ON tetris.match_tetris;
CREATE POLICY "Lectura partidas" ON tetris.match_tetris FOR ALL USING (true);

DROP POLICY IF EXISTS "Lectura jugadores" ON tetris.match_tetris_players;
CREATE POLICY "Lectura jugadores" ON tetris.match_tetris_players FOR ALL USING (true);

DROP POLICY IF EXISTS "Gestion reportes" ON tetris.reportes_resultado;
CREATE POLICY "Gestion reportes" ON tetris.reportes_resultado FOR ALL USING (true);

DROP POLICY IF EXISTS "Gestion de amigos" ON public.amigos;
CREATE POLICY "Gestion de amigos" ON public.amigos FOR ALL USING (
    auth.uid() = solicitante_id OR auth.uid() = receptor_id
);

-- 6. Catálogo en Gameros (public.juegos)
ALTER TABLE public.juegos ADD COLUMN IF NOT EXISTS motor TEXT NOT NULL DEFAULT 'manual';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.juegos WHERE nombre ILIKE '%tetris%') THEN
        INSERT INTO public.juegos (nombre, motor) VALUES ('Tetris Now', 'app_externa');
    ELSE
        UPDATE public.juegos SET motor = 'app_externa' WHERE nombre ILIKE '%tetris%';
    END IF;
END $$;

-- 7. Funciones ELO y Reporte
CREATE OR REPLACE FUNCTION tetris.actualizar_rating_elo(
    p_winner_user_id UUID,
    p_loser_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'tetris', 'public'
AS $$
DECLARE
    v_r_winner INT;
    v_r_loser INT;
    v_k CONSTANT INT := 32;
    v_expected_winner NUMERIC;
    v_expected_loser NUMERIC;
BEGIN
    INSERT INTO tetris.ratings (user_id, rating) VALUES (p_winner_user_id, 1000) ON CONFLICT (user_id) DO NOTHING;
    INSERT INTO tetris.ratings (user_id, rating) VALUES (p_loser_user_id, 1000) ON CONFLICT (user_id) DO NOTHING;

    SELECT rating INTO v_r_winner FROM tetris.ratings WHERE user_id = p_winner_user_id;
    SELECT rating INTO v_r_loser FROM tetris.ratings WHERE user_id = p_loser_user_id;

    v_expected_winner := 1.0 / (1.0 + pow(10.0, (v_r_loser - v_r_winner)::NUMERIC / 400.0));
    v_expected_loser := 1.0 / (1.0 + pow(10.0, (v_r_winner - v_r_loser)::NUMERIC / 400.0));

    UPDATE tetris.ratings
    SET rating = ROUND(v_r_winner + v_k * (1.0 - v_expected_winner)), wins = wins + 1, matches_played = matches_played + 1, updated_at = now()
    WHERE user_id = p_winner_user_id;

    UPDATE tetris.ratings
    SET rating = GREATEST(100, ROUND(v_r_loser + v_k * (0.0 - v_expected_loser))), losses = losses + 1, matches_played = matches_played + 1, updated_at = now()
    WHERE user_id = p_loser_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.reportar_resultado_partida_externa(
    p_juego_nombre TEXT,
    p_match_id UUID,
    p_winner_team_id UUID,
    p_payload JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'tetris'
AS $$
DECLARE
    v_caller_id UUID := auth.uid();
    v_reports_count INT;
    v_distinct_winners INT;
    v_winner_user_id UUID;
    v_loser_user_id UUID;
BEGIN
    INSERT INTO tetris.reportes_resultado (match_id, reporter_user_id, winner_team_id)
    VALUES (p_match_id, v_caller_id, p_winner_team_id)
    ON CONFLICT (match_id, reporter_user_id) 
    DO UPDATE SET winner_team_id = p_winner_team_id, reported_at = now();

    SELECT COUNT(*), COUNT(DISTINCT winner_team_id)
    INTO v_reports_count, v_distinct_winners
    FROM tetris.reportes_resultado
    WHERE match_id = p_match_id;

    IF v_reports_count >= 2 THEN
        IF v_distinct_winners = 1 THEN
            UPDATE tetris.match_tetris
            SET status = 'finished', winner_team_id = p_winner_team_id, ended_at = now()
            WHERE id = p_match_id;

            SELECT user_id INTO v_winner_user_id FROM tetris.match_tetris_players WHERE match_id = p_match_id AND team_id = p_winner_team_id LIMIT 1;
            SELECT user_id INTO v_loser_user_id FROM tetris.match_tetris_players WHERE match_id = p_match_id AND team_id != p_winner_team_id LIMIT 1;

            IF v_winner_user_id IS NOT NULL AND v_loser_user_id IS NOT NULL THEN
                PERFORM tetris.actualizar_rating_elo(v_winner_user_id, v_loser_user_id);
            END IF;

            RETURN jsonb_build_object('success', true, 'status', 'finished', 'winner_team_id', p_winner_team_id);
        ELSE
            UPDATE tetris.match_tetris SET status = 'en_disputa' WHERE id = p_match_id;
            RETURN jsonb_build_object('success', false, 'status', 'en_disputa');
        END IF;
    END IF;

    RETURN jsonb_build_object('success', true, 'status', 'report_received', 'waiting_opponent', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.reportar_resultado_partida_externa(TEXT, UUID, UUID, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION tetris.actualizar_rating_elo(UUID, UUID) TO authenticated, service_role;
