-- Fase 0 (cierre) — Matchmaking automático + seguridad de salas + ELO.
-- Este archivo documenta lo que ya está aplicado manualmente en producción
-- (Supabase: bgwvtfgwhpinfotzyucn). Se reconstruye acá porque un force-push
-- anterior sobre 'main' borró el commit original que lo agregaba al repo.
-- No volver a ejecutar sin revisar primero el estado real en Supabase.

create extension if not exists pgcrypto;

-- 1. Salas privadas: contraseña hasheada, nunca en texto plano.
alter table tetris.match_tetris
  add column if not exists room_name text not null default 'Duelo 1c1 Gameros',
  add column if not exists is_private boolean not null default false,
  add column if not exists password_hash text,
  add column if not exists allow_spectators boolean not null default true;

alter table tetris.match_tetris drop column if exists password;

create or replace function tetris.crear_sala_privada(
  p_room_name text,
  p_password text,
  p_team_1_id uuid,
  p_team_2_id uuid,
  p_format text default '1v1',
  p_allow_spectators boolean default true,
  p_tournament_id uuid default null,
  p_round_number int default 1
) returns tetris.match_tetris
language plpgsql
security definer
set search_path = tetris, public
as $$
declare
  v_match tetris.match_tetris;
begin
  insert into tetris.match_tetris (
    room_name, is_private, password_hash, allow_spectators,
    team_1_id, team_2_id, format, tournament_id, round_number, status
  ) values (
    p_room_name, true, crypt(p_password, gen_salt('bf')), p_allow_spectators,
    p_team_1_id, p_team_2_id, p_format, p_tournament_id, p_round_number, 'pending'
  )
  returning * into v_match;

  return v_match;
end;
$$;

create or replace function tetris.verificar_password_sala(
  p_match_id uuid,
  p_password text
) returns boolean
language sql
security definer
set search_path = tetris, public
as $$
  select coalesce(
    (select password_hash = crypt(p_password, password_hash)
     from tetris.match_tetris
     where id = p_match_id),
    false
  );
$$;

-- 2. RLS restrictiva (reemplaza los 'for all using (true)' iniciales).
alter table tetris.match_tetris enable row level security;
alter table tetris.match_tetris_players enable row level security;
alter table tetris.reportes_resultado enable row level security;

drop policy if exists "match_tetris_all" on tetris.match_tetris;
drop policy if exists "match_tetris_players_all" on tetris.match_tetris_players;
drop policy if exists "reportes_resultado_all" on tetris.reportes_resultado;

create policy "match_tetris_select_publicas_o_propias"
  on tetris.match_tetris for select
  using (
    is_private = false
    or exists (
      select 1 from tetris.match_tetris_players p
      where p.match_id = match_tetris.id and p.user_id = auth.uid()
    )
  );

create policy "match_tetris_insert_propio"
  on tetris.match_tetris for insert
  with check (true);

create policy "match_tetris_update_participantes"
  on tetris.match_tetris for update
  using (
    exists (
      select 1 from tetris.match_tetris_players p
      where p.match_id = match_tetris.id and p.user_id = auth.uid()
    )
  );

create policy "match_tetris_players_select_propias"
  on tetris.match_tetris_players for select
  using (
    user_id = auth.uid()
    or exists (
      select 1 from tetris.match_tetris_players p2
      where p2.match_id = match_tetris_players.match_id and p2.user_id = auth.uid()
    )
  );

create policy "match_tetris_players_insert_propio"
  on tetris.match_tetris_players for insert
  with check (user_id = auth.uid());

create policy "reportes_resultado_select_participantes"
  on tetris.reportes_resultado for select
  using (
    exists (
      select 1 from tetris.match_tetris_players p
      where p.match_id = reportes_resultado.match_id and p.user_id = auth.uid()
    )
  );

create policy "reportes_resultado_insert_participantes"
  on tetris.reportes_resultado for insert
  with check (
    exists (
      select 1 from tetris.match_tetris_players p
      where p.match_id = reportes_resultado.match_id and p.user_id = auth.uid()
    )
  );

-- 3. ELO: bloquear ejecución directa del cliente, solo vía funciones server-side.
revoke execute on function tetris.actualizar_rating_elo(uuid, uuid) from authenticated;

-- 4. Cola de matchmaking automático 1v1.
create table if not exists tetris.matchmaking_queue (
  user_id uuid primary key references auth.users(id) on delete cascade,
  gamer_tag text not null,
  match_id uuid references tetris.match_tetris(id) on delete set null,
  team_id uuid,
  created_at timestamptz not null default now()
);

