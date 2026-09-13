-- ============================================================================
-- TETRIS NOW — Fase 2: Contrato de Integración Torneos Gameros ↔ Tetris Now
-- Fecha de contrato: 05/09/2026
-- ============================================================================
-- 1. Este archivo documenta y asegura el contrato publicado por el equipo core
--    de Gameros para que los resultados de cruces de torneo reportados por
--    Tetris Now hagan avanzar automáticamente el cuadro del torneo en Gameros.
-- 2. Si el equipo de Gameros ya publicó public.reportar_resultado_cruce_torneo,
--    este bloque no lo pisa gracias a CREATE OR REPLACE FUNCTION.
-- 3. Agrega las columnas auxiliares a tetris.match_tetris para persistir la
--    asociación directa con public.partidas e inscripciones_torneo.
-- ============================================================================

-- Columnas de enlace con el torneo en Gameros
ALTER TABLE tetris.match_tetris
  ADD COLUMN IF NOT EXISTS torneo_partida_id UUID,
  ADD COLUMN IF NOT EXISTS torneo_insc_1 UUID,
  ADD COLUMN IF NOT EXISTS torneo_insc_2 UUID;

CREATE INDEX IF NOT EXISTS idx_tetris_match_torneo_partida
  ON tetris.match_tetris(torneo_partida_id)
  WHERE torneo_partida_id IS NOT NULL;

-- Contrato oficial publicado por Gameros
CREATE OR REPLACE FUNCTION public.reportar_resultado_cruce_torneo(
    p_partida_id UUID,              -- id de public.partidas (el cruce del bracket de Gameros)
    p_ganador_inscripcion_id UUID,  -- id de inscripciones_torneo del lado ganador (NULL si empate)
    p_empate BOOLEAN DEFAULT FALSE,
    p_metadata JSONB DEFAULT '{}'::jsonb  -- libre: guardamos tetris_match_id, motivo, etc.
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
    v_partida public.partidas%ROWTYPE;
    v_juego_id UUID;
    v_motor TEXT;
    v_caller UUID := auth.uid();
    v_autorizado BOOLEAN;
BEGIN
    SELECT * INTO v_partida FROM public.partidas WHERE id = p_partida_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La partida % no existe', p_partida_id;
    END IF;

    IF v_partida.estado <> 'pendiente' THEN
        RAISE EXCEPTION 'La partida % ya no está pendiente (estado actual: %)', p_partida_id, v_partida.estado;
    END IF;

    SELECT t.juego_id INTO v_juego_id FROM public.torneos t WHERE t.id = v_partida.torneo_id;
    SELECT motor INTO v_motor FROM public.juegos WHERE id = v_juego_id;
    IF v_motor IS DISTINCT FROM 'app_externa' THEN
        RAISE EXCEPTION 'El juego de este torneo no está marcado como app_externa';
    END IF;

    -- El que llama tiene que ser uno de los dos jugadores/equipos de ese cruce
    SELECT EXISTS (
        SELECT 1 FROM public.inscripciones_torneo it
        WHERE it.id IN (v_partida.inscripcion_a_id, v_partida.inscripcion_b_id)
          AND (it.usuario_id = v_caller
               OR EXISTS (
                    SELECT 1 FROM public.miembros_clan mc
                    WHERE mc.clan_id = it.clan_id AND mc.usuario_id = v_caller AND mc.estado = 'activo'
               ))
    ) INTO v_autorizado;

    IF NOT v_autorizado THEN
        RAISE EXCEPTION 'Solo un participante de este cruce puede reportar el resultado';
    END IF;

    IF NOT p_empate AND p_ganador_inscripcion_id NOT IN (v_partida.inscripcion_a_id, v_partida.inscripcion_b_id) THEN
        RAISE EXCEPTION 'El ganador tiene que ser uno de los dos inscriptos de este cruce';
    END IF;

    UPDATE public.partidas
    SET resultado_a = CASE WHEN p_empate THEN 'empate' WHEN p_ganador_inscripcion_id = inscripcion_a_id THEN 'ganador' ELSE 'perdedor' END,
        resultado_b = CASE WHEN p_empate THEN 'empate' WHEN p_ganador_inscripcion_id = inscripcion_b_id THEN 'ganador' ELSE 'perdedor' END,
        ganador_inscripcion_id = CASE WHEN p_empate THEN NULL ELSE p_ganador_inscripcion_id END,
        empate = p_empate,
        estado = 'jugada'
    WHERE id = p_partida_id;

    RETURN jsonb_build_object('success', true, 'partida_id', p_partida_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.reportar_resultado_cruce_torneo(UUID, UUID, BOOLEAN, JSONB) TO authenticated;
