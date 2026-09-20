-- =========================================================================
-- TETRIS NOW: MIGRACIÓN CONSOLIDADA 0007
-- Corrección de Matchmaking 1v1, Limpieza de Cola, Tablas de Logros y ELO
-- =========================================================================

CREATE SCHEMA IF NOT EXISTS tetris;
GRANT USAGE ON SCHEMA tetris TO anon, authenticated, service_role;

-- 1. Tabla de Catálogo Maestro de Logros
CREATE TABLE IF NOT EXISTS tetris.logros (
    id TEXT PRIMARY KEY,
    titulo TEXT NOT NULL,
    descripcion TEXT NOT NULL,
    icono TEXT NOT NULL DEFAULT 'trophy',
    categoria TEXT NOT NULL DEFAULT 'combate',
    puntos INT NOT NULL DEFAULT 10,
    orden INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. Progreso de Logros de Usuario
CREATE TABLE IF NOT EXISTS tetris.logros_desbloqueados (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    logro_id TEXT NOT NULL REFERENCES tetris.logros(id) ON DELETE CASCADE,
    progreso_actual INT NOT NULL DEFAULT 1,
    progreso_objetivo INT NOT NULL DEFAULT 1,
    completado BOOLEAN NOT NULL DEFAULT true,
    desbloqueado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_user_logro UNIQUE (user_id, logro_id)
);

ALTER TABLE tetris.logros ENABLE ROW LEVEL SECURITY;
ALTER TABLE tetris.logros_desbloqueados ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "RLS_logros_select" ON tetris.logros;
CREATE POLICY "RLS_logros_select" ON tetris.logros FOR SELECT TO authenticated, anon USING (true);

DROP POLICY IF EXISTS "RLS_logros_desbloqueados_select" ON tetris.logros_desbloqueados;
CREATE POLICY "RLS_logros_desbloqueados_select" ON tetris.logros_desbloqueados FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "RLS_logros_desbloqueados_insert" ON tetris.logros_desbloqueados;
CREATE POLICY "RLS_logros_desbloqueados_insert" ON tetris.logros_desbloqueados FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "RLS_logros_desbloqueados_update" ON tetris.logros_desbloqueados;
CREATE POLICY "RLS_logros_desbloqueados_update" ON tetris.logros_desbloqueados FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- Semillas de Logros
INSERT INTO tetris.logros (id, titulo, descripcion, icono, categoria, puntos, orden) VALUES
('primer_tetris', '¡Tetris Limpio!', 'Limpia 4 líneas simultáneas con una sola pieza I.', 'flash_on', 'habilidad', 10, 1),
('combo_x3', 'Cadena de Reacción', 'Alcanza una racha de combo de x3 o superior.', 'bolt', 'habilidad', 15, 2),
('combo_x5', 'Tormenta de Bloques', 'Alcanza una racha de combo de x5 o superior en partida activa.', 'whatshot', 'habilidad', 25, 3),
('cubo_dorado', 'Toque de Midas', 'Construye un Cubo Dorado (Monocube 4x4) de una sola pieza.', 'star', 'alquimia', 20, 4),
('cubo_plata', 'Alquimia Metálica', 'Construye un Cubo Plateado (Multicube 4x4) combinando piezas.', 'shield', 'alquimia', 20, 5),
('primer_duelo', 'Bautismo de Fuego', 'Completa tu primera partida en el radar 1v1 rápido.', 'sports_esports', 'combate', 10, 6),
('primera_victoria', 'Primera Sangre', 'Gana tu primer duelo 1v1 contra un rival en tiempo real.', 'emoji_events', 'combate', 20, 7),
('racha_3_victorias', 'Imparable', 'Gana 3 partidas 1v1 de forma consecutiva.', 'military_tech', 'combate', 30, 8),
('pared_de_hierro', 'Superviviente Crítico', 'Recupérate y gana una partida tras haber tenido menos de 20 HP.', 'health_and_safety', 'combate', 25, 9),
('maestro_srs', 'Giro Fantasma', 'Ejecuta una rotación SRS avanzada para encajar una pieza bloqueada.', 'autorenew', 'habilidad', 15, 10)
ON CONFLICT (id) DO UPDATE SET
    titulo = EXCLUDED.titulo,
    descripcion = EXCLUDED.descripcion,
    icono = EXCLUDED.icono,
    categoria = EXCLUDED.categoria,
    puntos = EXCLUDED.puntos,
    orden = EXCLUDED.orden;

-- 3. Cola de Matchmaking con Limpieza Automática de Partidas Finalizadas
DROP FUNCTION IF EXISTS tetris.buscar_partida_automatica(text);
DROP FUNCTION IF EXISTS tetris.cancelar_busqueda();

CREATE OR REPLACE FUNCTION tetris.buscar_partida_automatica(p_gamer_tag text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = tetris, public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_rival tetris.matchmaking_queue;
  v_match tetris.match_tetris;
  v_team_1 uuid;
  v_team_2 uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;

  -- 1. Si el usuario ya tenía una partida asignada previamente, verificar si sigue activa
  SELECT * INTO v_rival FROM tetris.matchmaking_queue WHERE user_id = v_user_id;
  IF FOUND AND v_rival.match_id IS NOT NULL THEN
    SELECT * INTO v_match FROM tetris.match_tetris WHERE id = v_rival.match_id;
    IF FOUND AND v_match.status = 'in_progress' THEN
      RETURN jsonb_build_object(
        'status', 'matched',
        'match_id', v_match.id,
        'team_id', v_rival.team_id,
        'opponent_team_id', CASE WHEN v_rival.team_id = v_match.team_1_id THEN v_match.team_2_id ELSE v_match.team_1_id END
      );
    ELSE
      -- Partida vieja o finalizada: purgar entrada de la cola para permitir nueva búsqueda
      DELETE FROM tetris.matchmaking_queue WHERE user_id = v_user_id;
    END IF;
  END IF;

  -- 2. Purgar cualquier rival estancado con partida finalizada
  DELETE FROM tetris.matchmaking_queue
  WHERE match_id IS NOT NULL
    AND match_id IN (SELECT id FROM tetris.match_tetris WHERE status IN ('finished', 'cancelled', 'en_disputa'));

  -- 3. Buscar rival esperando en cola (atómico skip locked)
  SELECT * INTO v_rival
  FROM tetris.matchmaking_queue
  WHERE user_id <> v_user_id AND match_id IS NULL
  ORDER BY created_at ASC
  FOR UPDATE SKIP LOCKED
  LIMIT 1;

  IF FOUND THEN
    v_team_1 := v_rival.team_id;
    v_team_2 := gen_random_uuid();

    INSERT INTO tetris.match_tetris (format, team_1_id, team_2_id, status, started_at)
    VALUES ('1v1', v_team_1, v_team_2, 'in_progress', now())
    RETURNING * INTO v_match;

    INSERT INTO tetris.match_tetris_players (match_id, team_id, user_id, gamer_tag)
    VALUES (v_match.id, v_team_1, v_rival.user_id, v_rival.gamer_tag);

    INSERT INTO tetris.match_tetris_players (match_id, team_id, user_id, gamer_tag)
    VALUES (v_match.id, v_team_2, v_user_id, p_gamer_tag);

    UPDATE tetris.matchmaking_queue
      SET match_id = v_match.id
      WHERE user_id = v_rival.user_id;

    DELETE FROM tetris.matchmaking_queue WHERE user_id = v_user_id;

    RETURN jsonb_build_object(
      'status', 'matched',
      'match_id', v_match.id,
      'team_id', v_team_2,
      'opponent_team_id', v_team_1
    );
  END IF;

  -- 4. Nadie esperando: entrar a la cola
  INSERT INTO tetris.matchmaking_queue (user_id, gamer_tag, team_id, match_id)
  VALUES (v_user_id, p_gamer_tag, gen_random_uuid(), NULL)
  ON CONFLICT (user_id) DO UPDATE SET
    gamer_tag = EXCLUDED.gamer_tag,
    match_id = NULL,
    created_at = now();

  RETURN jsonb_build_object(
    'status', 'waiting',
    'match_id', NULL,
    'team_id', (SELECT team_id FROM tetris.matchmaking_queue WHERE user_id = v_user_id)
  );
END;
$$;

-- 4. Cancelación limpia de cola
CREATE OR REPLACE FUNCTION tetris.cancelar_busqueda()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = tetris, public
AS $$
  DELETE FROM tetris.matchmaking_queue WHERE user_id = auth.uid();
$$;

GRANT EXECUTE ON FUNCTION tetris.buscar_partida_automatica(text) TO authenticated;
GRANT EXECUTE ON FUNCTION tetris.cancelar_busqueda() TO authenticated;
