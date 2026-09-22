# Especificación Funcional y Técnica Oficial — Tetris Now (Módulo Satélite Gameros)

**Documento de Traspaso y Sincronización Arquitectónica**  
**De:** Spark (Gemini) — Lead de Motor, Gráfica y Lógica de Tetris Now  
**Para:** Claude (Agente Core del Ecosistema Gameros) / Equipo de Desarrollo Gameros  
**Fecha de corte:** Septiembre 2026  
**Repositorio Oficial:** `adh3us/tetris-now` (rama `main`)  
**Ecosistema Central:** Plataforma Gameros (`adh3us/gameros`)  
**Backend Central (Supabase):** Proyecto `bgwvtfgwhpinfotzyucn` (AWS sa-east-1, São Paulo)  
**ID de Aplicación Android:** `com.gameros.tetris` (Compilado para Android SDK 36, Java 25, Flutter 3.47.2)

---

## 1. Visión General y Principio de Gobernanza

**Tetris Now** es un cliente competitivo de eSports en tiempo real diseñado para funcionar como un **módulo satélite subordinado** a la plataforma Gameros Core.

### Principio Arquitectónico:
1. **Gameros Core es la plataforma soberana:**
   * Centraliza la autenticación única (`auth.users`), perfiles oficiales (`public.usuarios`), clanes/equipos (`public.equipos`), amistades (`public.amigos`), torneos globales (`public.torneos`) y la futura billetera/ledger de créditos.
2. **Tetris Now como ejecutor de juego:**
   * No duplica tablas maestras de usuarios ni impone esquemas ajenos.
   * Utiliza el esquema aislado `tetris.*` para métricas propias del juego (ratings ELO, historial de partidas, estado de duelos y colas).
   * Consume la sesión activa mediante Supabase OAuth (Google Sign-In con `konig.arg@gmail.com` y correo/contraseña).
   * Reporta resultados de partidas y cruces de torneos a Gameros Core mediante contratos RPC preestablecidos.

---

## 2. Invariantes Arquitectónicas y Reglas de Oro (MODIFICACIONES PROHIBIDAS)

Para garantizar la estabilidad del cliente y evitar regresiones en producción y compilaciones en Windows 11 / Android, el desarrollo debe respetar estrictamente estas 7 reglas:

1. ❌ **Menú Principal de 2 Botones:**
   El menú en `lib/main.dart` contiene exclusivamente 2 accesos:
   * **Botón 1 (Principal destacado):** `BUSCAR PARTIDA 1v1 RÁPIDA` (entra directo al radar de emparejamiento automático `CreateDuelScreen`).
   * **Botón 2 (Secundario):** `MODO SOLITARIO (PRÁCTICA)` (partida individual 10x20 con Hi-Score).
   * Los accesos secundarios (Salas manuales, Clanes, Amigos, Torneos) se integran como subrutas o accesos contextuales, nunca sobrecargando la pantalla de inicio.
2. ❌ **Emparejamiento 1v1 Automático:**
   Prohibido reintroducir salas manuales con clave como flujo primario. El emparejamiento es directo por cola en Supabase con auto-lanzamiento hacia la partida al detectar al rival.
3. ❌ **Audio Puro (Cero Vibración Nativa):**
   El juego opera con SFX puros de baja latencia mediante `audioplayers`.
   * Prohibido incluir `<uses-permission android:name="android.permission.VIBRATE"/>` en `AndroidManifest.xml`.
   * Prohibido incluir `vibration: ^2.0.1` en `pubspec.yaml` (rompe la compatibilidad con SDK 36 / Java 25).
4. ❌ **Persistencia Metálica Absoluta de Cubos Especiales:**
   Los bloques 4x4 convertidos en **Cubo Dorado (Monocube)** o **Cubo Plateado (Multicube)** conservan su textura metálica pulida lisa de forma permanente, incluso si se rompen parcialmente en líneas individuales o escalonadas. Jamás vuelven al color de las piezas originales.
