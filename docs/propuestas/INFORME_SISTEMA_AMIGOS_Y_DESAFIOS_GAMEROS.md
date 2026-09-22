# Informe Técnico y Funcional: Sistema de Amigos, Solicitudes, Mensajería y Desafíos Directos en Tetris Now y su Integración con el Ecosistema Gameros

## Resumen Ejecutivo de la Arquitectura Social

La plataforma Gameros se fundamenta en un ecosistema competitivo interconectado donde múltiples títulos de juego operan como módulos satélites coordinados por un núcleo central de servicios. Dentro de esta topología distribuida, **Tetris Now** constituye el cliente satélite especializado en competencias de bloques en tiempo real, mientras que la plataforma **Gameros Core** actúa como el repositorio soberano de identidades, perfiles, clanes, torneos, economía virtual y relaciones sociales.

El presente informe detalla la arquitectura técnica y funcional del sistema social y de emparejamiento privado, abarcando la gestión de vínculos de amistad, la tramitación de solicitudes, la persistencia de estados de presencia en vivo, la mensajería asíncrona y la orquestación de desafíos directos 1v1 entre usuarios. Asimismo, se expone la hoja de ruta para consumar la interoperabilidad plena entre el cliente móvil desarrollado en Flutter y los servicios backend desplegados en Supabase (`bgwvtfgwhpinfotzyucn`).

| Dimensión Arquitectónica | Componente Satélite (Tetris Now) | Componente Central (Gameros Core) |
| :--- | :--- | :--- |
| **Gobernanza de Identidad** | Consumidor de sesión OAuth (Google / Email) | `auth.users` y tabla maestra `public.usuarios` |
| **Relaciones Sociales** | `FriendsService`, `FriendsScreen` | Tabla relacional `public.amigos` con RLS |
| **Presencia y Actividad** | Notificador de estado en cliente | Atributos `estado_juego` y `juego_actual` en `public.usuarios` |
| **Mensajería / Retos** | Visor de chat contextual en partida | Tabla transaccional `public.mensajes_amigos` |
| **Emparejamiento Privado** | Creación y suscripción a salas de duelo | Esquema `tetris.match_tetris` y canal Realtime Supabase |
| **Seguridad de Acceso** | Claves anónimas con JWT del usuario | Políticas Row Level Security (RLS) en Postgres |

---

## Modelo de Gobernanza y Separación de Esquemas en Base de Datos

La arquitectura de datos respeta el principio de desacoplamiento entre el núcleo social y los motores de juego específicos. Para evitar inconsistencias y redundancia de almacenamiento, la base de datos centralizada de Supabase se estructura en dos esquemas bien diferenciados:

```
+-------------------------------------------------------------------------+
|                       PROYECTO SUPABASE CENTRAL                         |
|                             bgwvtfgwhpinfotzyucn                        |
+------------------------------------+------------------------------------+
|         ESQUEMA public             |          ESQUEMA tetris            |
|       (Soberano Gameros)           |      (Satélite Especializado)      |
+------------------------------------+------------------------------------+
|  - public.usuarios                 |  - tetris.ratings (ELO)            |
|  - public.amigos                   |  - tetris.match_tetris (Partidas)  |
|  - public.mensajes_amigos          |  - tetris.match_tetris_players     |
|  - public.equipos (Clanes)         |  - tetris.matchmaking_queue        |
|  - public.torneos                  |  - tetris.reportes_resultado       |
+------------------------------------+------------------------------------+
```

### Tabla Maestra de Usuarios (`public.usuarios`)
Contiene los perfiles unificados de todos los jugadores de la plataforma. Ningún juego satélite crea perfiles independientes; todos consumen esta entidad compartida:

