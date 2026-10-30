-- =====================================================================
-- 001_tablas.sql · Grupo 18 · NEXØ
-- Traducción a PostgreSQL del diagrama E-R (docs/modelo-er.png).
--
-- Del diagrama:   entrenadores, deportistas, tests (FTP, VO2 máx,
--                 contrarrelojes y sprint), sesiones, tareas y sus cinco
--                 subentidades (distancia, potencia, tiempo, ritmo, frecuencia).
-- Añadido por la app (no está en el diagrama): lo que el deportista
--                 registra (sesiones_realizadas, tareas_realizadas, trazas),
--                 el test de referencia de cada tarea, las tareas compuestas
--                 (id_tarea_padre) y usuario_id para las cuentas.
--
-- Convenciones:
--   · Nombres en español, en minúsculas, sin tildes y en plural.
--   · Duraciones en minutos (numeric); descansos y tiempos en segundos.
--   · Ritmos como número: segundos por km ('s/km') o km/h ('km/h').
--
-- Todavía NO se ha ejecutado: espera la aprobación del grupo.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- ENTRENADORES (entidad Entrenador)
-- ---------------------------------------------------------------------
create table public.entrenadores (
  dni_entrenador  text primary key,
  nombre          text not null,                        -- no está en el diagrama; la app lo muestra
  correo          text,
  especialidad    text,
  usuario_id      uuid unique references auth.users (id) on delete set null,
                                                        -- su cuenta de Supabase Auth (para la seguridad)
  creado_en       timestamptz not null default now(),
  constraint entrenadores_dni_formato check (dni_entrenador ~ '^[XYZ0-9][0-9]{7}[A-Z]$')
);

-- ---------------------------------------------------------------------
-- DEPORTISTAS (entidad Deportista)
-- Relación «Entrena»: un entrenador entrena a N deportistas y cada
-- deportista tiene 1 entrenador → la clave foránea va en deportistas.
-- ---------------------------------------------------------------------
create table public.deportistas (
  dni               text primary key,
  nombre            text not null,
  foto_url          text,                               -- enlace a la foto en Supabase Storage
  fecha_nacimiento  date,
  deporte           text not null,
  objetivos         text,
  fc_max            smallint,                           -- frecuencia cardiaca máxima (ppm)
  fc_reposo         smallint,                           -- frecuencia cardiaca en reposo (ppm)
  dni_entrenador    text references public.entrenadores (dni_entrenador)
                         on update cascade on delete restrict,
  usuario_id        uuid unique references auth.users (id) on delete set null,
  creado_en         timestamptz not null default now(),
  constraint deportistas_dni_formato check (dni ~ '^[XYZ0-9][0-9]{7}[A-Z]$'),
  constraint deportistas_deporte check (deporte in ('ciclismo', 'piraguismo', 'carrera')),
  constraint deportistas_fc_max check (fc_max is null or fc_max between 100 and 240),
  constraint deportistas_fc_reposo check (fc_reposo is null or fc_reposo between 25 and 110),
  constraint deportistas_fc_coherente check (fc_max is null or fc_reposo is null or fc_reposo < fc_max)
);

-- ---------------------------------------------------------------------
-- TESTS (entidades FTP, VO2 máx, Contrarreloj 30min, Contrarreloj 2000m
-- y Sprint 200m)
-- Las cinco tienen los mismos datos, así que van en una sola tabla con
-- una columna «tipo». Un deportista tiene N resultados de cada test.
-- ---------------------------------------------------------------------
create table public.tests (
  id_test         bigint generated always as identity primary key,
  dni_deportista  text not null references public.deportistas (dni)
                       on update cascade on delete cascade,
  tipo            text not null,
  fecha           date not null default current_date,
  valor           numeric not null,                     -- W, ml/kg/min, metros o segundos según el tipo
  notas           text,
  constraint tests_tipo check (tipo in ('ftp', 'vo2max', 'contrarreloj_30min', 'contrarreloj_2000m', 'sprint_200m')),
  constraint tests_valor_positivo check (valor > 0)
);