5. ❌ **Botonera 3x2 Símil Arcade Protegida:**
   La botonera inferior táctil (`lib/ui/virtual_controller.dart`) está estructurada en una matriz de 3 arriba y 3 abajo, con botones de 40 px y protegida con `FittedBox` contra desbordes:
   * Fila superior: `HOLD` (Púrpura), `ESCUDO` (Verde), `ATAQUE` (Celeste/Cian).
   * Fila inferior: `⟲ ROTAR` (Rojo), `↻ ROTAR` (Azul), `DROP` (Rosa).
   * Botón central: `MAPA` (cicla inmediatamente entre los 4 escenarios temáticos).
6. ❌ **Hard Drop Exclusivo en Botón Físico:**
   Mover el analógico hacia arriba NO debe tirar la ficha de golpe. La caída instantánea es exclusiva del botón físico `DROP` (o doble tap configurado).
7. ❌ **Cumplimiento Estricto de Sintaxis Dart 3 y Tipado Supabase:**
   * Todos los `import` deben ubicarse estrictamente al inicio de cada archivo.
   * Cláusula `default:` al final en sentencias `switch`.
   * Parámetros de navegación sin modificador `const` en pantallas dinámicas.
   * Columnas de equipos (`team_1_id`, `team_2_id`) de tipo estricto `UUID` en Supabase; no enviar cadenas literales.

---

## 3. Especificaciones del Motor de Juego y Físicas (`tetris_engine.dart`)

El motor opera de forma determinista a 60 FPS con las reglas oficiales Guideline:

* **Super Rotation System (SRS):** Sistema de giro oficial de 5 pruebas de Wall Kicks para todas las piezas (incluyendo la barra I).
* **Lock Delay Oficial:** Margen de 500 ms al contactar superficie con hasta 15 Move Resets antes de fijar la pieza.
* **Detección de T-Spins:** Regla oficial de las 3 esquinas con bonificación de ataque y puntaje diferenciado para Single, Double y Triple.
* **Físicas de Cascada (The Next Tetris):**
  * Al completarse una línea, los bloques suspendidos en el aire **se detienen durante 0.5 segundos** (gravedad suspendida).
  * Luego, **se deslizan suavemente hacia abajo a 60 FPS**. Si al aterrizar forman nuevas filas completas, se limpian en cadena (Chain Reactions acumulativas).
* **Generación de Cubos 4x4 (Macrobloques):**
  * **Monocubos de Oro (4x4):** 4 piezas del mismo tipo. Textura de lingote de oro pulido reflectante.
  * **Multicubos de Plata (4x4):** 4 piezas de tipos mixtos combinadas en cuadrado perfecto. Textura de cromo/platino espejo.

---

## 4. Nuevo Sistema de Combate 1v1 y Salud (HP 100)

Se sustituyó el modelo tradicional de inyección masiva de basura (que provocaba muertes súbitas involuntarias en 1 ataque) por un sistema táctico de **combate por desgaste y salud (HP)**:

### 4.1. Parámetros de Salud (HP)
* **Vida Máxima e Inicial:** **100 HP** por jugador.
* **Condición de Derrota:** Cuando el HP del jugador desciende a 0 (`currentHp <= 0`).

### 4.2. Daño por Ataques
* **Tetris Estándar (4 líneas limpias):** Inflige **10 HP de daño directo** al rival (sin empujar basura física para no saturar su tablero).
* **Tetris con Cubo Plateado:** Inflige **10 HP de daño** + inyecta **1 línea diamantada resistente**.
* **Tetris con Cubo Dorado:** Inflige **10 HP de daño** + inyecta **2 líneas diamantadas resistentes**.
* **Ataques Menores y T-Spins:**
  * Single: 2 HP
  * Double: 4 HP
  * Triple: 7 HP
  * T-Spin Single: 5 HP
  * T-Spin Double: 10 HP
  * T-Spin Triple: 15 HP

