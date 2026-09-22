# ESTADO REAL DEL PROYECTO — TETRIS NOW
**Última actualización:** 22 de septiembre de 2026  
**Auditoría y Referencia:** Gameros Core & Antigravity  
**Repositorio Oficial:** `https://github.com/adh3us/tetris-now.git` (rama `main`)  
**Proyecto Supabase:** `bgwvtfgwhpinfotzyucn` (São Paulo, sa-east-1)

---

## Criterio de Clasificación
Este documento categoriza el estado técnico de cada componente en tres categorías estrictas y mutuamente excluyentes, de acuerdo a la **Regla 4** del protocolo de verificación de Gameros Core:
1. **Aplicado y probado en producción:** Código activo, verificado en dispositivos reales con cuentas reales en fechas específicas.
2. **Construido, sin probar contra producción:** Código existente en archivos/funciones y/o scripts SQL aplicados en base de datos, pero sin validación en campo sobre hardware real.
3. **Solo documentado o planeado, sin código real:** Módulos o ideas presentes en propuestas documentales sin implementación funcional.
4. **Pregunta abierta:** Puntos que dependen de definiciones o confirmaciones formales de Lucas o del equipo Gameros Core.

---

## 1. Aplicado y probado en producción

### 1.1 Login Compartido con Gameros
* **Fecha de prueba:** 19 de septiembre de 2026.
* **Cuentas utilizadas:** Cuentas reales de **Víctor** y **Lucas** (autenticación mediante Google OAuth y Email en Supabase Auth).
* **Qué se verificó:**
  * Ambos jugadores pudieron iniciar sesión a través del paquete vendorizado en `packages/gameros_auth_ui/lib/src/login_screen.dart` y `auth_service.dart`.
  * La sesión de Supabase Auth se inicializa correctamente y permite el acceso al menú principal (`HomeShell`).
* **Archivos involucrados:**
  * `lib/core/supabase_config.dart`
  * `packages/gameros_auth_ui/lib/src/login_screen.dart`
  * `packages/gameros_auth_ui/lib/src/auth_service.dart`

---

## 2. Construido, sin probar contra producción

### 2.1 Matchmaking 1v1 Automático (`buscar_partida_automatica`)
* **Estado:** Construido, con antecedente de fallo en producción y corrección pendiente de prueba conjunta en campo.
* **Antecedente real:** En la prueba del **19 de septiembre de 2026**, Víctor ingresó al tablero de juego pero Lucas quedó esperando indefinidamente en la pantalla de búsqueda con radar.
* **Causas resueltas en código:**
  1. Disparidad en identificadores de equipo (UUID generado vs cadenas esperadas).
  2. Acumulación de registros obsoletos con `match_id` residual en `tetris.matchmaking_queue` que impedían el emparejamiento atómico.
* **Código y scripts:**
  * `lib/ui/quick_play_screen.dart` (flujo de búsqueda y polling).
  * `lib/services/tetris_match_service.dart` (`buscarPartidaAutomatica`, `consultarEstadoMatchmaking`).
  * `supabase/0007_fix_matchmaking_elo_logros.sql` (reemplaza `tetris.buscar_partida_automatica` con limpieza previa y matching atómico `FOR UPDATE SKIP LOCKED`).
* **Qué falta verificar en producción:** Ejecutar la búsqueda de partida rápida de forma simultánea en dos dispositivos físicos reales para confirmar que ambos se emparejan y cargan la misma sala sin colgarse.

### 2.2 Secuencia de Piezas Sincronizada (Semilla compartida)
* **Estado:** Construido en cliente y servicio, pendiente de validación visual simultánea.
* **Código:**
  * `lib/ui/quick_play_screen.dart` y `lib/ui/tetris_game_screen.dart`: inicialización del generador aleatorio utilizando una semilla (`seed`) compartida derivada del `match_id`.
* **Qué falta verificar en producción:** Confirmar en dos pantallas en paralelo que ambos jugadores reciben exactamente la misma secuencia de tetrominós (misma pieza inicial, misma pieza siguiente).

### 2.3 Sistema de Logros y ELO Dinámico
* **Estado:** Construido, con antecedente de fallo en producción y fix aplicado en base de datos.
* **Antecedente real:** En las partidas de prueba del 19 de septiembre, no se modificaban los puntos de ELO y todos los logros internos se mantenían bloqueados (debido a la inexistencia física de la tabla `tetris.logros_desbloqueados` en Supabase y fallas en los deltas).
* **Código y scripts:**
  * `supabase/0007_fix_matchmaking_elo_logros.sql` (crea `tetris.logros_desbloqueados` y `tetris.registrar_resultado_partida`). Corregido y ejecutado en el panel de Supabase.
  * `lib/services/logros_service.dart` (gestión de logros con persistencia reactiva en `SharedPreferences` y sincronización Supabase).
  * `lib/services/tetris_match_service.dart` (`calcularEloDeltaGanador`, `calcularEloDeltaPerdedor`: deltas de +60 a +100 y -50 a -90).
  * `test/elo_combat_test.dart` y `test/logros_test.dart` (tests unitarios locales pasando).
* **Qué falta verificar en producción:** Jugar una partida 1v1 completa hasta el game over para verificar que el perfil del ganador aumente de ELO, el del perdedor disminuya, y los logros se desbloqueen en pantalla.

### 2.4 Penalización de ELO por Abandono / Desconexión
* **Estado:** Construido a nivel RPC y cliente, sin prueba de desconexión real de red.
* **Comportamiento técnico:** Supabase no detecta desconexiones abruptas por corte de red de forma automática. La penalización (-90 puntos o 15% de rating) solo se activa si:
  1. El cliente ejecuta activamente "Rendirse/Abandonar".
  2. El rival detecta timeout de presencia en Realtime y reporta victoria.
