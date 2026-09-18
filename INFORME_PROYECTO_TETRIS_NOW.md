# Informe de Arquitectura, Estado del Proyecto y Últimos Avances — Tetris Now

> **Documento de Contexto Integral para Agentes de IA (Gemini / Claude)**  
> **Proyecto:** Tetris Now (Cliente Satélite de eSports)  
> **Ecosistema Central:** Plataforma Gameros (`adh3us/gameros`)  
> **Repositorio Oficial:** `adh3us/tetris-now`  
> **Rama de Desarrollo Activa:** `reconciliacion` (sincronizada con `origin/reconciliacion`)  
> **Fecha de Actualización:** Septiembre 2026  
> **ID de Aplicación Android:** `com.gameros.tetris`  
> **Entorno de Compilación:** Flutter 3.47.2 • Dart 3 • Android SDK 36 • Java 25  
> **Backend / BaaS:** Supabase Proyecto `bgwvtfgwhpinfotzyucn` (AWS sa-east-1, São Paulo)  
> **Instalador APK Última Versión:** [Descargar app-debug.apk](https://github.com/adh3us/tetris-now/releases/download/latest-apk/app-debug.apk)

---

## 1. Visión General del Proyecto y Rol en el Ecosistema

**Tetris Now** es un cliente competitivo de Tetris en tiempo real con estética **Neón Arcade / Arcade de Bolsillo de los 90s**, diseñado específicamente como un **módulo satélite subordinado a la plataforma Gameros Core**.

### Topología de Gobernanza Distribuida
1. **Gameros Core (`adh3us/gameros`) — Plataforma Soberana:**
   - Administra la identidad de los usuarios (`auth.users`), perfiles oficiales y gamertags (`public.usuarios`), sistema social de amigos (`public.amigos`), mensajería (`public.mensajes_amigos`), clanes (`public.equipos`), torneos oficiales (`public.torneos`) y el cuadro maestro de cruces (`public.partidas`).
2. **Tetris Now (`adh3us/tetris-now`) — Ejecutor de Juego Especializado:**
   - **No duplica tablas maestras de usuarios.**
   - Consume la sesión iniciada a través de Supabase Auth (Google Sign-In / Correo y Contraseña).
   - Posee un esquema aislado en Postgres (`tetris.*`) para almacenar métricas propias del juego: clasificaciones ELO/MMR (`tetris.ratings`), emparejamientos activos (`tetris.match_tetris`), jugadores en partidas (`tetris.match_tetris_players`), colas de espera (`tetris.matchmaking_queue`) y reportes de resultados (`tetris.reportes_resultado`).
   - Reporta resultados de partidas 1v1 regulares mediante `public.reportar_resultado_partida_externa` y de cruces de torneos mediante `public.reportar_resultado_cruce_torneo`.

```
+-------------------------------------------------------------------------------+
|                           PROYECTO SUPABASE CENTRAL                           |
|                               bgwvtfgwhpinfotzyucn                            |
+---------------------------------------+---------------------------------------+
|            ESQUEMA public             |            ESQUEMA tetris             |
|          (Soberano Gameros)           |        (Satélite Especializado)       |
+---------------------------------------+---------------------------------------+
|  - public.usuarios (perfiles GamerOS) |  - tetris.ratings (MMR / ELO)         |
|  - public.amigos (grafo de amistad)   |  - tetris.match_tetris (partidas)     |
|  - public.mensajes_amigos             |  - tetris.match_tetris_players        |
|  - public.equipos (clanes)            |  - tetris.matchmaking_queue (colas)   |
|  - public.torneos (torneos globales)  |  - tetris.reportes_resultado          |
|  - public.partidas (cruces brackets)  |                                       |
+---------------------------------------+---------------------------------------+
```

---

## 2. Invariantes Arquitectónicas y Reglas de Oro (MODIFICACIONES PROHIBIDAS)

Al proponer o implementar código, cualquier agente de IA **debe acatar estrictamente las siguientes directivas innegociables**:

1. ❌ **Audio Puro (Cero Vibración Nativa):**
   - El juego opera con efectos de sonido (SFX) de baja latencia mediante `audioplayers`.
   - **Prohibido** incluir `<uses-permission android:name="android.permission.VIBRATE"/>` en `AndroidManifest.xml`.
   - **Prohibido** incluir librerías como `vibration` en `pubspec.yaml` (incompatibles con Android SDK 36 / Java 25).
2. ❌ **Separación de Responsabilidades Innegociable:**
   - `lib/game/tetris_engine.dart` contiene la física y lógica matemática pura del juego (matriz, piezas, gravedad, combos, cascadas, rotaciones SRS, cubos especiales). **No debe modificarse para tareas visuales, animaciones o llamadas a Supabase.**
   - Las animaciones, efectos, modales e interactividad táctil pertenecen exclusivamente a la capa de UI (`lib/ui/`).
   - La persistencia, consultas a Supabase y sondeos de red pertenecen a `lib/services/`.
3. ❌ **Persistencia Metálica de Cubos Especiales:**
   - Los bloques formados al armar 4x4 (**Cubo Dorado / Monocube** o **Cubo Plateado / Multicube**) conservan su textura metálica reflectiva de forma permanente, aun cuando se rompan parcialmente en líneas individuales o escalonadas. Nunca regresan al color de la pieza base original.
4. ❌ **Hard Drop Exclusivo en Botón Físico:**
   - La caída instantánea de pieza (`Hard Drop`) se ejecuta exclusivamente desde el botón físico de la botonera o mediante doble toque configurado. Mover la palanca o joystick analógico hacia arriba **no debe** arrojar la ficha de golpe.
5. ❌ **Identidad Visual "Neón Arcade" y "Arcade de Bolsillo":**
   - Paleta de diseño:
     - Fondo Carcasa / Chasis: Gris oscuro texturizado mate (`Color(0xFF0F1322)` / `Color(0xFF070B19)`).
     - Pantalla CRT: Azul noche profundo (`Color(0xFF070B19)`) con grilla técnica al 5% de opacidad y borde neón sutil.
     - Acentos Primarios: Cian Neón (`Color(0xFF00F0FF)`), Magenta Neón (`Color(0xFFFF007F)`), Amarillo Citrino (`Color(0xFFFFD700)` / `Color(0xFFFFE600)`), Púrpura Eléctrico (`Color(0xFF7928CA)`).
     - Botones físicos: Textura 3D biselada con sombra de profundidad inferior (`BoxShadow`), hundimiento mecánico en pulsación y resplandor lumínico de contacto de microswitch.
6. ❌ **Estricto Cumplimiento de Dart 3 y Tipado Supabase:**
   - Imports siempre arriba de cada archivo.
   - Columnas UUID en Supabase (`team_1_id`, `team_2_id`, `usuario_id`, etc.) deben pasarse como UUID válidos, no cadenas arbitrarias.
   - Manejo nulo estricto (sound null-safety).

---

## 3. Estructura del Código Fuente (`lib/`)

```
lib/
├── core/
│   └── supabase_config.dart          # Inicialización y singleton del cliente Supabase
├── game/
│   ├── tetris_engine.dart            # Motor matemático: matriz, gravedad, combos, cubos dorados/plata
│   └── tetris_types.dart             # Modelos de pieza, rotaciones, coordenadas y tipos de bloque
├── services/
│   ├── audio_service.dart            # Reproductor SFX arcade con audioplayers
│   ├── deep_link_service.dart        # Gestión de enlaces profundos para invitaciones y salas
│   ├── desafio_service.dart          # Gestión de desafíos directos 1v1 y presencia entre amigos
│   ├── friends_service.dart          # Grafo social en public.amigos (listar, solicitar, aceptar, bloquear)
│   ├── gameros_profile_service.dart  # Consulta, creación y auto-aprovisionamiento en public.usuarios
│   ├── tetris_match_service.dart     # Matchmaking 1v1, sondeo de colas y contratos de reporte
│   ├── tetris_realtime_service.dart  # Canales Realtime de Supabase (tableros rivales, basura de líneas)
│   └── tournament_service.dart       # Integración con torneos Gameros y reporte de cruces de brackets
├── ui/
│   ├── amigos_tab.dart               # Pestaña social de amigos con estilo Neón Arcade
│   ├── browse_rooms_screen.dart      # Explorador de salas públicas
│   ├── clan_challenges_screen.dart   # Desafíos entre clanes Gameros
│   ├── create_duel_screen.dart       # Radar de emparejamiento 1v1 y sala de espera
│   ├── friends_screen.dart           # Gestión de amistades, código de amigo y retos directos
│   ├── home_shell.dart               # Shell de navegación inferior con fondo Neón Arcade
│   ├── jugar_tab.dart                # Selector de modos (1v1 Rápida, Práctica Solitario, High Scores)
│   ├── match_lobby_screen.dart       # Sala previa de partida 1v1
│   ├── quick_play_screen.dart        # Búsqueda rápida 1v1 con sondeo reactivo
│   ├── salas_tab.dart                # Pestaña de salas manuales
│   ├── tetris_game_screen.dart       # Pantalla de juego activo (Arcade de Bolsillo, CRT, minimapa rival)
│   ├── tienda_tab.dart               # Tienda cosmética (en desarrollo)
│   ├── torneos_tab.dart              # Explorador de torneos Gameros, inscripción y mis torneos
│   ├── tournament_brackets_screen.dart # Árbol de cruces de torneos y botón "JUGAR CRUCE"
│   └── virtual_controller.dart       # Botonera táctil 3x2 con feedback táctil y lumínico
└── main.dart                         # Punto de entrada, bootstrap de Supabase y rutas principales
```

---

## 4. Cronología de los Últimos Avances (Hitos Recientes)

### Hito 1: Integración Completa con Torneos Gameros Core
- **Contrato Oficial:** Se integró la función RPC soberana `public.reportar_resultado_cruce_torneo(p_partida_id, p_ganador_inscripcion_id, p_empate, p_metadata)`.
- **Inscripción y Navegación:** Pestaña `TorneosTab` con pestañas *"TORNEOS DISPONIBLES"* y *"MIS TORNEOS"* (con opción para darse de baja).
- **Brackets y Cruces en Vivo:** Pantalla `tournament_brackets_screen.dart` que dibuja el árbol de cruces. Si el cruce está activo y el usuario autenticado participa, habilita el botón **"JUGAR CRUCE"**, enlazando la partida competitiva directamente con `TetrisGameScreen`.

### Hito 2: Dinámica de Combate 1v1 y Sincronización en Vivo
- **Ataques al Rival:** Cada Tetris (4 líneas) o combo consecutivo genera líneas de basura que se envían directamente al rival vía canal de Supabase.
- **Minimapa en Vivo del Rival:** Durante la partida, la pantalla muestra un minimapa en tiempo real que refleja la matriz del rival con un LED verde/rojo que indica el estado de conexión del oponente.
- **Corte Simultáneo de Partida:** Al caer uno de los dos rivales, se detiene la partida inmediatamente para ambos, presentando la pantalla con cartel de **GANADOR** o **PERDEDOR** y el desglose de estadísticas.

### Hito 3: Rediseño Global "Neón Arcade" (HomeShell, Jugar, Amigos, Torneos)
- Fondo unificado azul noche profundo (`Color(0xFF070B19)`) con grilla geométrica sutil al 5% de opacidad.
- Tarjetas con bordes brillantes y biseles sombreados simulando marquesinas de máquinas arcade.
- Lista de "TOP 10 GLOBAL" con tipografía de *High Score*, puntajes en amarillo brillante y medallas de podio (oro, plata y bronce).

### Hito 4: Rediseño "Arcade de Bolsillo" para la Pantalla de Juego
- Transformación de `tetris_game_screen.dart` en una recreativa portátil física:
  - **Cabezal Superior:** Barras de vida HP (amarillo citrino para el jugador local, rojo neón para el rival), temporizador central y contador de piezas.
  - **Pantalla Central CRT:** Matriz de juego enmarcada con biseles de tubo catódico y minimapa del rival integrado a un costado.
  - **Botonera Inferior 3D:** Botones con biselado físico, etiquetas claras (ROTAR, DROP, HOLD, ESCUDO, ATAQUE, MAPA) y espaciado ergonómico protegido contra desbordes (`FittedBox`).

### Hito 5: Dinamismo Táctil y Feedback Visual (Pulsación y Efectos)
- **Botonera Reactiva:** Detección de gestos (`onTapDown`, `onTapUp`, `onTapCancel`). Al pulsar, el botón reduce su sombra inferior (efecto de hundimiento mecánico físico) y genera un resplandor instantáneo tipo destello de switch eléctrico.
- **Alerta de Daño en Pantalla CRT:** Cuando el jugador recibe daño o sus bloques se acercan al borde superior crítico, una viñeta perimetral roja parpadea sutilmente en el CRT.
- **Fogonazo Citrino al Limpiar Líneas:** Animación lumínica en amarillo brillante sobre las líneas eliminadas que intensifica su brillo al encadenar combos.

### Hito 6: Corrección del Récord de Combo Máximo
- **Diagnóstico:** El marcador de combo máximo en el modal de fin de partida siempre quedaba en `0` porque el contador instantáneo `_engine.combo` se reseteaba a cero al expirar la ventana de gracia de 3 segundos.
- **Solución:**
  - Se incorporó la variable acumulativa `int maxCombo = 0;` en `TetrisEngine`.
  - Cada vez que se encadenan líneas (`combo++`), si `combo > maxCombo`, se actualiza el récord.
  - Se visualiza el valor pico alcanzado en la fila de estadísticas de fin de partida (`_showResultDialog`).

### Hito 7: Resolución de 4 Problemas Críticos Recientes (Commit `53138c5`)

#### 1. Auto-registro en GamerOS y Código de Amigo Propio
- **Problema:** Un usuario registrado en Tetris Now existía en `auth.users` pero no en `public.usuarios`. Como resultado, no tenía `codigo_jugador` y al ingresar el código de otro amigo (ej. Víctor), Supabase abortaba la solicitud por violación de foreign key `solicitante_id` en `public.amigos`.
- **Solución:**
  - En `gameros_profile_service.dart`, se implementó auto-aprovisionamiento transparente en `getFullProfile()`: si no existe registro en `public.usuarios`, se crea inmediatamente con `id`, `nombre_display`, `username` y un `codigo_jugador` único de 6 caracteres alfanuméricos (`_generateUniquePlayerCode()`). Si el registro existía pero tenía el código nulo, se genera y actualiza en el acto.
  - Se inicializa su registro de rating en `tetris.ratings` con valor base de 1000 MMR.
  - En `friends_screen.dart`, el código de amigo `#CODIGO` se copia al portapapeles con un solo toque y el diálogo de agregar amigos limpia automáticamente los caracteres `#` y espacios.

#### 2. Búsqueda y Emparejamiento 1v1 con Jugadores Reales
- **Problema:** Al buscar partida 1v1 rápida, la pantalla no lograba emparejar jugadores reales o quedaba estancada.
- **Causa Raíz:**
  - El backend devolvía `status: 'waiting', match_id: null`. El cliente Flutter verificaba `status == 'waiting' && matchId != null`, por lo que nunca iniciaba el sondeo de cola.
  - La función RPC `tetris.buscar_partida_automatica` tenía un bug en SQL donde insertaba al mismo usuario dos veces en `match_tetris_players` en lugar de emparejar al rival con el retador.
- **Solución:**
  - Se creó `consultarEstadoMatchmaking(matchId, myTeamId)` en `tetris_match_service.dart` para consultar la RPC `mi_estado_matchmaking` mientras el jugador esté en cola sin match ID.
  - Se corrigieron `quick_play_screen.dart` y `create_duel_screen.dart` para activar el sondeo reactivo de inmediato ante `status == 'waiting'`.
  - Se corrigió la función en `supabase/0002_matchmaking_seguridad.sql`.

#### 3. Bug de Partida que Iniciaba 2 Veces al Desafiar a un Amigo
- **Problema:** Al desafiar a un amigo, las respuestas concurrentes del sondeo generaban que la pantalla `TetrisGameScreen` se abriera por duplicado (rutas apiladas en el navegador de Flutter).
- **Solución:**
  - En `friends_screen.dart`, se incorporaron banderas de bloqueo en vuelo (`_isEnteringMatch`, `_isPollingMatch`) y se canceló síncronamente el temporizador de sondeo antes de invocar `Navigator.push`.
  - En `home_shell.dart`, se pausa el temporizador de sondeo de desafíos entrantes al ingresar a una partida activa y se reanuda al regresar al menú principal.

#### 4. Validación para Salir del Match (Botón Atrás de Android)
- **Problema:** Al presionar el botón físico o gesto de "Atrás" de Android durante una partida activa, la aplicación regresaba intempestivamente al menú principal sin advertencia ni cierre limpio.
- **Solución:**
  - En `tetris_game_screen.dart`, se envolvió la pantalla con un widget `PopScope(canPop: _isMatchEnded, onPopInvokedWithResult: ...)`.
  - Se implementó `_confirmExitMatch()`: pausa el motor del juego y abre un modal Neón Arcade:
    > **¿ABANDONAR PARTIDA?**  
    > *Si sales ahora, se considerará derrota y perderás la partida en curso.*  
    > Botones: `[CONTINUAR]` (reanuda la partida) y `[ABANDONAR]` (ejecuta rendición limpia y sale al menú).

---

## 5. Pipeline de CI/CD y Generación de APK

- **Workflow:** `.github/workflows/build-apk.yml`
- **Disparador:** Push a las ramas `main` o `reconciliacion`.
- **Pasos del Pipeline:**
  1. Configuración de entorno: Java 25, Flutter 3.47.2, CMake.
  2. Inyección segura de variables de entorno de Supabase (`SUPABASE_URL`, `SUPABASE_ANON_KEY`).
  3. Ejecución de pruebas unitarias (`flutter test`): Actualmente **100% de tests aprobados**.
  4. Compilación del ejecutable Android (`flutter build apk --debug`).
  5. Publicación automática: El release de GitHub etiquetado como `latest-apk` se elimina y recrea en cada build exitoso para garantizar que la fecha y los binarios siempre estén sincronizados con el último commit.
- **Enlace de Descarga Directa Permanente:**
  👉 **`https://github.com/adh3us/tetris-now/releases/download/latest-apk/app-debug.apk`**

---

## 6. Guía de Interacción para el Agente Gemini

Cuando asumas tareas de desarrollo en este proyecto:

1. **Consulta este documento primero:** Asegúrate de entender si la funcionalidad que vas a tocar corresponde a la plataforma soberana (Gameros Core) o al cliente satélite (Tetris Now).
2. **Preserva los esquemas de base de datos:** No crees tablas en `public` que dupliquen lo existente. Si necesitas almacenar datos de Tetris, utiliza el esquema `tetris.*` o las columnas de `metadata` en JSONB.
3. **Mantén las Reglas de Oro:** No agregues paquetes de vibración, no mezcles lógica de red dentro de `tetris_engine.dart`, y no alteres la botonera arcade 3D sin seguir el patrón de diseño establecido.
4. **Verificación:** Tras modificar código de UI o motor, ejecuta las pruebas unitarias (`flutter test`) y asegúrate de que no existan errores de lint ni variables no utilizadas.
5. **Git Workflow:** La rama principal de trabajo actual es `reconciliacion`. Siempre confirma que el árbol esté limpio (`git status`) y utiliza mensajes de commit descriptivos con prefijos convencionales (`feat:`, `fix:`, `refactor:`, etc.).