-- ---------------------------------------------------------------------
-- SESIONES (entidad Sesiones)
-- «Realizan»: 1 deportista realiza N sesiones → FK dni_deportista.
-- «Diseña»:   1 entrenador diseña N sesiones  → FK dni_entrenador.
--   (El diagrama pone «Nombre Entrenador»; la FK tiene que apuntar a la
--   clave primaria de entrenadores, que es el DNI.)
-- Clave primaria: id_sesion (número automático). El diagrama identifica la
-- sesión por fecha y hora; eso se mantiene como clave única junto con el
-- deportista, porque dos deportistas pueden entrenar a la misma hora.
-- ---------------------------------------------------------------------
create table public.sesiones (
  id_sesion       bigint generated always as identity primary key,
  dni_deportista  text not null references public.deportistas (dni)
                       on update cascade on delete cascade,
  dni_entrenador  text references public.entrenadores (dni_entrenador)
                       on update cascade on delete set null,
  fecha           date not null,
  hora            time not null,
  duracion_min    numeric,                              -- duración prevista
  duracion_auto   boolean not null default true,        -- true = suma de las tareas
  objetivo        text,
  rpe             smallint,                             -- RPE previsto (escala CR10)
  creada_por      text not null default 'entrenador',
  creado_en       timestamptz not null default now(),
  constraint sesiones_deportista_fecha_hora unique (dni_deportista, fecha, hora),
  constraint sesiones_rpe check (rpe is null or rpe between 1 and 10),
  constraint sesiones_duracion check (duracion_min is null or duracion_min >= 0),
  constraint sesiones_creada_por check (creada_por in ('entrenador', 'deportista'))
);

-- ---------------------------------------------------------------------
-- TAREAS (entidad Tareas, la superentidad)
-- «Tienen»: 1 sesión tiene N tareas → FK id_sesion (en el diagrama, Fecha y Hora).
-- Lo que se mide (distancia, potencia…) va en las subentidades de abajo.
-- ---------------------------------------------------------------------
create table public.tareas (
  id_tarea            bigint generated always as identity primary key,
  id_sesion           bigint not null references public.sesiones (id_sesion) on delete cascade,
  id_tarea_padre      bigint references public.tareas (id_tarea) on delete cascade,
                                                        -- solo en las partes de una tarea compuesta
  orden               smallint not null default 1,
  series              smallint not null default 1,
  descanso_seg        integer,                          -- descanso entre series
  zona_entrenamiento  numeric,                          -- % de esfuerzo sobre el test de referencia
  duracion_min        numeric,                          -- duración de UNA serie
  id_test_referencia  bigint references public.tests (id_test) on delete set null,
  objetivo            text,                             -- texto calculado, p. ej. '4:36 /km'
  duracion_estimada   boolean not null default false,
  constraint tareas_series check (series >= 1),
  constraint tareas_descanso check (descanso_seg is null or descanso_seg >= 0),
  constraint tareas_zona check (zona_entrenamiento is null or (zona_entrenamiento > 0 and zona_entrenamiento <= 200)),
  constraint tareas_no_es_su_padre check (id_tarea_padre is distinct from id_tarea)
);

-- ---------------------------------------------------------------------
-- SUBENTIDADES DE TAREAS
-- Cada una tiene como clave primaria el mismo id_tarea, que a la vez es
-- clave foránea a tareas (relación 1:1, como en el diagrama).
-- ---------------------------------------------------------------------
create table public.tareas_distancia (
  id_tarea   bigint primary key references public.tareas (id_tarea) on delete cascade,
  distancia  numeric not null,
  unidad     text not null default 'm',
  constraint tareas_distancia_valor check (distancia > 0),
  constraint tareas_distancia_unidad check (unidad in ('m', 'km'))
);

