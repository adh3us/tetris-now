-- =========================================================================
-- FASE 0 (cierre) — Matchmaking automático, seguridad de salas y ELO
-- Sigue a fase0_init.sql. Proyecto Supabase ID: bgwvtfgwhpinfotzyucn
-- =========================================================================

-- 1. pgcrypto (Gameros ya la usa para contraseñas de torneo; idempotente)
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- 2. Columnas de sala que el cliente ya usa y no existían en fase0_init
--    (room_name, allow_spectators) + reemplazo de contraseña en texto
--    plano por hash. El cliente hoy inserta `password` en texto plano
--    directo a la tabla (tetris_match_service.dart) — se corrige acá y
--    en el cliente en el mismo commit.
ALTER TABLE tetris.match_tetris
  ADD COLUMN IF NOT EXISTS room_name TEXT DEFAULT 'Duelo 1c1',
  ADD COLUMN IF NOT EXISTS is_private BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS password_hash TEXT,
  ADD COLUMN IF NOT EXISTS allow_spectators BOOLEAN NOT NULL DEFAULT true;

-- Si existiera una columna `password` en texto plano de una corrida
-- previa del cliente viejo, se elimina — nunca debe persistir en claro.
ALTER TABLE tetris.match_tetris DROP COLUMN IF EXISTS password;

