-- Fase 1: Desafíos directos entre amigos ("Desafiar" en el bloque Amigos).
-- El destinatario tiene 20 segundos para aceptar; si no responde, expira solo.

create table if not exists tetris.desafios (
  id uuid primary key default gen_random_uuid(),
  retador_id uuid not null references auth.users(id) on delete cascade,
  retado_id uuid not null references auth.users(id) on delete cascade,
  match_id uuid references tetris.match_tetris(id) on delete cascade,
  estado text not null default 'pendiente'
    check (estado in ('pendiente', 'aceptado', 'rechazado', 'expirado')),
  created_at timestamptz not null default now(),
  expira_at timestamptz not null default (now() + interval '20 seconds')
);

alter table tetris.desafios enable row level security;

drop policy if exists "desafios_select_participantes" on tetris.desafios;
create policy "desafios_select_participantes"
  on tetris.desafios for select
  using (auth.uid() = retador_id or auth.uid() = retado_id);

drop policy if exists "desafios_insert_retador" on tetris.desafios;
create policy "desafios_insert_retador"
  on tetris.desafios for insert
  with check (auth.uid() = retador_id);

drop policy if exists "desafios_update_retado" on tetris.desafios;
create policy "desafios_update_retado"
  on tetris.desafios for update
  using (auth.uid() = retado_id);

-- Crea el desafío + la sala 1v1 (pending) donde se va a jugar si se acepta.
create or replace function tetris.crear_desafio(p_retado_id uuid, p_gamer_tag text)
returns jsonb
language plpgsql
security definer
set search_path = tetris, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_match tetris.match_tetris;
  v_desafio tetris.desafios;
begin
  if v_user_id is null then
    raise exception 'No autenticado';
  end if;
  if v_user_id = p_retado_id then
    raise exception 'No podés desafiarte a vos mismo';
  end if;

  insert into tetris.match_tetris (format, team_1_id, team_2_id, status)
  values ('1v1', gen_random_uuid(), gen_random_uuid(), 'pending')
  returning * into v_match;

  insert into tetris.match_tetris_players (match_id, team_id, user_id, gamer_tag)
  values (v_match.id, v_match.team_1_id, v_user_id, p_gamer_tag);

  insert into tetris.desafios (retador_id, retado_id, match_id)
  values (v_user_id, p_retado_id, v_match.id)
  returning * into v_desafio;

  return jsonb_build_object(
    'desafio_id', v_desafio.id,
    'match_id', v_match.id,
    'team_id', v_match.team_1_id,
    'expira_at', v_desafio.expira_at
  );
end;
$$;

-- El retado acepta (se une a la sala como team_2) o rechaza. Expira sola si
-- ya pasaron los 20 segundos (mi_desafios_pendientes() la filtra).
create or replace function tetris.responder_desafio(p_desafio_id uuid, p_aceptar boolean, p_gamer_tag text default null)
returns jsonb
language plpgsql
security definer
set search_path = tetris, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_desafio tetris.desafios;
  v_match tetris.match_tetris;
begin
  select * into v_desafio from tetris.desafios where id = p_desafio_id and retado_id = v_user_id;
  if not found then
    raise exception 'Desafío no encontrado';
  end if;
  if v_desafio.estado <> 'pendiente' or now() > v_desafio.expira_at then
    update tetris.desafios set estado = 'expirado' where id = p_desafio_id and estado = 'pendiente';
    raise exception 'El desafío ya expiró';
  end if;

  if not p_aceptar then
    update tetris.desafios set estado = 'rechazado' where id = p_desafio_id;
    return jsonb_build_object('status', 'rechazado');
  end if;

  select * into v_match from tetris.match_tetris where id = v_desafio.match_id;

  insert into tetris.match_tetris_players (match_id, team_id, user_id, gamer_tag)
  values (v_match.id, v_match.team_2_id, v_user_id, coalesce(p_gamer_tag, 'Gamer'));

  update tetris.match_tetris set status = 'in_progress', started_at = now() where id = v_match.id;
  update tetris.desafios set estado = 'aceptado' where id = p_desafio_id;

  return jsonb_build_object('status', 'aceptado', 'match_id', v_match.id, 'team_id', v_match.team_2_id);
end;
$$;

-- Desafíos pendientes donde el usuario logueado es el retador o el retado,
-- ya excluyendo los vencidos (el cliente igual valida expira_at para la
-- barra de tiempo).
create or replace function tetris.mis_desafios()
returns jsonb
language plpgsql
security definer
set search_path = tetris, public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  update tetris.desafios
    set estado = 'expirado'
    where estado = 'pendiente' and now() > expira_at
      and (retador_id = v_user_id or retado_id = v_user_id);

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', d.id,
      'retador_id', d.retador_id,
      'retado_id', d.retado_id,
      'match_id', d.match_id,
      'estado', d.estado,
      'expira_at', d.expira_at,
      'soy_retador', d.retador_id = v_user_id
    ))
    from tetris.desafios d
    where (d.retador_id = v_user_id or d.retado_id = v_user_id)
      and d.estado = 'pendiente'
  ), '[]'::jsonb);
end;
$$;