create table public.tareas_potencia (
  id_tarea    bigint primary key references public.tareas (id_tarea) on delete cascade,
  potencia_w  numeric not null,
  constraint tareas_potencia_valor check (potencia_w > 0)
);

create table public.tareas_tiempo (
  id_tarea    bigint primary key references public.tareas (id_tarea) on delete cascade,
  tiempo_seg  integer not null,
  constraint tareas_tiempo_valor check (tiempo_seg > 0)
);

create table public.tareas_ritmo (
  id_tarea  bigint primary key references public.tareas (id_tarea) on delete cascade,
  ritmo     numeric not null,                           -- segundos por km, o km/h
  unidad    text not null default 's/km',
  constraint tareas_ritmo_valor check (ritmo > 0),
  constraint tareas_ritmo_unidad check (unidad in ('s/km', 'km/h'))
);

create table public.tareas_frecuencia (
  id_tarea    bigint primary key references public.tareas (id_tarea) on delete cascade,
  frecuencia  numeric not null,
  unidad      text not null,
  constraint tareas_frecuencia_valor check (frecuencia > 0),
  constraint tareas_frecuencia_unidad check (unidad in ('rpm', 'pal/min', 'pasos/min', 'ppm'))
);

-- ---------------------------------------------------------------------
-- LO REALIZADO (no está en el diagrama)
-- sesiones_realizadas y tareas_realizadas son 1:1 con sesiones y tareas,
-- por eso su clave primaria es a la vez la clave foránea.
-- ---------------------------------------------------------------------
create table public.sesiones_realizadas (
  id_sesion      bigint primary key references public.sesiones (id_sesion) on delete cascade,
  duracion_min   numeric,                               -- minutos reales
  rpe            smallint,                              -- RPE real
  comentario     text,
  ritmo          numeric,                               -- solo si la sesión no tiene tareas
  unidad_ritmo   text,
  potencia_w     numeric,
  fc_media       smallint,
  distancia_m    numeric,
  registrado_en  timestamptz not null default now(),
  constraint sesiones_realizadas_rpe check (rpe is null or rpe between 1 and 10),
  constraint sesiones_realizadas_unidad check (unidad_ritmo is null or unidad_ritmo in ('s/km', 'km/h'))
);

create table public.tareas_realizadas (
  id_tarea      bigint primary key references public.tareas (id_tarea) on delete cascade,
  estado        text not null default 'completada',
  duracion_min  numeric,
  auto          boolean not null default false,         -- true = minutos calculados (previsto o reloj)
  ritmo         numeric,
  unidad_ritmo  text,
  potencia_w    numeric,
  fc_media      smallint,
  distancia_m   numeric,
  comentario    text,
  constraint tareas_realizadas_estado check (estado in ('completada', 'parcial', 'no')),
  constraint tareas_realizadas_unidad check (unidad_ritmo is null or unidad_ritmo in ('s/km', 'km/h'))
);

-- Archivo del reloj (GPX/TCX) reducido a ~480 puntos. Se lee y se guarda entero, por eso va en jsonb.
create table public.trazas (
  id_sesion       bigint primary key references public.sesiones_realizadas (id_sesion) on delete cascade,
  nombre_archivo  text,
  puntos          jsonb not null,                       -- {"t":[s],"d":[m],"alt":[m],"fc":[ppm],"pot":[W]}
  subido_en       timestamptz not null default now()
);

-- Índices para las búsquedas más habituales (las claves foráneas no los crean solas).
create index deportistas_dni_entrenador_idx on public.deportistas (dni_entrenador);
create index tests_deportista_tipo_fecha_idx on public.tests (dni_deportista, tipo, fecha desc);
create index sesiones_dni_entrenador_idx on public.sesiones (dni_entrenador);
create index tareas_sesion_orden_idx on public.tareas (id_sesion, orden);
create index tareas_padre_idx on public.tareas (id_tarea_padre);
create index tareas_test_referencia_idx on public.tareas (id_test_referencia);

commit;
