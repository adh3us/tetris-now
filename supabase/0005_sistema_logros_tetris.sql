-- =========================================================================
-- ESQUEMA TETRIS: SISTEMA DE LOGROS INTERNO Y PROGRESO DE USUARIOS
-- Proyecto Supabase ID: bgwvtfgwhpinfotzyucn
-- =========================================================================

-- 1. Asegurar esquema tetris y permisos base
CREATE SCHEMA IF NOT EXISTS tetris;
GRANT USAGE ON SCHEMA tetris TO anon, authenticated, service_role;

-- 2. Catálogo Maestro de Logros (Solo lectura para usuarios, administración restringida)
CREATE TABLE IF NOT EXISTS tetris.logros (
    id TEXT PRIMARY KEY,                       -- Clave nemotécnica única (ej: 'primer_tetris', 'cubo_dorado')
    titulo TEXT NOT NULL,                      -- Título visible del logro (ej: '¡Tetris Clásico!')
    descripcion TEXT NOT NULL,                 -- Detalle de cómo desbloquearlo
    icono TEXT NOT NULL DEFAULT 'trophy',       -- Identificador de icono / badge en Flutter
    categoria TEXT NOT NULL DEFAULT 'combate', -- 'combate', 'habilidad', 'alquimia', 'progresion'
    puntos INT NOT NULL DEFAULT 10,            -- Puntos o experiencia de logro
    orden INT NOT NULL DEFAULT 0,              -- Orden de presentación en la UI
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. Progreso y Logros Desbloqueados por Usuario
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

-- Índices de alto rendimiento
CREATE INDEX IF NOT EXISTS idx_logros_desbloqueados_user ON tetris.logros_desbloqueados(user_id);
CREATE INDEX IF NOT EXISTS idx_logros_desbloqueados_logro ON tetris.logros_desbloqueados(logro_id);

-- 4. Habilitar Seguridad por Filas (Row Level Security - RLS)
ALTER TABLE tetris.logros ENABLE ROW LEVEL SECURITY;
ALTER TABLE tetris.logros_desbloqueados ENABLE ROW LEVEL SECURITY;

-- =========================================================================
-- POLÍTICAS RLS: tetris.logros (Catálogo)
-- Separación estricta: Lectura pública/autenticada, Escritura exclusiva service_role
-- =========================================================================

-- LECTURA: Todos los usuarios autenticados y anónimos pueden ver el catálogo de logros
CREATE POLICY "RLS_logros_select"
    ON tetris.logros
    FOR SELECT
    TO authenticated, anon
    USING (true);

-- ESCRITURA: Ningún usuario común puede insertar, actualizar o borrar logros del catálogo
CREATE POLICY "RLS_logros_insert_admin"
    ON tetris.logros
    FOR INSERT
    TO service_role
    WITH CHECK (true);

CREATE POLICY "RLS_logros_update_admin"
    ON tetris.logros
    FOR UPDATE
    TO service_role
    USING (true)
    WITH CHECK (true);

CREATE POLICY "RLS_logros_delete_admin"
    ON tetris.logros
    FOR DELETE
    TO service_role
    USING (true);

-- =========================================================================
-- POLÍTICAS RLS: tetris.logros_desbloqueados (Progreso de Usuario)
-- Separación estricta por operación: cada usuario solo accede a sus propios datos
-- PROHIBIDO: USING (true) indiscriminado
-- =========================================================================

-- LECTURA: Un usuario autenticado solo puede leer sus propios logros
CREATE POLICY "RLS_logros_desbloqueados_select"
    ON tetris.logros_desbloqueados
    FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

-- LECTURA ADMINISTRATIVA: service_role puede auditar todos los registros
CREATE POLICY "RLS_logros_desbloqueados_select_service"
    ON tetris.logros_desbloqueados
    FOR SELECT
    TO service_role
    USING (true);

-- INSERCIÓN: Un usuario autenticado solo puede registrar logros para su propio UUID
CREATE POLICY "RLS_logros_desbloqueados_insert"
    ON tetris.logros_desbloqueados
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

-- ACTUALIZACIÓN: Un usuario solo puede modificar su propio progreso
CREATE POLICY "RLS_logros_desbloqueados_update"
    ON tetris.logros_desbloqueados
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- ELIMINACIÓN: Un usuario solo puede eliminar registros de sus propios logros
CREATE POLICY "RLS_logros_desbloqueados_delete"
    ON tetris.logros_desbloqueados
    FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);

-- =========================================================================
-- 5. SEMILLAS INICIALES DEL CATÁLOGO DE LOGROS (tetris.logros)
-- =========================================================================
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