-- 3. Contraseña de sala con hash (bcrypt vía pgcrypto)
CREATE OR REPLACE FUNCTION tetris.crear_sala_privada(
  p_match_id UUID,
  p_password TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'tetris', 'extensions'
AS $$
BEGIN
  UPDATE tetris.match_tetris
  SET is_private = true,
      password_hash = extensions.crypt(p_password, extensions.gen_salt('bf'))
  WHERE id = p_match_id;
END;
$$;

CREATE OR REPLACE FUNCTION tetris.verificar_password_sala(
  p_match_id UUID,
  p_password TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'tetris', 'extensions'
AS $$
DECLARE
  v_hash TEXT;
  v_es_privada BOOLEAN;
BEGIN
  SELECT password_hash, is_private INTO v_hash, v_es_privada
  FROM tetris.match_tetris WHERE id = p_match_id;

  IF NOT v_es_privada THEN
    RETURN true;
  END IF;

  IF v_hash IS NULL THEN
    RETURN false;
  END IF;

  RETURN v_hash = extensions.crypt(p_password, v_hash);
END;
$$;

GRANT EXECUTE ON FUNCTION tetris.crear_sala_privada(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION tetris.verificar_password_sala(UUID, TEXT) TO authenticated;

-- 4. RLS restrictivo (fase0_init dejó "FOR ALL USING (true)" en estas 3)
DROP POLICY IF EXISTS "Lectura partidas" ON tetris.match_tetris;
CREATE POLICY "match_tetris_select" ON tetris.match_tetris FOR SELECT USING (true);
CREATE POLICY "match_tetris_insert" ON tetris.match_tetris
  FOR INSERT WITH CHECK (status = 'pending' AND winner_team_id IS NULL);
-- El propio jugador (creador o quien arranca la partida) puede pasarla
-- a in_progress/finished/en_disputa; la resolución de ELO sigue yendo
-- únicamente por reportar_resultado_partida_externa (SECURITY DEFINER).
CREATE POLICY "match_tetris_update" ON tetris.match_tetris
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM tetris.match_tetris_players mtp
      WHERE mtp.match_id = tetris.match_tetris.id AND mtp.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Lectura jugadores" ON tetris.match_tetris_players;
CREATE POLICY "match_tetris_players_select" ON tetris.match_tetris_players FOR SELECT USING (true);
CREATE POLICY "match_tetris_players_insert" ON tetris.match_tetris_players
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "match_tetris_players_update" ON tetris.match_tetris_players
  FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Gestion reportes" ON tetris.reportes_resultado;
CREATE POLICY "reportes_resultado_select" ON tetris.reportes_resultado FOR SELECT USING (true);
CREATE POLICY "reportes_resultado_insert" ON tetris.reportes_resultado
  FOR INSERT WITH CHECK (auth.uid() = reporter_user_id);

-- 5. Nadie autenticado puede auto-asignarse ELO llamando esta función
--    directo; solo debe correr como parte de reportar_resultado_partida_externa
--    (SECURITY DEFINER, no necesita EXECUTE propio sobre la función que invoca).
REVOKE EXECUTE ON FUNCTION tetris.actualizar_rating_elo(UUID, UUID) FROM authenticated;

-- 6. Cola de matchmaking automático (no existía: hoy todo es manual vía
--    Crear Duelo / Encontrar Salas). Botón único "Jugar" en el cliente
--    llama a tetris.buscar_partida_automatica.
CREATE TABLE IF NOT EXISTS tetris.matchmaking_queue (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  gamer_tag TEXT NOT NULL,
  rating INT NOT NULL DEFAULT 1000,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE tetris.matchmaking_queue ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "matchmaking_queue_select" ON tetris.matchmaking_queue;
CREATE POLICY "matchmaking_queue_select" ON tetris.matchmaking_queue FOR SELECT USING (true);
-- No hay policy de INSERT/UPDATE/DELETE directa: solo se entra/sale de
-- la cola vía las funciones SECURITY DEFINER de abajo.

-- Entra a la cola y, si ya hay alguien esperando, arma la partida ahí
-- mismo (primero en cola = primero emparejado; sin filtro de ELO en
-- esta primera versión). Devuelve el match_id si emparejó, o NULL si
-- quedó esperando.
CREATE OR REPLACE FUNCTION tetris.buscar_partida_automatica(
  p_gamer_tag TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'tetris'
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_rating INT;
  v_oponente UUID;
  v_oponente_tag TEXT;
  v_match_id UUID;
  v_team_propio UUID := gen_random_uuid();
  v_team_rival UUID := gen_random_uuid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Debe estar autenticado para buscar partida';
  END IF;

  SELECT rating INTO v_rating FROM tetris.ratings WHERE user_id = v_user_id;
  v_rating := COALESCE(v_rating, 1000);

  -- Busca al rival más antiguo en cola (excluyéndose a sí mismo) y lo
  -- saca de la cola de forma atómica (evita que dos búsquedas en
  -- paralelo emparejen al mismo rival dos veces).
  SELECT user_id, gamer_tag INTO v_oponente, v_oponente_tag
  FROM tetris.matchmaking_queue
  WHERE user_id != v_user_id
  ORDER BY joined_at ASC
  LIMIT 1
  FOR UPDATE SKIP LOCKED;

  IF v_oponente IS NOT NULL THEN
    DELETE FROM tetris.matchmaking_queue WHERE user_id = v_oponente;
    DELETE FROM tetris.matchmaking_queue WHERE user_id = v_user_id;

    INSERT INTO tetris.match_tetris (format, status, team_1_id, team_2_id, room_name)
    VALUES ('1v1', 'pending', v_team_propio, v_team_rival, 'Duelo automático')
    RETURNING id INTO v_match_id;

    INSERT INTO tetris.match_tetris_players (match_id, team_id, user_id, gamer_tag)
    VALUES
      (v_match_id, v_team_propio, v_user_id, p_gamer_tag),
      (v_match_id, v_team_rival, v_oponente, v_oponente_tag);

    RETURN v_match_id;
  END IF;

  -- Nadie esperando: se anota en la cola y devuelve NULL (el cliente
  -- sigue esperando y consulta tetris.mi_estado_matchmaking()).
  INSERT INTO tetris.matchmaking_queue (user_id, gamer_tag, rating)
  VALUES (v_user_id, p_gamer_tag, v_rating)
  ON CONFLICT (user_id) DO UPDATE SET gamer_tag = p_gamer_tag, joined_at = now();

  RETURN NULL;
END;
$$;

-- El cliente hace polling (o Realtime sobre match_tetris_players) con
-- esto mientras espera en cola, para saber si otro jugador ya lo
-- emparejó a él (porque el otro llamó a buscar_partida_automatica y
-- lo encontró primero).
CREATE OR REPLACE FUNCTION tetris.mi_estado_matchmaking()
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
SET search_path = 'tetris'
AS $$
  SELECT mtp.match_id
  FROM tetris.match_tetris_players mtp
  JOIN tetris.match_tetris mt ON mt.id = mtp.match_id
  WHERE mtp.user_id = auth.uid()
    AND mt.status = 'pending'
    AND mt.created_at > now() - interval '5 minutes'
  ORDER BY mt.created_at DESC
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION tetris.cancelar_busqueda()
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = 'tetris'
AS $$
  DELETE FROM tetris.matchmaking_queue WHERE user_id = auth.uid();
$$;

GRANT EXECUTE ON FUNCTION tetris.buscar_partida_automatica(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION tetris.mi_estado_matchmaking() TO authenticated;
GRANT EXECUTE ON FUNCTION tetris.cancelar_busqueda() TO authenticated;

-- 7. Penalización de ELO por abandono/desconexión: 15% del ELO ACTUAL
--    del jugador en el momento del abandono, sin piso en 0 (puede
--    quedar negativo). Detección: timeout de reconexión del cliente
--    (30s, ver tetris_realtime_service.dart) + reporte del cliente.
--    Solo puede penalizar a un jugador que efectivamente pertenece a
--    esa partida, para que no se pueda penalizar ELO ajeno arbitrariamente.
CREATE OR REPLACE FUNCTION tetris.penalizar_abandono(
  p_match_id UUID,
  p_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'tetris'
AS $$
DECLARE
  v_rating_actual INTEGER;
  v_descuento INTEGER;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM tetris.match_tetris_players mtp
    WHERE mtp.match_id = p_match_id AND mtp.user_id = p_user_id
  ) THEN
    RAISE EXCEPTION 'El usuario no pertenece a esta partida';
  END IF;

  INSERT INTO tetris.ratings (user_id, rating) VALUES (p_user_id, 1000)
  ON CONFLICT (user_id) DO NOTHING;

  SELECT rating INTO v_rating_actual FROM tetris.ratings WHERE user_id = p_user_id;
  v_descuento := ROUND(v_rating_actual * 0.15);

  UPDATE tetris.ratings
  SET rating = v_rating_actual - v_descuento,
      losses = losses + 1,
      matches_played = matches_played + 1,
      updated_at = now()
  WHERE user_id = p_user_id;
END;
$$;

-- La llama el cliente del jugador que SIGUE conectado, al vencerse el
-- timeout de reconexión del rival (ver tetris_realtime_service.dart /
-- tetris_game_screen.dart). Queda para authenticated porque quien
-- reporta no es el propio penalizado; la validación de pertenencia a
-- la partida de arriba evita el abuso hacia jugadores ajenos.
GRANT EXECUTE ON FUNCTION tetris.penalizar_abandono(UUID, UUID) TO authenticated;
