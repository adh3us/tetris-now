# Contrato de integración Torneos Gameros ↔ Tetris Now

**Para:** equipo de Tetris Now (Víctor)
**De:** equipo core de Gameros
**Fecha:** 05/09/2026
**Motivo:** hoy Tetris Now tiene su propia función `public.reportar_resultado_partida_externa`, pero
solo actualiza sus tablas internas (`tetris.match_tetris`, ranking ELO propio). Nunca escribe en
`public.partidas` de Gameros — así que si hoy se arma un torneo de Tetris dentro de Gameros, el
resultado que carga Tetris Now **no hace avanzar el cuadro del torneo**. Este documento define la
pieza que falta para que sí lo haga, sin tocar nada de lo que ya tienen funcionando.

## 1. No toquen su función actual

`public.reportar_resultado_partida_externa(p_juego_nombre, p_match_id, p_winner_team_id, p_payload)`
sigue existiendo tal cual está, para partidas sueltas 1v1 con ranking propio (fuera de torneo). No
hace falta tocarla ni renombrarla.

## 2. Función nueva que van a llamar ustedes (la crea y publica el equipo de Gameros)

```sql
CREATE OR REPLACE FUNCTION public.reportar_resultado_cruce_torneo(
    p_partida_id UUID,              -- id de public.partidas (el cruce del bracket de Gameros)
    p_ganador_inscripcion_id UUID,  -- id de inscripciones_torneo del lado ganador (NULL si empate)
    p_empate BOOLEAN DEFAULT FALSE,
    p_metadata JSONB DEFAULT '{}'::jsonb  -- libre: guarden ahí lo que les sirva (ej. su match_id interno)
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

    -- A partir de acá el resto del motor de Gameros (avanzar bracket, actualizar
    -- posiciones, anunciar en Discord si corresponde) sigue exactamente el mismo
    -- camino que cuando un árbitro humano carga un resultado a mano — no hace
    -- falta nada más de este lado.

    RETURN jsonb_build_object('success', true, 'partida_id', p_partida_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.reportar_resultado_cruce_torneo(UUID, UUID, BOOLEAN, JSONB) TO authenticated;
```

*(Nota interna para el equipo de Gameros: falta enganchar acá el mismo bloque de avance de bracket
que usan `cargar_resultado`/`cargar_resultado_suizo`/etc. — se termina de escribir del lado de Gameros,
no es trabajo de Tetris.)*

## 3. Cómo la llaman desde Tetris Now

Cuando una partida de `tetris.match_tetris` tiene `tournament_id` distinto de null y el motor del
juego (su propio código, sin intervención del jugador) determina quién ganó — llamen **una sola vez**,
automático, sin pedirle confirmación a nadie:

```dart
await supabase.rpc('reportar_resultado_cruce_torneo', params: {
  'p_partida_id': idDelCruceEnGameros, // el que vino cuando se armó la partida
  'p_ganador_inscripcion_id': idInscripcionGanadora,
  'p_empate': false,
  'p_metadata': {'tetris_match_id': match.id},
});
```

## 4. Punto importante — decisión explícita de Lucas

El diseño original pedía doble confirmación de los dos jugadores antes de dar un resultado por
válido (para evitar que un jugador trucho invente un resultado). **Para este puente específico,
Lucas decidió no pedirles ese mecanismo**: como el resultado sale del propio motor de juego (no de
que un jugador "declare" que ganó), se reporta automático con un solo llamado. Sigan usando su
sistema de doble confirmación (`tetris.reportes_resultado`) para todo lo demás — partidas sueltas,
fuera de torneo — eso no cambia.

## 5. Qué necesitamos de ustedes para coordinar

- Confirmarnos si `fase0_init.sql` ya se corrió en el Supabase compartido (`bgwvtfgwhpinfotzyucn`) o
  todavía está solo en el repo.
- Avisarnos cuándo tengan lista la llamada del punto 3, para probar un torneo de prueba de punta a
  punta entre los dos lados.
