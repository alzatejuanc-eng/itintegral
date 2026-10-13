-- IT Assessment Board, Transformación ExO
-- Esquema para un proyecto propio de Supabase (sin Lovable).
-- Ejecutar completo en el editor SQL de Supabase, en este orden:
--   1. supabase/schema.sql          (este archivo)
--   2. supabase/seed_publico.sql    (pilares, preguntas situacionales y biblioteca de acciones)
--   3. privado/seed_clave.sql       (clave de niveles; NO está en el repositorio, se entrega aparte)
-- Es idempotente: se puede volver a ejecutar sin perder datos.

create extension if not exists pgcrypto;

-- =====================================================================
-- 1. Catálogos
-- =====================================================================

create table if not exists public.pilares_cfg (
  n        smallint primary key check (n between 1 and 11),
  nombre   text not null,
  bloque   text not null check (bloque in ('A','B','C','D')),
  peso     numeric(5,2) not null,
  ejes     text[] not null default '{}'
);

-- Preguntas situacionales visibles. No contienen ningún dato de nivel.
create table if not exists public.preguntas (
  id        text primary key check (id ~ '^q[0-9]{3}$'),
  grupo     smallint not null references public.pilares_cfg(n),
  orden     smallint not null,
  enunciado text not null,
  opciones  jsonb not null
);

-- Clave de niveles. Solo la lee el servidor (funciones SECURITY DEFINER).
create table if not exists public.clave_privada (
  id         text primary key references public.preguntas(id) on delete cascade,
  pilar      smallint not null,
  componente text not null,
  tipo       char(1) not null check (tipo in ('D','E','I')),
  niveles    jsonb not null
);

-- Biblioteca de acciones típicas por pilar y horizonte (para el roadmap sugerido).
create table if not exists public.biblioteca_acciones (
  id         serial primary key,
  pilar      smallint not null references public.pilares_cfg(n),
  horizonte  text not null check (horizonte in ('quick_win','90_dias','12_meses')),
  accion     text not null,
  indicador  text,
  unique (pilar, horizonte, accion)
);

-- =====================================================================
-- 2. Evaluaciones, respuestas y roadmap
-- =====================================================================