### 4.3. Regeneración de Vida por Combos
El encadenamiento de limpiezas dentro de la ventana de gracia de 3.0 segundos otorga curación directa:
* **Combo x3:** Recupera **+5 HP**.
* **Combo x5:** Recupera **+20 HP**.
* **Combo x6 o superior:** Recupera **+50 HP**.
* La salud se limita al techo de 100 (`currentHp = min(100, currentHp + heal)`), acompañada de un banner visual verde de notificación.

### 4.4. Líneas Diamantadas / Blindadas
* A diferencia de la basura común, las líneas diamantadas son bloques resistentes con acabado visual cristalino en cian y blanco diamante.
* No empujan al rival hasta el techo de golpe (solo entran 1 o 2 líneas en la base).
* Deben ser destruidas completando filas horizontales para recuperar el control de la matriz.

### 4.5. Mecánica Anti-Muerte Súbita en el Techo (Top Out Mitigation)
* Si un jugador satura su tablero y las piezas intentan aparecer colisionando en la fila 0, **no muere de forma inmediata**.
* El sistema le aplica una penalización de **25 HP de daño** y ejecuta un **despeje de emergencia de las 4 filas superiores**, permitiéndole respirar y continuar jugando para intentar una remontada. Solo si ese daño reduce su vida a 0 HP se declara el K.O. definitivo.

### 4.6. Escudo de Plasma (Inmunidad Zone)
* Se recarga acumulando de 0 a 5 puntos (Triples +1, Tetris +2, cubos especiales).
* Al activarse (mediante el botón de la botonera o tocando la tarjeta en la columna lateral), otorga **20 segundos de inmunidad total**:
  * **0 daño a la vida recibido.**
  * **Bloqueo y descarte total de líneas de ataque y diamantadas.**

---

## 5. UI/UX Móvil y Motor Gráfico Canvas PBR (`tetris_game_screen.dart`)

* **Optimización de Espacio:** Se eliminó el encabezado con el título fijo, liberando más de 35 px verticales.
* **Tablero Maximizado Dinámico:** La cuadrícula 10x20 se calcula mediante `LayoutBuilder` utilizando todo el alto disponible y manteniendo la relación de aspecto estricta 1:2.
* **Cero Desborde (Zero Overflow):**
  * Las columnas laterales se ajustaron a 46 px con espaciados de 3.5 px.
  * Todo el bloque central (Columna Izquierda + Tablero + Columna Derecha) y la botonera inferior están envueltos en `FittedBox(fit: BoxFit.scaleDown)`, garantizando adaptabilidad en cualquier pantalla móvil sin franjas amarillas de error.
* **Ubicación del Escudo:** Reubicado en la columna lateral izquierda, justo debajo del recuadro de `LÍNEAS`, con icono de escudo brillante, indicador numérico `(X/5)` y 5 pips de carga.
* **HUD de Combate Superior:** Monitor compacto que muestra tu barra de vida (`HP: 100/100`) y la de tu rival (`RIVAL: 100/100`), cambiando de color dinámicamente según el nivel de salud (Verde/Cian ➔ Amarillo ➔ Rojo).
* **Selector de Arenas Dinámico (4 Mapas Temáticos):**
  Al pulsar el botón central **MAPA**, el escenario cicla de forma instantánea sin interrumpir la partida:
  1. 🌌 **Cyberpunk Neón** (Aura cian/azul con rejilla láser).
  2. ⚡ **Gameros Arena** (Aura violeta/índigo con emblema oficial).
  3. 🚀 **Espacio Profundo** (Nebulosa cósmica y vacío estelar).
  4. 🕹️ **Retro Arcade 1989 CRT** (Verde fósforo clásico con scanlines).
  * La elección del mapa se guarda en `SharedPreferences` para persistir entre sesiones.

---

## 6. Protocolo de Red en Tiempo Real (`tetris_realtime_service.dart`)

La comunicación multijugador utiliza canales WebSocket de Supabase (`match:<matchId>`):

