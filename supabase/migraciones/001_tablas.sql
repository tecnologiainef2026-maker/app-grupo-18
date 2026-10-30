-- =====================================================================
-- 001_tablas.sql · Grupo 18 · NEXØ
-- Crea las tablas de la app: entrenadores, deportistas, tests, sesiones,
-- tareas (y sus partes) y lo que el deportista registra como realizado.
--
-- Convenciones:
--   · Nombres en español, en minúsculas, sin tildes y en plural.
--   · Las duraciones de las tareas van en minutos (numeric) y los descansos
--     en segundos (integer), igual que en la app.
--   · Los ritmos se guardan como número: segundos por km (unidad 's/km')
--     o km/h (unidad 'km/h'). Así se pueden comparar y ordenar.
--
-- Se ejecuta UNA vez, en el SQL Editor de Supabase o con la CLI.
-- Todavía NO se ha ejecutado: espera la aprobación del grupo.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- ENTRENADORES
-- Diseñan las sesiones y entrenan a los deportistas.
-- ---------------------------------------------------------------------
create table public.entrenadores (
  dni           text primary key,                       -- DNI/NIE, p. ej. 12345678Z
  nombre        text not null,
  correo        text,
  especialidad  text,
  usuario_id    uuid unique references auth.users (id) on delete set null,
                                                        -- su cuenta de Supabase Auth (para la seguridad)
  creado_en     timestamptz not null default now(),
  constraint entrenadores_dni_formato check (dni ~ '^[XYZ0-9][0-9]{7}[A-Z]$')
);