| Campo | Tipo de Dato | Restricciones | Descripción Funcional |
| :--- | :--- | :--- | :--- |
| `id` | `UUID` | Primary Key, FK `auth.users(id)` | Identificador criptográfico único de usuario |
| `gamertag` | `TEXT` | NOT NULL, UNIQUE | Nombre de combate público visible en el juego |
| `username` | `TEXT` | UNIQUE | Nombre de usuario de red social con prefijo `@` |
| `avatar_url` | `TEXT` | NULLABLE | URL pública del avatar o fotografía de perfil |
| `nivel` | `INTEGER` | DEFAULT 1 | Nivel de experiencia general acumulado en Gameros |
| `reputacion` | `INTEGER` | DEFAULT 100 | Índice de conducta deportiva y juego limpio |
| `estado_juego` | `TEXT` | DEFAULT 'Desconectado' | Actividad actual ('En el Hub', 'Tetris Now', etc.) |
| `created_at` | `TIMESTAMPTZ` | DEFAULT `now()` | Fecha y hora de registro en la plataforma |

### Tabla de Relaciones de Amistad (`public.amigos`)
Modela el grafo social bidireccional entre usuarios de la plataforma:

| Campo | Tipo de Dato | Restricciones | Descripción Funcional |
| :--- | :--- | :--- | :--- |
| `id` | `UUID` | Primary Key, DEFAULT `gen_random_uuid()` | Identificador del registro de vínculo |
| `solicitante_id` | `UUID` | FK `public.usuarios(id)` ON DELETE CASCADE | Usuario que origina la petición de amistad |
| `receptor_id` | `UUID` | FK `public.usuarios(id)` ON DELETE CASCADE | Usuario destinatario de la invitación |
| `estado` | `TEXT` | CHECK (`estado` IN ('pendiente', 'aceptada', 'rechazada', 'bloqueado')) | Estado administrativo de la relación |
| `created_at` | `TIMESTAMPTZ` | DEFAULT `now()` | Marca temporal de emisión de la solicitud |
| `updated_at` | `TIMESTAMPTZ` | DEFAULT `now()` | Marca temporal de última modificación |

### Tabla de Mensajería y Desafíos Escritos (`public.mensajes_amigos`)
Canal de mensajería directa asíncrona entre amigos aprobados:

| Campo | Tipo de Dato | Restricciones | Descripción Funcional |
| :--- | :--- | :--- | :--- |
| `id` | `UUID` | Primary Key, DEFAULT `gen_random_uuid()` | Identificador único del mensaje |
| `emisor_id` | `UUID` | FK `public.usuarios(id)` ON DELETE CASCADE | Usuario que redacta el mensaje o reto |
| `receptor_id` | `UUID` | FK `public.usuarios(id)` ON DELETE CASCADE | Usuario destinatario del mensaje |
| `mensaje` | `TEXT` | NOT NULL | Cuerpo textual del mensaje o código de partida |
| `leido` | `BOOLEAN` | DEFAULT `false` | Bandera de confirmación de lectura |
| `created_at` | `TIMESTAMPTZ` | DEFAULT `now()` | Marca temporal de despacho del mensaje |

---

## Implementación Vigente en el Cliente Tetris Now

El cliente móvil desarrollado en Flutter dispone de una implementación funcional que articula la capa visual con los servicios backend mediante inyección del cliente `SupabaseConfig.client`.

### Capa de Servicio: `FriendsService` (`lib/services/friends_service.dart`)

El servicio encapsula las operaciones asíncronas sobre la base de datos de Gameros.

#### 1. Recuperación de la Lista de Amigos (`getFriends`)
El método ejecuta una consulta combinada que resuelve la naturaleza bidireccional de la amistad:
```dart
final res = await supabase
    .from('amigos')
    .select()
    .or('solicitante_id.eq.${user.id},receptor_id.eq.${user.id}')
    .eq('estado', 'aceptada');
```
Para cada registro devuelto, determina cuál de los dos identificadores corresponde al amigo y resuelve paralelamente dos enriquecimientos de datos:
1. **Datos de Perfil General:** Consulta `public.usuarios` para obtener `gamertag`, `username`, `avatar_url` y el estado de presencia en tiempo real (`estado_juego`).
2. **Métricas de Rendimiento Específicas de Tetris:** Consulta el esquema satélite `tetris.ratings` para obtener la puntuación ELO del amigo (`tetrisElo`).

En caso de que el usuario juegue en modalidad de invitado (*Guest Mode*) o no disponga de conexión activa a Supabase, el servicio conmuta automáticamente a una nómina de demostración local (`_getDemoFriends`) para preservar la fluidez de la interfaz.

