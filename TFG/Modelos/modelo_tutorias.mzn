% ----------------------------------------
% MODELO DE TUTORÍAS POR SOLICITUDES
% ----------------------------------------
% Cada solicitud de tutoría pertenece a un estudiante y a una asignatura.
% El modelo asigna cada solicitud a un profesor y una franja horaria,
% respetando disponibilidades, compatibilidad por asignatura y no solapamientos.

int: NEstudiantes;
int: NProfesores;
int: NFranjas;
int: NAsignaturas;
int: NSolicitudes;

set of int: EST = 1..NEstudiantes;
set of int: PROF = 1..NProfesores;
set of int: FRA = 1..NFranjas;
set of int: ASIG = 1..NAsignaturas;
set of int: SOL = 1..NSolicitudes;

% disponibilidad_est[e,t] = true si el estudiante e puede asistir en la franja t
array[EST, FRA] of bool: disponibilidad_est;

% disponibilidad_prof[p,t] = true si el profesor p puede atender en la franja t
array[PROF, FRA] of bool: disponibilidad_prof;

% profesor_asignatura[p,a] = true si el profesor p puede impartir tutoría de la asignatura a
array[PROF, ASIG] of bool: profesor_asignatura;

% estudiante_solicitud[s] = estudiante al que pertenece la solicitud s
array[SOL] of EST: estudiante_solicitud;

% asignatura_solicitud[s] = asignatura de la solicitud s
array[SOL] of ASIG: asignatura_solicitud;

% preferencia[s,t] = preferencia de la solicitud s por la franja t
% por ejemplo: 0 = no deseada, 1 = aceptable, 2 = preferida
array[SOL, FRA] of int: preferencia;

% máximo número total de tutorías que puede atender cada profesor
array[PROF] of int: max_tutorias_prof;

% x[s,p,t] = 1 si la solicitud s se asigna al profesor p en la franja t
array[SOL, PROF, FRA] of var 0..1: x;

% ----------------------------------------
% RESTRICCIONES
% ----------------------------------------

% Cada solicitud se asigna exactamente una vez
constraint
  forall(s in SOL) (
    sum(p in PROF, t in FRA)(x[s,p,t]) = 1
  );

% La franja debe ser válida para el estudiante de la solicitud
constraint
  forall(s in SOL, p in PROF, t in FRA) (
    x[s,p,t] <= bool2int(disponibilidad_est[estudiante_solicitud[s], t])
  );

% La franja debe ser válida para el profesor
constraint
  forall(s in SOL, p in PROF, t in FRA) (
    x[s,p,t] <= bool2int(disponibilidad_prof[p, t])
  );

% El profesor asignado debe poder impartir la asignatura de la solicitud
constraint
  forall(s in SOL, p in PROF, t in FRA) (
    x[s,p,t] <= bool2int(profesor_asignatura[p, asignatura_solicitud[s]])
  );

% Un profesor no puede atender dos tutorías en la misma franja
constraint
  forall(p in PROF, t in FRA) (
    sum(s in SOL)(x[s,p,t]) <= 1
  );

% Un estudiante no puede tener dos tutorías en la misma franja
constraint
  forall(e in EST, t in FRA) (
    sum(s in SOL where estudiante_solicitud[s] = e, p in PROF)(x[s,p,t]) <= 1
  );

% Límite total de tutorías por profesor
constraint
  forall(p in PROF) (
    sum(s in SOL, t in FRA)(x[s,p,t]) <= max_tutorias_prof[p]
  );

% ----------------------------------------
% FUNCIÓN OBJETIVO
% ----------------------------------------

% Satisfacción máxima teórica sin considerar restricciones.
% Para cada solicitud se toma la mejor franja posible según su matriz de preferencias.
int: satisfaccion_maxima_teorica =
  sum(s in SOL)(
    max(t in FRA)(preferencia[s,t])
  );

% Función Objetivo, satisfacción real obtenida por la planificación final.
var int: satisfaccion_total =
  sum(s in SOL, p in PROF, t in FRA)(
    x[s,p,t] * preferencia[s,t]
  );

solve maximize satisfaccion_total;

% ----------------------------------------
% SALIDA
% ----------------------------------------

output
[
  "Satisfaccion maxima teorica = " ++ show(satisfaccion_maxima_teorica) ++ "\n" ++
  "Satisfaccion total = " ++ show(satisfaccion_total) ++ "\n\n"
]
++
[
  if fix(x[s,p,t]) = 1 then
    "Solicitud " ++ show(s) ++
    " (Estudiante " ++ show(estudiante_solicitud[s]) ++
    ", Asignatura " ++ show(asignatura_solicitud[s]) ++
    ") -> Profesor " ++ show(p) ++
    " en franja " ++ show(t)
    ++ " | Preferencia = " ++ show(preferencia[s,t]) ++ "\n"
  else
    ""
  endif
  | s in SOL, p in PROF, t in FRA
];