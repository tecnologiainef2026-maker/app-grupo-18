-- =====================================================================
-- 002_seguridad.sql · Grupo 18 · NEXØ
-- Activa la seguridad a nivel de fila (RLS) en todas las tablas y crea
-- las políticas iniciales.
--
-- Idea general:
--   · Sin sesión iniciada (rol anon) no se puede leer ni escribir nada.
--   · Un ENTRENADOR (su usuario está en entrenadores.usuario_id) ve y
--     gestiona los datos de todos los deportistas del grupo.
--   · Un DEPORTISTA (su usuario está en deportistas.usuario_id) solo ve
--     sus propios datos, registra lo que ha hecho y puede crear sus
--     propias sesiones y tests.
--
-- Se ejecuta después de 001_tablas.sql. Todavía NO se ha ejecutado.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. Funciones de ayuda
-- Van en un esquema "privado" que la API de Supabase no publica.
-- Son "security definer": consultan las tablas saltándose RLS para que
-- las políticas no se llamen a sí mismas en bucle.
-- ---------------------------------------------------------------------
create schema if not exists privado;
grant usage on schema privado to authenticated;

-- ¿El usuario conectado es entrenador?
create or replace function privado.es_entrenador()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.entrenadores
    where usuario_id = (select auth.uid())
  );
$$;

-- DNI del deportista conectado (null si no es deportista).
create or replace function privado.mi_dni_deportista()
returns text
language sql stable security definer set search_path = ''
as $$
  select dni from public.deportistas
  where usuario_id = (select auth.uid());
$$;

-- ¿Puede el usuario VER esta sesión? (entrenador, o el deportista que la realiza)
create or replace function privado.puede_ver_sesion(p_id_sesion bigint)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select privado.es_entrenador() or exists (
    select 1 from public.sesiones s
    where s.id = p_id_sesion
      and s.dni_deportista = privado.mi_dni_deportista()
  );
$$;

-- ¿Puede el usuario CAMBIAR el plan de esta sesión (sus tareas)?
-- El entrenador siempre; el deportista solo si la sesión la creó él.
create or replace function privado.puede_editar_sesion(p_id_sesion bigint)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select privado.es_entrenador() or exists (
    select 1 from public.sesiones s
    where s.id = p_id_sesion
      and s.dni_deportista = privado.mi_dni_deportista()
      and s.creada_por = 'deportista'
  );
$$;

-- ¿Puede el usuario REGISTRAR lo realizado en esta sesión?
-- El deportista que la realiza, o un entrenador que lo hace por él.
create or replace function privado.puede_registrar_sesion(p_id_sesion bigint)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select privado.puede_ver_sesion(p_id_sesion);
$$;

-- Sesión a la que pertenece una tarea.
create or replace function privado.sesion_de_tarea(p_id_tarea bigint)
returns bigint
language sql stable security definer set search_path = ''
as $$
  select id_sesion from public.tareas where id = p_id_tarea;
$$;

revoke all on all functions in schema privado from public;
grant execute on all functions in schema privado to authenticated;

-- ---------------------------------------------------------------------
-- 2. Activar RLS en todas las tablas
-- Con RLS activado y sin políticas, nadie puede hacer nada: cada política
-- de abajo abre solo lo que hace falta.
-- ---------------------------------------------------------------------
alter table public.entrenadores        enable row level security;
alter table public.deportistas         enable row level security;
alter table public.tests               enable row level security;
alter table public.sesiones            enable row level security;
alter table public.tareas              enable row level security;
alter table public.partes_tarea        enable row level security;
alter table public.sesiones_realizadas enable row level security;
alter table public.tareas_realizadas   enable row level security;
alter table public.trazas              enable row level security;

-- ---------------------------------------------------------------------
-- 3. ENTRENADORES
-- ---------------------------------------------------------------------
-- Cualquier usuario con sesión ve la lista (el deportista ve el nombre de su entrenador).
create policy "entrenadores: ver con sesion iniciada"
  on public.entrenadores for select to authenticated
  using (true);

-- Solo un entrenador puede dar de alta a otro entrenador. Si cualquiera pudiera
-- darse de alta, cualquier usuario vería los datos de todos los deportistas.
-- El PRIMER entrenador se crea desde el panel de Supabase (Table Editor).
create policy "entrenadores: alta por otro entrenador"
  on public.entrenadores for insert to authenticated
  with check (privado.es_entrenador());

-- Cada entrenador edita solo su ficha.
create policy "entrenadores: editar la propia"
  on public.entrenadores for update to authenticated
  using (usuario_id = (select auth.uid()))
  with check (usuario_id = (select auth.uid()));
-- Sin política de DELETE: los entrenadores se borran desde el panel de Supabase.

-- ---------------------------------------------------------------------
-- 4. DEPORTISTAS
-- ---------------------------------------------------------------------
create policy "deportistas: ver entrenador o el propio"
  on public.deportistas for select to authenticated
  using (privado.es_entrenador() or usuario_id = (select auth.uid()));

-- El entrenador da de alta a cualquier deportista; un deportista solo su propia ficha.
create policy "deportistas: alta"
  on public.deportistas for insert to authenticated
  with check (privado.es_entrenador() or usuario_id = (select auth.uid()));

create policy "deportistas: editar entrenador o el propio"
  on public.deportistas for update to authenticated
  using (privado.es_entrenador() or usuario_id = (select auth.uid()))
  with check (privado.es_entrenador() or usuario_id = (select auth.uid()));

create policy "deportistas: borrar solo entrenador"
  on public.deportistas for delete to authenticated
  using (privado.es_entrenador());