#### 2. Tramitación de Solicitudes de Amistad (`getPendingRequests`, `sendFriendRequest`, `respondToRequest`)
* **Búsqueda y Envío:** Permite localizar jugadores mediante una búsqueda insensible a mayúsculas y minúsculas sobre múltiples campos (`gamertag`, `nombre`, `email`, `username`):
```dart
final targetUser = await supabase
    .from('usuarios')
    .select('id')
    .or('gamertag.ilike.%$query%,nombre.ilike.%$query%,email.ilike.%$query%,username.ilike.%$query%')
    .maybeSingle();
```
Al hallar una coincidencia válida que no sea el propio usuario, inserta un registro en estado `pendiente`.
* **Respuesta:** Actualiza el campo `estado` a `'aceptada'` o `'rechazada'`, registrando la marca de tiempo `updated_at`.

#### 3. Mensajería Directa Contextual (`getDirectMessages`, `sendDirectMessage`)
Permite intercambiar mensajes directos almacenados en `public.mensajes_amigos`. La consulta recupera los últimos 50 mensajes intercambiados entre ambos participantes ordenados cronológicamente:
```dart
final res = await supabase
    .from('mensajes_amigos')
    .select()
    .or('and(emisor_id.eq.${user.id},receptor_id.eq.$friendUserId),and(emisor_id.eq.$friendUserId,receptor_id.eq.${user.id})')
    .order('created_at', ascending: true)
    .limit(50);
```

### Capa de Presentación: `FriendsScreen` (`lib/ui/friends_screen.dart`)

La interfaz gráfica ofrece una navegación intuitiva estructurada mediante un `TabBar` con dos secciones principales:
1. **Pestaña "Mis Amigos":**
   * Listado estilizado de contactos con tarjetas de fondo oscuro (`#161B22`) y bordes adaptativos según el estado de conexión (azul violeta `#5865F2` si está en línea, gris `#30363D` si está desconectado).
   * Avatar circular con indicador luminoso de presencia (verde para `'en_linea'`, gris para `'desconectado'`).
   * Información de telemetría social que detalla el juego en el que se encuentra el contacto (por ejemplo: *"Jugando Tetris Now"*, *"Jugando TrucoArg"*, *"Jugando Chess in Time"* o *"En el Hub de Gameros"*).
   * Acceso rápido al diálogo modal de mensajería/buzón (`IconButton` con icono de correo).
   * Botón destacado `INVITAR` para iniciar un encuentro contra dicho amigo.
2. **Pestaña "Solicitudes Pendientes":**
   * Lista de peticiones recibidas en estado pendiente.
   * Botones de acción rápida: botón verde de aceptación (`check_circle_rounded`) y botón rojo de rechazo (`cancel_rounded`).
3. **Diálogo de Búsqueda y Adición:**
   * Modal accesible desde la barra superior (`Icons.person_add_rounded`) que permite ingresar un término de búsqueda para remitir una solicitud instantánea a cualquier usuario de la plataforma.
4. **Ventana Flotante de Chat Directo:**
   * Diálogo modal interactivo (`_openChatDialog`) con burbujas de diálogo diferenciadas por color (índigo `#4F46E5` para mensajes propios, grafito `#21262D` para mensajes del amigo) y caja de texto para redactar mensajes o desafíos en tiempo real.

---

## Sistema de Presencia y Telemetría Cruzada Multi-Juego

Una de las fortalezas centrales del ecosistema Gameros radica en la visibilidad transversal de la actividad de los usuarios a través de todos los títulos de la compañía.

```
+-----------------------------------------------------------------------+
|                    ECOSISTEMA MULTI-JUEGO GAMEROS                     |
+-------------------+-------------------+---------------+---------------+
|    TETRIS NOW     |     TRUCO ARG     | CHESS IN TIME | GAMEROS CORE  |
|  (Satélite 1v1)   |  (Cartas y Puntos)| (Ajedrez PBR) |  (Hub Matriz) |
+-------------------+-------------------+---------------+---------------+
         |                   |                  |               |
         +-------------------+------------------+---------------+
                             |
                   Reporte de Presencia
                             v
               +---------------------------+
               |  public.usuarios          |
               |  - estado_juego:          |
               |    "Jugando Tetris Now"   |
               |    "Jugando TrucoArg"     |
               |    "Jugando Chess in Time"|
               |    "En el Hub de Gameros" |
               +---------------------------+
```