-- ---------------------------------------------------------------------
-- DEPORTISTAS
-- Cada deportista practica un deporte y tiene (como mucho) un entrenador.
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
  dni_entrenador    text references public.entrenadores (dni)
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
-- TESTS
-- Resultados de los tests de rendimiento. Sobre el último de cada tipo
-- se calcula el % de esfuerzo de las tareas.
-- ---------------------------------------------------------------------
create table public.tests (
  id              bigint generated always as identity primary key,
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
-- SESIONES
-- Una sesión la realiza un deportista y la diseña un entrenador.
-- Es la tabla que une a entrenadores y deportistas en cada entrenamiento.
-- ---------------------------------------------------------------------
create table public.sesiones (
  id              bigint generated always as identity primary key,
  dni_deportista  text not null references public.deportistas (dni)
                       on update cascade on delete cascade,
  dni_entrenador  text references public.entrenadores (dni)
                       on update cascade on delete set null,
  fecha           date not null,
  hora            time not null,
  duracion_min    numeric,                              -- duración prevista
  duracion_auto   boolean not null default true,        -- true = suma de las tareas
  objetivo        text,
  rpe             smallint,                             -- RPE previsto (escala CR10)
  creada_por      text not null default 'entrenador',
  creado_en       timestamptz not null default now(),
  constraint sesiones_rpe check (rpe is null or rpe between 1 and 10),
  constraint sesiones_duracion check (duracion_min is null or duracion_min >= 0),
  constraint sesiones_creada_por check (creada_por in ('entrenador', 'deportista'))
);

-- ---------------------------------------------------------------------
-- TAREAS
-- Bloques de una sesión, en orden. Una tarea "compuesta" no tiene valor
-- propio: sus partes van en la tabla partes_tarea.
-- ---------------------------------------------------------------------
create table public.tareas (
  id                  bigint generated always as identity primary key,
  id_sesion           bigint not null references public.sesiones (id) on delete cascade,
  orden               smallint not null default 1,
  tipo                text not null,
  valor               numeric,                          -- metros, km, W, segundos, s/km, km/h, rpm…
  unidad              text,
  series              smallint not null default 1,
  descanso_seg        integer,                          -- descanso entre series
  esfuerzo_pct        numeric,                          -- % de esfuerzo sobre el test de referencia
  id_test_referencia  bigint references public.tests (id) on delete set null,
  objetivo            text,                             -- texto calculado, p. ej. '4:36 /km'
  duracion_min        numeric,                          -- duración de UNA serie
  duracion_estimada   boolean not null default false,
  constraint tareas_tipo check (tipo in ('distancia', 'potencia', 'tiempo', 'ritmo', 'frecuencia', 'compuesta')),
  constraint tareas_valor check ((tipo = 'compuesta') = (valor is null)),
  constraint tareas_unidad check (unidad is null or unidad in ('m', 'km', 'W', 's', 's/km', 'km/h', 'rpm', 'pal/min', 'pasos/min', 'ppm')),
  constraint tareas_series check (series >= 1),
  constraint tareas_descanso check (descanso_seg is null or descanso_seg >= 0),
  constraint tareas_esfuerzo check (esfuerzo_pct is null or (esfuerzo_pct > 0 and esfuerzo_pct <= 200))
);

-- ---------------------------------------------------------------------
-- PARTES DE TAREA
-- Solo para tareas compuestas: cada serie se hace con estas partes, en orden.
-- ---------------------------------------------------------------------
create table public.partes_tarea (
  id                  bigint generated always as identity primary key,
  id_tarea            bigint not null references public.tareas (id) on delete cascade,
  orden               smallint not null,
  tipo                text not null,
  valor               numeric not null,
  unidad              text,
  esfuerzo_pct        numeric,
  id_test_referencia  bigint references public.tests (id) on delete set null,
  objetivo            text,
  duracion_min        numeric,
  duracion_estimada   boolean not null default false,
  constraint partes_tarea_tipo check (tipo in ('distancia', 'potencia', 'tiempo', 'ritmo', 'frecuencia')),
  constraint partes_tarea_esfuerzo check (esfuerzo_pct is null or (esfuerzo_pct > 0 and esfuerzo_pct <= 200)),
  constraint partes_tarea_orden_unico unique (id_tarea, orden)
);

-- ---------------------------------------------------------------------
-- SESIONES REALIZADAS
-- Lo que el deportista anota al terminar. Como mucho una por sesión (1:1),
-- por eso su clave primaria es a la vez la clave foránea a sesiones.
-- ---------------------------------------------------------------------
create table public.sesiones_realizadas (
  id_sesion         bigint primary key references public.sesiones (id) on delete cascade,
  duracion_min      numeric,                            -- minutos reales
  rpe               smallint,                           -- RPE real
  comentario        text,
  ritmo             numeric,                            -- solo si la sesión no tiene tareas
  unidad_ritmo      text,
  potencia_w        numeric,
  fc_media          smallint,
  distancia_m       numeric,
  registrado_en     timestamptz not null default now(),
  constraint sesiones_realizadas_rpe check (rpe is null or rpe between 1 and 10),
  constraint sesiones_realizadas_unidad check (unidad_ritmo is null or unidad_ritmo in ('s/km', 'km/h'))
);

-- ---------------------------------------------------------------------
-- TAREAS REALIZADAS
-- Lo realizado en cada tarea (1:1 con tareas).
-- ---------------------------------------------------------------------
create table public.tareas_realizadas (
  id_tarea      bigint primary key references public.tareas (id) on delete cascade,
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

-- ---------------------------------------------------------------------
-- TRAZAS
-- Archivo del reloj (GPX/TCX) ya reducido a ~480 puntos. Los puntos van en
-- jsonb porque se leen y se guardan siempre juntos.
-- ---------------------------------------------------------------------
create table public.trazas (
  id_sesion       bigint primary key references public.sesiones_realizadas (id_sesion) on delete cascade,
  nombre_archivo  text,
  puntos          jsonb not null,                       -- {"t":[s],"d":[m],"alt":[m],"fc":[ppm],"pot":[W]}
  subido_en       timestamptz not null default now()
);

-- Índices para las búsquedas más habituales (las claves foráneas no los crean solas).
create index deportistas_dni_entrenador_idx on public.deportistas (dni_entrenador);
create index tests_deportista_tipo_fecha_idx on public.tests (dni_deportista, tipo, fecha desc);
create index sesiones_deportista_fecha_idx on public.sesiones (dni_deportista, fecha desc);
create index sesiones_dni_entrenador_idx on public.sesiones (dni_entrenador);
create index tareas_sesion_orden_idx on public.tareas (id_sesion, orden);
create index tareas_test_referencia_idx on public.tareas (id_test_referencia);
create index partes_tarea_test_referencia_idx on public.partes_tarea (id_test_referencia);

commit;