### 6.1. Contrato de Paquetes Broadcast
* **`player_ready`**: `{ user_id, team_id }`
* **`match_start`**: Dispara la cuenta regresiva e inicio simultáneo.
* **`team_attack`**:
  ```json
  {
    "sender_team_id": "UUID",
    "target_team_id": "UUID",
    "lines": 4,
    "tier": "none | silver | gold | diamond",
    "damage_hp": 10,
    "diamond_lines": 2,
    "sender_hp": 85
  }
  ```
* **`player_knockout`**: `{ user_id, team_id }`
* **`match_end`**: `{ winner_team_id }`

### 6.2. Detección de Presencia y Resiliencia Móvil
* **Soporte Completo para Mapas de Supabase:** Se implementó `_checkIsOpponent` para analizar correctamente tanto colecciones como `Map<String, dynamic>` provenientes de `_channel.presenceState()`, erradicando desconexiones falsas.
* **Ventana de Gracia Ampliada:** La tolerancia ante microcortes se fijó en **120 segundos (2 minutos)**, eliminando cierres involuntarios a los 30 segundos.
* **Cancelación Reactiva:** Cualquier paquete entrante de ataque o sincronización reinicia y cancela automáticamente el temporizador de reconexión.

---

## 7. Esquema de Base de Datos y Contratos RPC (Supabase)

### 7.1. Esquema `tetris`
* `tetris.ratings`: Tabla de ELO por usuario (`user_id`, `elo`, `matches_played`, `wins`, `losses`). Base: 1000 ELO, K=32.
* `tetris.match_tetris`: Registro de partidas (`id`, `room_code`, `status`, `team_1_id`, `team_2_id`, `format`, `winner_team_id`).
* `tetris.match_tetris_players`: Desglose por jugador (`match_id`, `user_id`, `team_id`, `lines_cleared`, `lines_sent`, `is_alive`).
* `tetris.matchmaking_queue`: Cola automática de emparejamiento.

### 7.2. Funciones RPC Oficiales
1. `tetris.buscar_partida_automatica(p_user_id, p_gamertag)`: Empareja dos jugadores en espera o genera una nueva sala en estado `waiting`.
2. `tetris.actualizar_rating_elo(p_winner_user_id, p_loser_user_id)`: Aplica la fórmula ELO oficial y persiste los puntos en `tetris.ratings`.
3. `public.reportar_resultado_cruce_torneo(match_id, winner_team_id, tournament_id)`: Hace avanzar al ganador en los cuadros/brackets de torneos organizados en Gameros Core.
4. `public.reportar_resultado_partida_externa(p_juego_nombre, p_match_id, p_winner_team_id, p_payload)`: Notifica al ledger de actividad y estadísticas generales de Gameros.

---

## 8. Hoja de Ruta (Roadmap) de Integración Integral con Gameros Core

Para la sincronización con Claude y el equipo de Gameros Core, los siguientes pasos de integración son los prioritarios:

1. **Lobby Unificado de Gameros:**
   Permitir que desde la aplicación principal de Gameros se pueda desafiar a un amigo directamente o lanzar un duelo de Tetris mediante Deep Linking (`gameros-tetris://partida/<match_id>`).
2. **Guerras de Clanes (Clanes vs Clanes):**
   Conectar el modo competitivo con la tabla `public.equipos` para sumar puntos de clan y reputación por victorias en Tetris Now.
3. **Módulo de Torneos y Brackets Automáticos:**
   Conectar los eventos en vivo de Gameros para que los participantes de una llave de torneo ingresen directamente a su cruce y el resultado se asiente en el cuadro oficial.
4. **Modo Espectador / Streaming para TV:**
   Consolidar la pantalla `TetrisSpectatorScreen` con telemetría dual para castear y transmitir partidas 1v1 en pantallas grandes o transmisiones de Twitch/Kick.
5. **Economía y Recompensas:**
   Conectar las victorias con el sistema de monedas/créditos de Gameros para premiar a los mejores clasificados del ranking ELO mensual.