### Mecánica de Actualización de Presencia
1. **Al Inicializar el Cliente:**  
   Cuando Tetris Now arranca y detecta una sesión válida en `SupabaseConfig.client.auth`, invoca el método de señalización social que actualiza la tupla del usuario en `public.usuarios`:
   ```sql
   UPDATE public.usuarios 
   SET estado_juego = 'Jugando Tetris Now', updated_at = now() 
   WHERE id = auth.uid();
   ```
2. **Durante la Partida en Vivo:**  
   Al entrar en un duelo 1v1 activo, el estado puede refinarse automáticamente a `'En Duelo 1v1 (Tetris)'`, informando a la red de contactos que el usuario se encuentra ocupado compitiendo.
3. **Al Abandonar o Suspender la Aplicación:**  
   Mediante la captura del ciclo de vida de Flutter (`WidgetsBindingObserver.didChangeAppLifecycleState`), al pausarse o cerrarse el cliente, se emite una actualización que restablece el valor a `'En el Hub de Gameros'` o `'Desconectado'`.

---

## Diagnóstico del Estado Actual de los Desafíos Directos

En la versión actual del cliente, el botón `INVITAR` ubicado junto a cada amigo en `FriendsScreen` redirige de forma genérica a la pantalla `CreateDuelScreen()`:
```dart
ElevatedButton(
  onPressed: () {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateDuelScreen()));
  },
  child: const Text('INVITAR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
)
```

### Limitación del Enfoque Actual
`CreateDuelScreen` es el radar de **matchmaking abierto** de la cola pública (`tetris.buscar_partida_automatica`). En consecuencia, pulsar `INVITAR` no envía un reto dirigido a ese amigo en particular, sino que ingresa al usuario en la cola global de emparejamiento con cualquier jugador disponible.

Para completar la experiencia competitiva de Gameros, es imperativo implementar el flujo de **Reto Privado Directo (Peer-to-Peer Challenge)**.

---

## Arquitectura para la Implementación de Desafíos Directos

El nuevo sistema de desafíos directos permitirá retar a un amigo específico sin importar si este se encuentra navegando en el menú de Tetris Now o interactuando en la aplicación central de Gameros.

```
JUGADOR A (Retador)                                 JUGADOR B (Amigo)
        |                                                   |
        | 1. Toca "RETAR" en FriendsScreen                  |
        |                                                   |
        | 2. Crea sala privada (is_private=true)            |
        |    en tetris.match_tetris                         |
        |--------------------------------------------+      |
        |                                            |      |
        | 3. Emite invitación vía Realtime/Notif     |      |
        |==================================================>|
        |                                                   | 4. Recibe banner emergente:
        |                                                   |    "¡Reto 1v1 de Jugador A!"
        |                                                   |
        |                                                   | 5. Presiona "ACEPTAR"
        |                                                   |
        |                                                   | 6. Se suscribe al canal
        |                                                   |    match:<match_id>
        |                                            |<-----+
        | 7. Ambos sincronizan presencia y envían    |
        |    evento "player_ready"                   |
        |<==========================================>|
        |                                            |
        | 8. Inicio simultáneo del combate 100 HP    |
        |    en TetrisGameScreen                     |
        |                                            |
```

### Componentes del Flujo de Desafío

#### 1. Creación de la Sala de Reto Privado
El servicio `TetrisMatchService` creará un registro de partida privada en `tetris.match_tetris`:
* `status`: `'pending'`
* `format`: `'1v1'`
* `is_private`: `true`
* `team_1_id`: `UUID` del retador (Team Alpha)
* `team_2_id`: `UUID` del amigo desafiado (Team Beta)
* `room_code`: Código alfanumérico corto de 6 caracteres (ej. `#TET982`)