* **Código:**
  * `supabase/0002_matchmaking_seguridad.sql` y `supabase/0006_sistema_elo_dinamico.sql` (`tetris.penalizar_abandono`).
  * `lib/services/tetris_match_service.dart` (`penalizarAbandono`).
  * `lib/ui/tetris_game_screen.dart` (`_terminateMatch`, líneas 791 y 1343).
* **Qué falta verificar en producción:** Provocar abandono voluntario o caída de conexión (modo avión) durante una partida 1v1 y constatar la deducción de puntos.

### 2.5 Reporte de Torneo (`public.reportar_resultado_cruce_torneo`)
* **Estado:** Cliente integrado; sin prueba de integración con torneo real en Gameros Core.
* **Código:**
  * `lib/services/tetris_match_service.dart` (`reportarResultadoCruceTorneo`, líneas 535–585).
  * `lib/ui/tetris_game_screen.dart` (invocación automática al finalizar si existe `widget.torneoPartidaId`).
* **Qué falta verificar en producción:** Crear un torneo real en Gameros Core, lanzar el juego mediante deep link de cruce, disputar la partida en Tetris Now y confirmar que el bracket de Gameros Core avance automáticamente.

### 2.6 Auto-registro de usuario desde Tetris hacia `public.usuarios`
* **Estado:** Construido en servicio, sin prueba con cuenta virgen.
* **Código:**
  * `lib/services/gameros_profile_service.dart` (`getFullProfile`, líneas 30–75): Si el usuario autenticado en `auth.users` no existe en `public.usuarios`, ejecuta un `upsert`/`insert` asignando un `codigo_jugador` nuevo (`#TTR...`).
* **Qué falta verificar en producción:** Iniciar sesión con un usuario nuevo que jamás haya ingresado a la web de Gameros para validar que las políticas RLS de `public.usuarios` no rechacen la inserción directa.

### 2.7 Indicadores de Estado de Conexión de Amigos
* **Estado:** Construido en interfaz y servicio de presencia.
* **Código:**
  * `lib/ui/amigos_tab.dart` y `lib/services/friends_service.dart`: renderizado de indicador de color (Verde = Conectado, Amarillo = Ausente, Rojo = Desconectado).
* **Qué falta verificar en producción:** Validar en la pestaña de amigos que el cambio de presencia en Supabase Realtime modifique dinámicamente el color del indicador.

### 2.8 Control de Versión y Reproducción de Música
* **Estado:** Construido en cliente.
* **Código:**
  * Versión visible en UI y centralizada: `lib/core/app_version.dart` (`v1.0.01`) y `pubspec.yaml`.
  * Motor de audio con soporte de BGM: `lib/services/audio_service.dart` (`playBgm`, `stopBgm`, `setBgmVolume` utilizando `audioplayers`).

---

## 3. Solo documentado o planeado, sin código real

### 3.1 Salas Privadas con Contraseña en Interfaz de Usuario
* **Estado:** Solo lógica SQL / Service; **cero interfaz gráfica**.
* **Evidencia:** Aunque existen `tetris.crear_sala_privada` (con hash `pgcrypto/bcrypt`) en `supabase/0002_matchmaking_seguridad.sql` y métodos en `lib/services/tetris_match_service.dart`, la pantalla `lib/ui/salas_tab.dart` es únicamente un placeholder que dice *"SALAS - Próximamente"*. No existe diálogo ni pantalla para escribir contraseña.

### 3.2 Sistema de Clanes y Tienda de Cosméticos
* **Estado:** Solo maquetas estáticas / documentado en propuestas.
* **Evidencia:** `lib/ui/tienda_tab.dart` muestra *"Próximamente"*, y `lib/ui/clan_challenges_screen.dart` contiene datos estáticos mock sin conexión a ninguna tabla de clanes de Gameros.

### 3.3 Mensajería Directa entre Amigos (`public.mensajes_amigos`)
* **Estado:** Inexistente. Fue documentada por error en informes históricos (`INFORME_SISTEMA_AMIGOS_Y_DESAFIOS_GAMEROS.md`), pero esa tabla nunca existió en Gameros Core. Todo el código mock asociado fue purgado en el commit `f26d541`.

---

## 4. Preguntas Abiertas

Las siguientes preguntas requieren definición o confirmación de Lucas o del equipo de Gameros Core:

1. **Avance automático de Bracket de Torneos:**
   * ¿El RPC `public.reportar_resultado_cruce_torneo` en el Supabase de producción ya cuenta con la lógica interna para actualizar el bracket y cerrar la ronda en Gameros Core, o todavía está pendiente de implementación por parte de Gameros Core (conforme lo señalado en la línea 93 de `contratotetrisnow.md`)?
2. **Alcance de Salas Privadas con Clave en el MVP:**
   * Dado que el flujo principal de juego es el emparejamiento 1v1 automático, ¿se requiere construir la UI de creación/ingreso de salas privadas con contraseña para este release, o se mantiene oficialmente como *"Próximamente"*?
3. **Gobierno y DDLs de Torneos:**
   * Confirmar si el archivo `supabase/0004_contrato_torneos_gameros.sql` (propuesta de tablas de torneos en esquema `public`) debe ser archivado definitivamente como propuesta histórica, entendiendo que el esquema `public` de torneos es gestionado con soberanía exclusiva por Gameros Core.