create table if not exists public.evaluaciones (
  id                  uuid primary key default gen_random_uuid(),
  owner_id            uuid not null default auth.uid() references auth.users(id) on delete cascade,
  -- Quien diligencia
  evaluador_nombre    text not null,
  evaluador_cargo     text,
  evaluador_correo    text,
  evaluador_telefono  text,
  -- Empresa evaluada
  empresa             text not null,
  empresa_id_fiscal   text,
  sector              text,
  pais                text,
  tamano              text,
  -- Contexto previo C1 a C11
  decision            text,
  patrocinador        text,
  periodo_meses       smallint check (periodo_meses is null or periodo_meses in (12,24)),
  alcance             text,
  contexto            jsonb not null default '{}'::jsonb,
  regulada            boolean not null default false,
  escala_ia           boolean not null default false,
  -- Pesos, objetivos y riesgos por pilar
  pesos               jsonb not null default '{"1":10,"2":14,"3":10,"4":10,"5":9,"6":8,"7":9,"8":8,"9":6,"10":8,"11":8}'::jsonb,
  objetivos           jsonb not null default '{"1":3,"2":3,"3":3,"4":3,"5":3,"6":3,"7":3,"8":3,"9":3,"10":3,"11":3}'::jsonb,
  riesgos_pilar       jsonb not null default '{"1":1,"2":1,"3":1,"4":1,"5":1,"6":1,"7":1,"8":1,"9":1,"10":1,"11":1}'::jsonb,
  justificacion_pesos text,
  pesos_bloqueados    boolean not null default false,
  ajustes_log         jsonb not null default '[]'::jsonb,
  -- Estado y resultados
  estado              text not null default 'borrador' check (estado in ('borrador','en_curso','provisional','definitiva')),
  version_marco       text not null default '1.0',
  resultados          jsonb,
  calculado_at        timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index if not exists evaluaciones_owner_idx on public.evaluaciones(owner_id);

create table if not exists public.respuestas (
  id               uuid primary key default gen_random_uuid(),
  evaluacion_id    uuid not null references public.evaluaciones(id) on delete cascade,
  pregunta_id      text not null references public.preguntas(id),
  opcion_id        text check (opcion_id is null or opcion_id in ('a','b','c','d','e')),
  ne               boolean not null default false,
  evidencia_tipo   text check (evidencia_tipo is null or evidencia_tipo in ('verbal','documento','datos','mejora')),
  fuentes          smallint not null default 1 check (fuentes in (1,2)),
  fuente_texto     text,
  fecha_evidencia  date,
  comentario       text,
  updated_at       timestamptz not null default now(),
  unique (evaluacion_id, pregunta_id),
  -- NE limpia la opción; una opción exige no estar en NE
  check (not (ne and opcion_id is not null))
);
create index if not exists respuestas_eval_idx on public.respuestas(evaluacion_id);

create table if not exists public.acciones_roadmap (
  id                 uuid primary key default gen_random_uuid(),
  evaluacion_id      uuid not null references public.evaluaciones(id) on delete cascade,
  pilar              smallint references public.pilares_cfg(n),
  brecha             text,
  causa_raiz         text,
  accion             text not null,
  dueno              text,
  costo_estimado     numeric(14,2),
  fecha              date,
  horizonte          text not null default '90_dias' check (horizonte in ('quick_win','90_dias','12_meses')),
  indicador          text,
  indicador_actual   text,
  indicador_meta     text,
  indicador_fuente   text,
  nivel_esperado     numeric(3,1),
  dependencias       text,
  riesgo_si_no       text,
  prioridad          numeric(8,2),
  estado             text not null default 'en_brechas' check (estado in ('en_brechas','en_plan','en_curso','cerrada')),
  origen             text not null default 'manual' check (origen in ('manual','sugerida')),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index if not exists acciones_eval_idx on public.acciones_roadmap(evaluacion_id);

-- =====================================================================
-- 3. Reglas en el servidor (disparadores)
-- =====================================================================

create or replace function public._touch() returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;

drop trigger if exists trg_touch_eval on public.evaluaciones;
create trigger trg_touch_eval before update on public.evaluaciones for each row execute function public._touch();
drop trigger if exists trg_touch_resp on public.respuestas;
create trigger trg_touch_resp before update on public.respuestas for each row execute function public._touch();
drop trigger if exists trg_touch_acc on public.acciones_roadmap;
create trigger trg_touch_acc before update on public.acciones_roadmap for each row execute function public._touch();

-- Validación de evaluaciones: pesos suman 100, justificación si cambian, bloqueo, campos protegidos.
create or replace function public._validar_evaluacion() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_suma numeric;
  v_cambia boolean;
begin
  -- El navegador nunca escribe resultados ni la bitácora de ajustes directamente.
  if current_setting('app.servidor', true) is distinct from 'si' then
    if tg_op = 'INSERT' then
      new.resultados := null; new.calculado_at := null;
      new.ajustes_log := '[]'::jsonb; new.pesos_bloqueados := false;
      new.owner_id := auth.uid();
    else
      new.resultados := old.resultados; new.calculado_at := old.calculado_at;
      new.ajustes_log := old.ajustes_log; new.owner_id := old.owner_id;
      if old.pesos_bloqueados and not new.pesos_bloqueados then
        raise exception 'Para reabrir los pesos use la función reabrir_pesos con un motivo.';
      end if;
      if old.pesos_bloqueados and (new.pesos is distinct from old.pesos or new.objetivos is distinct from old.objetivos) then
        raise exception 'Los pesos y objetivos están bloqueados porque ya hay respuestas. Reábralos indicando un motivo.';
      end if;
      if new.estado in ('provisional','definitiva') and new.estado is distinct from old.estado then
        new.estado := old.estado;
      end if;
    end if;
  end if;

  select sum((value)::numeric) into v_suma from jsonb_each_text(new.pesos);
  if v_suma is null or abs(v_suma - 100) > 0.001 then
    raise exception 'Los pesos deben sumar 100 (suman %).', coalesce(v_suma, 0);
  end if;
  if (select count(*) from jsonb_object_keys(new.pesos)) <> 11 then
    raise exception 'Debe haber un peso para cada uno de los 11 pilares.';
  end if;
  select exists (
    select 1 from public.pilares_cfg p
    where (new.pesos->>p.n::text)::numeric is distinct from p.peso
  ) into v_cambia;
  if v_cambia and coalesce(btrim(new.justificacion_pesos), '') = '' then
    raise exception 'Si cambia algún peso base, la justificación escrita es obligatoria.';
  end if;
  return new;
end $$;

drop trigger if exists trg_validar_eval on public.evaluaciones;
create trigger trg_validar_eval before insert or update on public.evaluaciones
  for each row execute function public._validar_evaluacion();

-- Bloqueo de pesos con la primera respuesta (y tras una reapertura, con la siguiente).
create or replace function public._bloquear_pesos() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform set_config('app.servidor', 'si', true);
  update public.evaluaciones
     set pesos_bloqueados = true,
         estado = case when estado = 'borrador' then 'en_curso' else estado end
   where id = new.evaluacion_id and (pesos_bloqueados = false or estado = 'borrador');
  perform set_config('app.servidor', '', true);
  return new;
end $$;

drop trigger if exists trg_bloquear_pesos on public.respuestas;
create trigger trg_bloquear_pesos after insert or update on public.respuestas
  for each row execute function public._bloquear_pesos();

-- Respuestas: NE limpia la opción; descripción de fuente obligatoria con evidencia fuerte.
create or replace function public._validar_respuesta() returns trigger language plpgsql as $$
begin
  if new.ne then new.opcion_id := null; end if;
  if new.evidencia_tipo in ('documento','datos','mejora') and coalesce(btrim(new.fuente_texto), '') = '' then
    raise exception 'Describa la fuente cuando el respaldo es documento, datos o mejora.';
  end if;
  return new;
end $$;

drop trigger if exists trg_validar_resp on public.respuestas;
create trigger trg_validar_resp before insert or update on public.respuestas
  for each row execute function public._validar_respuesta();

-- Regla del plan: sin dueño, costo y fecha la acción queda en el registro de brechas.
create or replace function public._regla_plan() returns trigger language plpgsql as $$
begin
  if new.estado <> 'en_brechas'
     and (coalesce(btrim(new.dueno), '') = '' or new.costo_estimado is null or new.fecha is null) then
    new.estado := 'en_brechas';
  end if;
  return new;
end $$;

drop trigger if exists trg_regla_plan on public.acciones_roadmap;
create trigger trg_regla_plan before insert or update on public.acciones_roadmap
  for each row execute function public._regla_plan();

-- =====================================================================
-- 4. Seguridad: RLS y permisos
-- =====================================================================

alter table public.pilares_cfg         enable row level security;
alter table public.preguntas           enable row level security;
alter table public.clave_privada       enable row level security;
alter table public.biblioteca_acciones enable row level security;
alter table public.evaluaciones        enable row level security;
alter table public.respuestas          enable row level security;
alter table public.acciones_roadmap    enable row level security;

revoke all on public.clave_privada from anon, authenticated, public;
revoke all on public.pilares_cfg, public.preguntas, public.biblioteca_acciones,
              public.evaluaciones, public.respuestas, public.acciones_roadmap from anon;

grant select on public.pilares_cfg, public.preguntas, public.biblioteca_acciones to authenticated;
grant select, insert, update, delete on public.evaluaciones, public.respuestas, public.acciones_roadmap to authenticated;

drop policy if exists pilares_lectura on public.pilares_cfg;
create policy pilares_lectura on public.pilares_cfg for select to authenticated using (true);
drop policy if exists preguntas_lectura on public.preguntas;
create policy preguntas_lectura on public.preguntas for select to authenticated using (true);
drop policy if exists biblioteca_lectura on public.biblioteca_acciones;
create policy biblioteca_lectura on public.biblioteca_acciones for select to authenticated using (true);
-- clave_privada: RLS activo y CERO políticas a propósito.

drop policy if exists eval_dueno on public.evaluaciones;
create policy eval_dueno on public.evaluaciones for all to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

drop policy if exists resp_dueno on public.respuestas;
create policy resp_dueno on public.respuestas for all to authenticated
  using (exists (select 1 from public.evaluaciones e where e.id = evaluacion_id and e.owner_id = auth.uid()))
  with check (exists (select 1 from public.evaluaciones e where e.id = evaluacion_id and e.owner_id = auth.uid()));

drop policy if exists acc_dueno on public.acciones_roadmap;
create policy acc_dueno on public.acciones_roadmap for all to authenticated
  using (exists (select 1 from public.evaluaciones e where e.id = evaluacion_id and e.owner_id = auth.uid()))
  with check (exists (select 1 from public.evaluaciones e where e.id = evaluacion_id and e.owner_id = auth.uid()));

-- =====================================================================
-- 5. Funciones que llama la página (RPC)
-- =====================================================================

-- Reabrir pesos exige un motivo que queda en la bitácora con fecha.
create or replace function public.reabrir_pesos(p_id uuid, p_motivo text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(btrim(p_motivo), '') = '' then
    raise exception 'El motivo de la reapertura es obligatorio.';
  end if;
  if not exists (select 1 from evaluaciones where id = p_id and owner_id = auth.uid()) then
    raise exception 'Evaluación no encontrada.';
  end if;
  perform set_config('app.servidor', 'si', true);
  update evaluaciones
     set pesos_bloqueados = false,
         ajustes_log = ajustes_log || jsonb_build_array(jsonb_build_object(
           'fecha', now(), 'usuario', auth.uid(), 'motivo', btrim(p_motivo)))
   where id = p_id;
  perform set_config('app.servidor', '', true);
end $$;

-- Vista agregada (ejes y bloques). Interna.
create or replace function public._vista(p_ns int[], p_peso numeric[], p_nota numeric[], p_ne boolean[])
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'pilares', to_jsonb(p_ns),
    'nota', case when sum(p_peso[n]) filter (where not p_ne[n]) > 0
                 then round(sum(p_peso[n] * p_nota[n]) filter (where not p_ne[n])
                            / sum(p_peso[n]) filter (where not p_ne[n]), 2) end,
    'evaluados', count(*) filter (where not p_ne[n]))
  from unnest(p_ns) as n
$$;

-- Cálculo completo. Lee la clave en el servidor y devuelve SOLO agregados.
-- Reglas: sección 8 del traspaso (techos por evidencia, NE, nota del pilar,
-- global, cobertura, provisional, rating, veto, alerta IA, ejes, bloques,
-- compuertas y prioridades).
create or replace function public.calcular_evaluacion(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  ev        evaluaciones;
  pc        record;
  agg       jsonb;
  comp      jsonb;
  a         jsonb;
  v_n       int;
  peso      numeric[] := array_fill(0::numeric, array[11]);
  prac      numeric[] := array_fill(null::numeric, array[11]);
  res       numeric[] := array_fill(null::numeric, array[11]);
  nota      numeric[] := array_fill(null::numeric, array[11]);
  ne        boolean[] := array_fill(true, array[11]);
  veto      boolean[] := array_fill(false, array[11]);
  alerta    boolean[] := array_fill(false, array[11]);
  conf      text[]    := array_fill(null::text, array[11]);
  nombre    text[]    := array_fill(null::text, array[11]);
  bloque    text[]    := array_fill(null::text, array[11]);
  resp      int[]     := array_fill(0, array[11]);
  total     int[]     := array_fill(0, array[11]);
  techos    int[]     := array_fill(0, array[11]);
  cf        numeric;
  peso_total numeric := 0; peso_eval numeric := 0; peso_cob numeric := 0; peso_nb numeric := 0;
  suma      numeric := 0;
  g_nota    numeric;
  letra     text; rnombre text; veredicto text;
  provisional boolean;
  veto_p    int[] := '{}';
  datos_comp numeric;
  disparada boolean; ia_p int[] := '{}'; ia_nd int[] := '{}';
  pilares_j jsonb := '[]'::jsonb;
  prior_j   jsonb;
  resultado jsonb;
  pe        numeric;
begin
  select * into ev from evaluaciones where id = p_id;
  if not found or ev.owner_id is distinct from auth.uid() then
    raise exception 'Evaluación no encontrada.';
  end if;

  -- Niveles finales por respuesta (nunca salen de esta función)
  with r as (
    select c.pilar, c.componente, c.tipo,
           (c.niveles ->> re.opcion_id)::int as nop,
           coalesce(re.evidencia_tipo, 'verbal') as evt,
           coalesce(re.fuentes, 1) as fu
      from clave_privada c
      join respuestas re on re.pregunta_id = c.id and re.evaluacion_id = p_id
     where not re.ne and re.opcion_id is not null
  ), f as (
    select *,
           case evt when 'documento' then 3 when 'datos' then 4 when 'mejora' then 5 else 2 end as techo
      from r where nop is not null
  ), g as (
    select pilar, componente, tipo,
           case when evt = 'mejora' and nop = 4 then 5 else least(nop, techo) end as nivel,
           (not (evt = 'mejora' and nop = 4) and nop > techo) as recortado,
           case when evt in ('documento','datos','mejora') then (case when fu >= 2 then 3 else 2 end)
                else (case when fu >= 2 then 2 else 1 end) end as cnf
      from f
  )
  select
    (select jsonb_object_agg(pilar, jsonb_build_object(
        'resp', n, 'techos', t, 'pr', pr, 'rs', rs, 'cf', cfv))
       from (select pilar, count(*) n, count(*) filter (where recortado) t,
                    avg(nivel) filter (where tipo <> 'D') pr,
                    avg(nivel) filter (where tipo = 'D') rs,
                    avg(cnf) cfv
               from g group by pilar) x),
    (select jsonb_object_agg(componente, jsonb_build_object('nivel', round(av, 2), 'respondidas', n))
       from (select componente, avg(nivel) av, count(*) n from g group by componente) y
      where n >= 2),
    (select round(avg(nivel), 2) from g where componente = 'P8.3')
  into agg, comp, datos_comp;

  agg  := coalesce(agg, '{}'::jsonb);
  comp := coalesce(comp, '{}'::jsonb);

  for pc in select p.n, p.nombre, p.bloque, p.peso,
                   (select count(*) from clave_privada k where k.pilar = p.n) as tot
              from pilares_cfg p order by p.n loop
    v_n := pc.n;
    nombre[v_n] := pc.nombre;
    bloque[v_n] := pc.bloque;
    peso[v_n]   := coalesce((ev.pesos ->> v_n::text)::numeric, pc.peso);
    total[v_n]  := pc.tot;
    a := agg -> v_n::text;
    if a is not null then
      resp[v_n]   := (a->>'resp')::int;
      techos[v_n] := (a->>'techos')::int;
      prac[v_n]   := round((a->>'pr')::numeric, 2);
      res[v_n]    := round((a->>'rs')::numeric, 2);
      cf          := (a->>'cf')::numeric;
      conf[v_n]   := case when cf >= 2.5 then 'alta' when cf >= 1.75 then 'media' else 'baja' end;
    end if;
    ne[v_n] := total[v_n] = 0 or resp[v_n]::numeric / nullif(total[v_n], 0) < 0.5
               or prac[v_n] is null or res[v_n] is null;
    if not ne[v_n] then
      nota[v_n] := round(0.4 * prac[v_n] + 0.6 * res[v_n], 2);
    end if;
    alerta[v_n] := prac[v_n] is not null and res[v_n] is not null and res[v_n] <= prac[v_n] - 2;
    if v_n in (6,7) and not ne[v_n] and prac[v_n] <= 1 then
      veto[v_n] := true; veto_p := veto_p || v_n;
    end if;

    peso_total := peso_total + peso[v_n];
    if not ne[v_n] then
      peso_eval := peso_eval + peso[v_n];
      suma := suma + peso[v_n] * nota[v_n];
      if conf[v_n] in ('alta','media') then peso_cob := peso_cob + peso[v_n]; end if;
    end if;
    if ne[v_n] or conf[v_n] = 'baja' then peso_nb := peso_nb + peso[v_n]; end if;

    pilares_j := pilares_j || jsonb_build_array(jsonb_build_object(
      'n', v_n, 'nombre', nombre[v_n], 'bloque', bloque[v_n], 'peso', peso[v_n],
      'practica', prac[v_n], 'resultado', res[v_n], 'nota', nota[v_n], 'ne', ne[v_n],
      'confianza', conf[v_n], 'alerta_actividad', alerta[v_n], 'veto', veto[v_n],
      'respondidas', resp[v_n], 'total', total[v_n]));
  end loop;

  -- Global, rating y estado
  if peso_eval > 0 then g_nota := round(suma / peso_eval, 1); end if;
  if g_nota is not null then
    letra := case when g_nota >= 4.5 then 'A' when g_nota >= 3.5 then 'B'
                  when g_nota >= 2.5 then 'C' when g_nota >= 1.5 then 'D' else 'E' end;
    if coalesce(array_length(veto_p, 1), 0) > 0 and letra in ('A','B','C') then letra := 'D'; end if;
    rnombre := case letra when 'A' then 'Líder' when 'B' then 'Sólido' when 'C' then 'Funcional'
                          when 'D' then 'Frágil' else 'Crítico' end;
    veredicto := case letra
      when 'A' then 'Líder. La función de TI es un activo estratégico demostrado.'
      when 'B' then 'Sólido. Funciona bien con brechas puntuales.'
      when 'C' then 'Funcional. Cumple lo básico, pero limita al negocio en áreas relevantes.'
      when 'D' then 'Frágil. Hay riesgos de operación, de valor o de protección que requieren acción prioritaria.'
      else 'Crítico. La función no sostiene al negocio de forma confiable.' end;
  end if;
  provisional := g_nota is null or peso_nb > peso_total / 3;

  -- Alerta de escalamiento de IA
  disparada := ev.escala_ia or (prac[11] is not null and prac[11] >= 3);
  if disparada then
    foreach v_n in array array[1,7,8] loop
      if ne[v_n] then ia_nd := ia_nd || v_n;
      elsif prac[v_n] < 2 then ia_p := ia_p || v_n; end if;
    end loop;
  end if;

  -- Prioridades = brecha x peso x riesgo
  select jsonb_agg(x order by (x->>'prioridad')::numeric desc nulls last, (x->>'n')::int)
    into prior_j
    from (
      select jsonb_build_object(
        'n', n, 'nombre', nombre[n], 'objetivo', obj, 'nota', nota[n], 'brecha', br,
        'peso', peso[n], 'riesgo', rg, 'prioridad', round(br * peso[n] * rg, 2),
        'exige_causa_raiz', alerta[n], 'ne', ne[n]) as x
      from (
        select n,
               coalesce((ev.objetivos ->> n::text)::numeric, 3) as obj,
               case when veto[n] then 3 else coalesce((ev.riesgos_pilar ->> n::text)::numeric, 1) end as rg,
               case when nota[n] is null then null
                    else round(greatest(0, coalesce((ev.objetivos ->> n::text)::numeric, 3) - nota[n]), 2) end as br
          from generate_series(1, 11) as n
      ) s
    ) t;

  resultado := jsonb_build_object(
    'pilares', pilares_j,
    'global', jsonb_build_object(
      'nota', g_nota, 'rating_calculado', letra, 'rating_nombre', rnombre,
      'rating_definitivo', case when provisional or letra is null then null else letra end,
      'veredicto', veredicto, 'provisional', provisional,
      'cobertura', case when peso_total > 0 then round(peso_cob / peso_total * 100, 1) else 0 end,
      'peso_ne_o_baja', peso_nb, 'peso_total', peso_total),
    'ejes', jsonb_build_object(
      'Productividad',       _vista(array[4,5,10],   peso, nota, ne),
      'Eficiencia',          _vista(array[3,5,9],    peso, nota, ne),
      'Apoyo al negocio',    _vista(array[1,2,10,11], peso, nota, ne),
      'Resiliencia',         _vista(array[6,7],      peso, nota, ne),
      'Innovación y futuro', _vista(array[8,11],     peso, nota, ne)),
    'bloques', jsonb_build_object(
      'A', _vista(array[1,2,3],     peso, nota, ne),
      'B', _vista(array[4,5],       peso, nota, ne),
      'C', _vista(array[6,7],       peso, nota, ne),
      'D', _vista(array[8,9,10,11], peso, nota, ne)),
    'veto', jsonb_build_object('activo', coalesce(array_length(veto_p, 1), 0) > 0, 'pilares', to_jsonb(veto_p)),
    'alerta_ia', jsonb_build_object('disparada', disparada,
      'riesgo_mayor', coalesce(array_length(ia_p, 1), 0) > 0,
      'pilares', to_jsonb(ia_p), 'no_descartable', to_jsonb(ia_nd)),
    'compuertas', jsonb_build_array(
      jsonb_build_object('id','C1','nombre','Protección',
        'estado', public._compuerta(array[case when ne[6] then null else prac[6] end, case when ne[7] then null else prac[7] end]),
        'frena','Ampliar superficie tecnológica (nuevas nubes, proveedores críticos, agentes de IA con acceso a sistemas).'),
      jsonb_build_object('id','C2','nombre','Gobierno y datos',
        'estado', public._compuerta(array[case when ne[1] then null else prac[1] end, datos_comp]),
        'frena','Escalar IA a más procesos o áreas.'),
      jsonb_build_object('id','C3','nombre','Valor',
        'estado', public._compuerta(array[case when ne[2] then null else prac[2] end]),
        'frena','Aprobar nuevos proyectos grandes sin caso de negocio ni dueño del beneficio.'),
      jsonb_build_object('id','C4','nombre','Adopción',
        'estado', public._compuerta(array[case when ne[10] then null else prac[10] end]),
        'frena','Nuevas implementaciones masivas de sistemas o herramientas de IA.')),
    'prioridades', prior_j,
    'componentes', comp,
    'techos_aplicados', (select jsonb_object_agg(n, techos[n]) from generate_series(1,11) n),
    'ne_por_pilar', (select jsonb_object_agg(n, total[n] - resp[n]) from generate_series(1,11) n),
    'respondidas_por_pilar', (select jsonb_object_agg(n, resp[n]) from generate_series(1,11) n)
  );

  perform set_config('app.servidor', 'si', true);
  update evaluaciones
     set resultados = resultado,
         calculado_at = now(),
         estado = case when g_nota is null then estado
                       when provisional then 'provisional' else 'definitiva' end
   where id = p_id;
  perform set_config('app.servidor', '', true);
  return resultado;
end $$;

create or replace function public._compuerta(p_vals numeric[]) returns text language sql immutable as $$
  select case when exists (select 1 from unnest(p_vals) v where v is null) then 'sin_evidencia'
              when not exists (select 1 from unnest(p_vals) v where v < 2) then 'cumple'
              else 'no_cumple' end
$$;

-- Roadmap sugerido a partir de las prioridades calculadas y la biblioteca de acciones.
-- Reemplaza solo las acciones sugeridas que siguen en el registro de brechas sin dueño.
create or replace function public.sugerir_roadmap(p_id uuid) returns int
language plpgsql security definer set search_path = public as $$
declare
  ev  evaluaciones;
  p   jsonb;
  b   record;
  k   int := 0;
  hz  text;
  pil int;
begin
  select * into ev from evaluaciones where id = p_id;
  if not found or ev.owner_id is distinct from auth.uid() then
    raise exception 'Evaluación no encontrada.';
  end if;
  if ev.resultados is null then
    raise exception 'Calcule los resultados antes de sugerir el roadmap.';
  end if;

  delete from acciones_roadmap
   where evaluacion_id = p_id and origen = 'sugerida' and estado = 'en_brechas'
     and coalesce(btrim(dueno), '') = '' and costo_estimado is null and fecha is null;

  for p in select * from jsonb_array_elements(ev.resultados -> 'prioridades') loop
    pil := (p->>'n')::int;
    if (p->>'ne')::boolean then
      insert into acciones_roadmap(evaluacion_id, pilar, brecha, accion, horizonte, prioridad, origen, riesgo_si_no)
      values (p_id, pil, 'Pilar no evaluable por falta de evidencia',
              'Levantar la evidencia faltante del pilar ' || (p->>'nombre') || ' y completar las respuestas pendientes.',
              'quick_win', null, 'sugerida',
              'El rating sigue provisional y el pilar no entra en la nota global.');
      k := k + 1;
      continue;
    end if;
    if coalesce((p->>'prioridad')::numeric, 0) <= 0 then continue; end if;

    if (p->>'exige_causa_raiz')::boolean then
      insert into acciones_roadmap(evaluacion_id, pilar, brecha, accion, horizonte, prioridad, origen, riesgo_si_no)
      values (p_id, pil, 'Actividad sin resultado: la práctica supera al resultado en 2 o más puntos',
              'Analizar la causa raíz de por qué la práctica declarada no se traduce en resultados medibles en ' || (p->>'nombre') || '.',
              'quick_win', (p->>'prioridad')::numeric, 'sugerida',
              'Se invierte en actividades que no mueven el resultado.');
      k := k + 1;
    end if;

    for b in select * from biblioteca_acciones where pilar = pil order by
               case horizonte when 'quick_win' then 1 when '90_dias' then 2 else 3 end, id loop
      hz := b.horizonte;
      -- Un veto activo empuja las acciones de 12 meses a 90 días.
      if (ev.resultados -> 'veto' -> 'pilares') @> to_jsonb(pil) and hz = '12_meses' then hz := '90_dias'; end if;
      insert into acciones_roadmap(evaluacion_id, pilar, brecha, accion, horizonte, indicador,
                                   nivel_esperado, prioridad, origen, riesgo_si_no)
      values (p_id, pil,
              'Nota ' || replace(p->>'nota', '.', ',') || ' frente a objetivo ' || (p->>'objetivo') || ' (brecha ' || replace(p->>'brecha', '.', ',') || ')',
              b.accion, hz, b.indicador, least(5, (p->>'objetivo')::numeric),
              (p->>'prioridad')::numeric, 'sugerida',
              case when (p->>'riesgo')::int >= 3 then 'Riesgo alto de continuidad, seguridad o cumplimiento.'
                   when (p->>'riesgo')::int = 2 then 'Riesgo medio para el negocio.'
                   else 'La brecha se mantiene y limita al negocio.' end)
      on conflict do nothing;
      k := k + 1;
    end loop;
  end loop;
  return k;
end $$;

revoke execute on function public.calcular_evaluacion(uuid), public.sugerir_roadmap(uuid),
                           public.reabrir_pesos(uuid, text) from public, anon;
grant execute on function public.calcular_evaluacion(uuid), public.sugerir_roadmap(uuid),
                          public.reabrir_pesos(uuid, text) to authenticated;
revoke execute on function public._validar_evaluacion(), public._bloquear_pesos() from public, anon, authenticated;
revoke execute on function public._vista(int[], numeric[], numeric[], boolean[]), public._compuerta(numeric[]) from public, anon;
grant execute on function public._vista(int[], numeric[], numeric[], boolean[]), public._compuerta(numeric[]) to authenticated;