#### 2. Notificación en Tiempo Real al Amigo Desafiado
La notificación se canaliza a través de dos vías complementarias para garantizar una recepción inmediata:
* **Vía WebSocket (Supabase Realtime):**  
  Emisión de un evento broadcast en el canal personal del usuario desafiado (`user_notifications:<friend_id>`):
  ```json
  {
    "event": "game_challenge",
    "challenge_id": "c7a8b2d1-0000-4000-8000-0123456789ab",
    "game_code": "tetris_now",
    "challenger_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "challenger_name": "Rey-ToRuS",
    "challenger_avatar": "https://.../avatar.png",
    "match_id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
    "room_code": "#TET982",
    "expires_at": "2026-09-12T21:45:00Z"
  }
  ```
* **Vía Mensajería de Respaldo:**  
  Inserción de un mensaje automático estructurado en `public.mensajes_amigos` con formato de invitación consumible por clientes que se reconecten en diferido.

#### 3. Interfaz del Desafiado: Diálogo Emergente de Reto
Cuando el amigo recibe el evento en su cliente, se dispara un diálogo no bloqueante con animación de pulso y cuenta regresiva de 30 segundos para aceptar:
* **Datos Visibles:** Avatar y Gamertag del retador, ELO actual y modo de juego (Combate 100 HP).
* **Acciones:**
  * **Botón Verde "ACEPTAR":** Cierra el modal, confirma la entrada del jugador en `tetris.match_tetris_players` y realiza la navegación directa hacia `TetrisGameScreen` conectado al canal `match:<match_id>`.
  * **Botón Rojo "RECHAZAR":** Envía el evento `challenge_declined` al canal del retador y descarta la invitación.

#### 4. Integración mediante Deep Linking con Gameros Core
Si el amigo desafiado se encuentra navegando dentro de la app general de Gameros o fuera del juego, el desafío se envía como notificación push de sistema que ejecuta el esquema URI oficial:
```
gameros-tetris://partida/<match_id>?equipo=team_2&retador=<challenger_id>
```
El servicio `DeepLinkService` (`lib/services/deep_link_service.dart`) ya se encuentra configurado en `main.dart` para interceptar este enlace y navegar inmediatamente al lobby de partida correspondiente:
```dart
DeepLinkService().onDeepLink.listen((payload) {
  if (payload.matchId != null) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => MatchLobbyScreen(
          initialMatchId: payload.matchId,
          tournamentId: payload.tournamentId,
        ),
      ),
    );
  }
});
```

---

## Políticas de Seguridad y Control de Acceso (RLS en Postgres)

La integridad de las interacciones sociales descansa sobre políticas estrictas de seguridad a nivel de fila (Row Level Security) ejecutadas en el servidor Postgres de Supabase.

### 1. Políticas sobre la Tabla `public.amigos`
* **Lectura (`SELECT`):**  
  Un usuario únicamente puede consultar los registros donde figure como solicitante o receptor:
  ```sql
  CREATE POLICY "amigos_select_policy" ON public.amigos
  FOR SELECT TO authenticated
  USING (solicitante_id = auth.uid() OR receptor_id = auth.uid());
  ```
* **Creación (`INSERT`):**  
  Un usuario autenticado solo puede crear solicitudes donde su propio identificador actúe como `solicitante_id`:
  ```sql
  CREATE POLICY "amigos_insert_policy" ON public.amigos
  FOR INSERT TO authenticated
  WITH CHECK (solicitante_id = auth.uid() AND solicitante_id != receptor_id);
  ```
* **Actualización (`UPDATE`):**  
  Únicamente el destinatario (`receptor_id`) está facultado para modificar el estado de la solicitud (aceptar o rechazar):
  ```sql
  CREATE POLICY "amigos_update_policy" ON public.amigos
  FOR UPDATE TO authenticated
  USING (receptor_id = auth.uid())
  WITH CHECK (receptor_id = auth.uid());
  ```

### 2. Políticas sobre la Tabla `public.mensajes_amigos`
* **Lectura e Inserción:**  
  Estrictamente restringidas al emisor y receptor legítimos del mensaje:
  ```sql
  CREATE POLICY "mensajes_select_policy" ON public.mensajes_amigos
  FOR SELECT TO authenticated
  USING (emisor_id = auth.uid() OR receptor_id = auth.uid());

  CREATE POLICY "mensajes_insert_policy" ON public.mensajes_amigos
  FOR INSERT TO authenticated
  WITH CHECK (emisor_id = auth.uid());
  ```