-- ---------------------------------------------------------------------
-- 5. TESTS
-- ---------------------------------------------------------------------
create policy "tests: ver entrenador o el propio"
  on public.tests for select to authenticated
  using (privado.es_entrenador() or dni_deportista = privado.mi_dni_deportista());

create policy "tests: registrar entrenador o el propio"
  on public.tests for insert to authenticated
  with check (privado.es_entrenador() or dni_deportista = privado.mi_dni_deportista());

create policy "tests: editar entrenador o el propio"
  on public.tests for update to authenticated
  using (privado.es_entrenador() or dni_deportista = privado.mi_dni_deportista())
  with check (privado.es_entrenador() or dni_deportista = privado.mi_dni_deportista());

create policy "tests: borrar entrenador o el propio"
  on public.tests for delete to authenticated
  using (privado.es_entrenador() or dni_deportista = privado.mi_dni_deportista());

-- ---------------------------------------------------------------------
-- 6. SESIONES
-- ---------------------------------------------------------------------
create policy "sesiones: ver entrenador o el deportista"
  on public.sesiones for select to authenticated
  using (privado.es_entrenador() or dni_deportista = privado.mi_dni_deportista());

-- El entrenador crea sesiones para cualquiera; el deportista solo para sí
-- mismo y marcadas como creadas por él.
create policy "sesiones: crear"
  on public.sesiones for insert to authenticated
  with check (
    privado.es_entrenador()
    or (dni_deportista = privado.mi_dni_deportista() and creada_por = 'deportista')
  );

create policy "sesiones: editar"
  on public.sesiones for update to authenticated
  using (privado.puede_editar_sesion(id))
  with check (
    privado.es_entrenador()
    or (dni_deportista = privado.mi_dni_deportista() and creada_por = 'deportista')
  );

create policy "sesiones: borrar"
  on public.sesiones for delete to authenticated
  using (privado.puede_editar_sesion(id));

-- ---------------------------------------------------------------------
-- 7. TAREAS y PARTES DE TAREA (el plan de la sesión)
-- ---------------------------------------------------------------------
create policy "tareas: ver"
  on public.tareas for select to authenticated
  using (privado.puede_ver_sesion(id_sesion));

create policy "tareas: crear"
  on public.tareas for insert to authenticated
  with check (privado.puede_editar_sesion(id_sesion));

create policy "tareas: editar"
  on public.tareas for update to authenticated
  using (privado.puede_editar_sesion(id_sesion))
  with check (privado.puede_editar_sesion(id_sesion));

create policy "tareas: borrar"
  on public.tareas for delete to authenticated
  using (privado.puede_editar_sesion(id_sesion));

create policy "partes_tarea: ver"
  on public.partes_tarea for select to authenticated
  using (privado.puede_ver_sesion(privado.sesion_de_tarea(id_tarea)));

create policy "partes_tarea: crear"
  on public.partes_tarea for insert to authenticated
  with check (privado.puede_editar_sesion(privado.sesion_de_tarea(id_tarea)));

create policy "partes_tarea: editar"
  on public.partes_tarea for update to authenticated
  using (privado.puede_editar_sesion(privado.sesion_de_tarea(id_tarea)))
  with check (privado.puede_editar_sesion(privado.sesion_de_tarea(id_tarea)));

create policy "partes_tarea: borrar"
  on public.partes_tarea for delete to authenticated
  using (privado.puede_editar_sesion(privado.sesion_de_tarea(id_tarea)));

-- ---------------------------------------------------------------------
-- 8. LO REALIZADO (sesiones_realizadas, tareas_realizadas, trazas)
-- Lo ven y lo escriben el deportista de la sesión y los entrenadores.
-- ---------------------------------------------------------------------
create policy "sesiones_realizadas: ver"
  on public.sesiones_realizadas for select to authenticated
  using (privado.puede_ver_sesion(id_sesion));

create policy "sesiones_realizadas: registrar"
  on public.sesiones_realizadas for insert to authenticated
  with check (privado.puede_registrar_sesion(id_sesion));

create policy "sesiones_realizadas: corregir"
  on public.sesiones_realizadas for update to authenticated
  using (privado.puede_registrar_sesion(id_sesion))
  with check (privado.puede_registrar_sesion(id_sesion));

create policy "sesiones_realizadas: borrar"
  on public.sesiones_realizadas for delete to authenticated
  using (privado.puede_registrar_sesion(id_sesion));

create policy "tareas_realizadas: ver"
  on public.tareas_realizadas for select to authenticated
  using (privado.puede_ver_sesion(privado.sesion_de_tarea(id_tarea)));

create policy "tareas_realizadas: registrar"
  on public.tareas_realizadas for insert to authenticated
  with check (privado.puede_registrar_sesion(privado.sesion_de_tarea(id_tarea)));

create policy "tareas_realizadas: corregir"
  on public.tareas_realizadas for update to authenticated
  using (privado.puede_registrar_sesion(privado.sesion_de_tarea(id_tarea)))
  with check (privado.puede_registrar_sesion(privado.sesion_de_tarea(id_tarea)));

create policy "tareas_realizadas: borrar"
  on public.tareas_realizadas for delete to authenticated
  using (privado.puede_registrar_sesion(privado.sesion_de_tarea(id_tarea)));

create policy "trazas: ver"
  on public.trazas for select to authenticated
  using (privado.puede_ver_sesion(id_sesion));

create policy "trazas: subir"
  on public.trazas for insert to authenticated
  with check (privado.puede_registrar_sesion(id_sesion));

create policy "trazas: reemplazar"
  on public.trazas for update to authenticated
  using (privado.puede_registrar_sesion(id_sesion))
  with check (privado.puede_registrar_sesion(id_sesion));

create policy "trazas: quitar"
  on public.trazas for delete to authenticated
  using (privado.puede_registrar_sesion(id_sesion));

commit;
