-- =====================================================================
-- 003_fc_umbral.sql · Grupo 18 · NEXØ
-- PROPUESTA (sin ejecutar, pendiente de aprobación del grupo).
--
-- La carga semanal pasa a calcularse con el hrTSS:
--   hrTSS = horas × hrIF² × 100
--   hrIF  = (FC media − FC reposo) / (FC umbral − FC reposo)
-- Para eso cada deportista necesita su FC umbral (LTHR), que no estaba
-- en el modelo. Esta migración añade esa columna a deportistas.
-- La carga no se guarda: la app la calcula al vuelo con la FC registrada.
-- =====================================================================

begin;

alter table public.deportistas
  add column fc_umbral smallint;                        -- FC umbral de lactato (LTHR), en ppm

alter table public.deportistas
  add constraint deportistas_fc_umbral check (fc_umbral is null or fc_umbral between 80 and 230),
  add constraint deportistas_fc_umbral_coherente check (
    fc_umbral is null
    or ((fc_reposo is null or fc_reposo < fc_umbral) and (fc_max is null or fc_umbral <= fc_max))
  );

commit;