---

## Hoja de Ruta de Implementación para Sincronización con Claude

Para ejecutar la integración coordinada entre el satélite Tetris Now y el equipo de Gameros Core encabezado por Claude, se establece el siguiente cronograma estructurado:

```
[FASE 1: CONTRATOS RPC Y DB]
- Validación de esquemas en Supabase (public.amigos y public.mensajes_amigos)
- Creación de la función RPC tetris.crear_desafio_privado(p_amigo_id)
        |
        v
[FASE 2: SERVICIO DE DESAFÍOS EN DART]
- Extensión de FriendsService: enviarDesafioAmigo() y escucharDesafiosEntrantes()
- Integración de canales personales de broadcast en Supabase Realtime
        |
        v
[FASE 3: UI DE RETOS Y DIÁLOGO RECIPROCO]
- Transformación del botón "INVITAR" en FriendsScreen a "RETAR" con modal de espera
- Creación del widget ChallengeReceivedDialog con temporizador de 30s
        |
        v
[FASE 4: INTEGRACIÓN CON GAMEROS CORE Y PRUEBAS]
- Validación cruzada de Deep Linking (gameros-tetris://) desde la app Gameros
- Batería de pruebas de desconexión, rechazo de reto y arranque simultáneo
```

### Tareas Asignadas por Equipo de Desarrollo:

| Hito / Tarea | Responsable | Entregable Técnico |
| :--- | :--- | :--- |
| **RPC de Creación de Desafíos** | Claude / Gameros Core | Función Postgres `tetris.crear_desafio_privado` con validación de amistad previa |
| **Canal de Notificaciones Realtime** | Claude / Gameros Core | Configuración de canal `user_notifications:<user_id>` con permisos de difusión |
| **Cliente de Retos Directos** | Spark / Tetris Now | Métodos `sendChallengeToFriend` y listener de retos en `FriendsService` |
| **UI de Confirmación y Lanzamiento** | Spark / Tetris Now | Diálogo `ChallengeReceivedDialog` y auto-conexión a `TetrisGameScreen` |
| **Pruebas de Integración y CI** | Equipo Conjunto | Verificación de flujo completo en dispositivos físicos y reporte ELO |

---

## Conclusiones Técnicas y Recomendaciones

El subsistema de amigos y relaciones sociales implementado en Tetris Now cuenta con una base sólida, tipada en Dart 3 y perfectamente alineada con los estándares de la base de datos de Gameros. Los modelos de entidad (`FriendModel`, `FriendRequestModel`, `FriendMessageModel`) y la interfaz actual (`FriendsScreen`) satisfacen plenamente las necesidades de consulta, agregación de contactos y mensajería directa.

La transición desde el emparejamiento genérico actual hacia los **desafíos directos 1v1** representa el paso evolutivo fundamental para dotar al juego del dinamismo propio de los eSports modernos. Al sincronizar este protocolo con el agente Claude de Gameros Core, se recomienda priorizar el uso de identificadores criptográficos `UUID` validados mediante `auth.uid()` en las funciones RPC, asegurar que el canal Realtime de Supabase mantenga una ventana de gracia adecuada para dispositivos móviles y afianzar los esquemas de Deep Linking para que cualquier usuario pueda retar a un colega con un solo toque desde cualquier rincón del ecosistema Gameros.

---

## Referencias y Documentación Técnica

* Repositorio de Código Fuente: [adh3us/tetris-now en GitHub](https://github.com/adh3us/tetris-now)
* Especificación Técnica e Integración Oficial: [Tetris Now by gAmeros — Especificaciones Técnicas](https://docs.google.com/document/d/1FowFEdWpn5Kt9gGl3qFWY8YNz7LzxM7kmrZg59BnHYc/edit)
* Módulo Oficial de Desarrollo: [Gameros: Tetris VS](https://docs.google.com/document/d/1-H9zJ7LDJfdw_hW2WdIEVlKdSmvZZ2Sxwf9_lZLTRUA/edit)
* Esquema SQL Oficial de Fase 0: `master_workspace/supabase/fase0_init.sql`