alter table tetris.matchmaking_queue enable row level security;

drop policy if exists "matchmaking_queue_propia" on tetris.matchmaking_queue;
create policy "matchmaking_queue_propia"
  on tetris.matchmaking_queue for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create or replace function tetris.buscar_partida_automatica(p_gamer_tag text)
returns jsonb
language plpgsql
security definer
set search_path = tetris, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_rival tetris.matchmaking_queue;
  v_match tetris.match_tetris;
  v_team_1 uuid;
  v_team_2 uuid;
begin
  if v_user_id is null then
    raise exception 'No autenticado';
  end if;

  -- Ya está en cola o ya tiene partida asignada.
  select * into v_rival from tetris.matchmaking_queue where user_id = v_user_id;
  if found and v_rival.match_id is not null then
    select * into v_match from tetris.match_tetris where id = v_rival.match_id;
    return jsonb_build_object(
      'status', case when v_match.status = 'in_progress' then 'matched' else 'waiting' end,
      'match_id', v_match.id,
      'team_id', v_rival.team_id
    );
  end if;

  -- Buscar rival esperando (atómico, evita doble emparejamiento).
  select * into v_rival
  from tetris.matchmaking_queue
  where user_id <> v_user_id and match_id is null
  order by created_at asc
  for update skip locked
  limit 1;

  if found then
    v_team_1 := v_rival.team_id;
    v_team_2 := gen_random_uuid();

    insert into tetris.match_tetris (format, team_1_id, team_2_id, status, started_at)
    values ('1v1', v_team_1, v_team_2, 'in_progress', now())
    returning * into v_match;

    -- Jugador 1 (esperando en la cola)
    insert into tetris.match_tetris_players (match_id, team_id, user_id, gamer_tag)
    values (v_match.id, v_team_1, v_rival.user_id, v_rival.gamer_tag);

    -- Jugador 2 (recién ingresado)
    insert into tetris.match_tetris_players (match_id, team_id, user_id, gamer_tag)
    values (v_match.id, v_team_2, v_user_id, p_gamer_tag);

    update tetris.matchmaking_queue
      set match_id = v_match.id
      where user_id = v_rival.user_id;

    delete from tetris.matchmaking_queue where user_id = v_user_id;

    return jsonb_build_object('status', 'matched', 'match_id', v_match.id, 'team_id', v_team_2);
  end if;

  -- Nadie esperando: entrar a la cola.
  insert into tetris.matchmaking_queue (user_id, gamer_tag, team_id)
  values (v_user_id, p_gamer_tag, gen_random_uuid())
  on conflict (user_id) do update set gamer_tag = excluded.gamer_tag;

  return jsonb_build_object('status', 'waiting', 'match_id', null, 'team_id',
    (select team_id from tetris.matchmaking_queue where user_id = v_user_id));
end;
$$;

create or replace function tetris.mi_estado_matchmaking()
returns jsonb
language sql
security definer
set search_path = tetris, public
as $$
  select case
    when mq.match_id is not null then jsonb_build_object(
      'status', case when m.status = 'in_progress' then 'matched' else 'waiting' end,
      'match_id', mq.match_id,
      'team_id', mq.team_id
    )
    when mq.user_id is not null then jsonb_build_object('status', 'waiting', 'match_id', null, 'team_id', mq.team_id)
    else jsonb_build_object('status', 'idle', 'match_id', null, 'team_id', null)
  end
  from tetris.matchmaking_queue mq
  left join tetris.match_tetris m on m.id = mq.match_id
  where mq.user_id = auth.uid()
  union all
  select jsonb_build_object('status', 'idle', 'match_id', null, 'team_id', null)
  where not exists (select 1 from tetris.matchmaking_queue where user_id = auth.uid())
  limit 1;
$$;

create or replace function tetris.cancelar_busqueda()
returns void
language sql
security definer
set search_path = tetris, public
as $$
  delete from tetris.matchmaking_queue where user_id = auth.uid() and match_id is null;
$$;

-- 5. Penalización de abandono: 15% del ELO actual, sin piso (puede ir negativo).
create or replace function tetris.penalizar_abandono(p_match_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = tetris, public
as $$
declare
  v_rating int;
begin
  select rating into v_rating from tetris.ratings where user_id = p_user_id;
  if v_rating is null then
    return;
  end if;

  update tetris.ratings
    set rating = rating - round(rating * 0.15),
        losses = losses + 1,
        matches_played = matches_played + 1
    where user_id = p_user_id;
end;
$$;

revoke execute on function tetris.penalizar_abandono(uuid, uuid) from anon;
