% Conjuntos e índices
int: max_credits;
int: n_courses;
int: n_students;

array[1..n_courses] of string: course_names;
array[1..n_courses] of string: course_codes;
array[1..n_courses] of int: capacity;
array[1..n_courses] of int: credits;

array[1..n_students] of string: students;
array[1..n_students, 1..n_courses] of 0..3: pref;

% ---------------------------------
% NUEVOS DATOS PARA RANKING GLOBAL
% ---------------------------------

% Nota media multiplicada por 100
array[1..n_students] of int: avg_grade_100;

% Número de rechazos previos por alumno y asignatura.
array[1..n_students, 1..n_courses] of int: previous_rejections;

% ---------------------------------
% PARÁMETROS CONFIGURABLES
% ---------------------------------

int: weight_preferences;
int: weight_grade;
int: weight_rejections;
int: max_previous_rejections_considered;

% Oferta total de créditos (créditos por capacidad)
int: total_credits_offered = sum(c in 1..n_courses)( credits[c] * capacity[c] );

% Créditos demandados por alumno (limitado a max_credits)
array[1..n_students] of int: demanded_credits =
  [ min(max_credits, sum(c in 1..n_courses)(credits[c] * bool2int(pref[s,c] > 0))) | s in 1..n_students ];

% Demanda total de créditos
int: total_demanded_credits = sum(s in 1..n_students)(demanded_credits[s]);

% Estrellas marcadas (demandadas) totales de un alumno (interés)
array[1..n_students] of int: demanded_stars = [ sum(c in 1..n_courses)(pref[s,c]) | s in 1..n_students ];

% Medida de la satisfacción de un alumno: interés en una asignatura
% nota: asignaturas sin puntuar:interés cero. asignaturas puntuadas: ponderación por cantidad estrellas demandadas, siendo la suma de estrellas el 100% y repartiendo después entre cada asignatura el porcentaje a razón de las estrellas demandadas
array[1..n_students, 1..n_courses] of int: student_course_interest =
  array2d(
    1..n_students,
    1..n_courses,
    [
      if demanded_stars[s] > 0
      then 100 * pref[s,c] div demanded_stars[s]
      else 0
      endif
      | s in 1..n_students, c in 1..n_courses
    ]
  );

% ------------------------------
% RANKING GLOBAL DEL ESTUDIANTE
% preferencias     = 95%
% nota media       = 3%
% intentos previos = 2%
% ------------------------------

int: min_grade_100 = min(avg_grade_100);
int: max_grade_100 = max(avg_grade_100);

% Nota media normalizada a [0..100]
array[1..n_students] of int: grade_score =
[
  if max_grade_100 > min_grade_100
  then 100 * (avg_grade_100[s] - min_grade_100)
       div (max_grade_100 - min_grade_100)
  else 100
  endif
  | s in 1..n_students
];

% Bonus por historial de rechazo en X asignatura (no lineal, para que no explote de manera proporcional a los intentos)

% Rechazos previos acotados, a partir de la cota, nuevos rechazos no aumentan el bonus
array[1..n_students, 1..n_courses] of int: capped_previous_rejections =
array2d(
  1..n_students,
  1..n_courses,
  [
    min(previous_rejections[s,c], max_previous_rejections_considered)
    | s in 1..n_students, c in 1..n_courses
  ]
);

int: max_rejections = max(capped_previous_rejections);

% Se usa una función cuadrática para que un único rechazo tenga poco impacto
% y el bonus solo sea realmente significativo cuando existan varios rechazos acumulados
array[1..n_students, 1..n_courses] of int: retry_bonus =
array2d(
  1..n_students,
  1..n_courses,
  [
    if max_rejections > 0
    then
      round(
        100 * capped_previous_rejections[s,c] * capped_previous_rejections[s,c]
        div (max_rejections * max_rejections)
      )
    else 0
    endif
    | s in 1..n_students, c in 1..n_courses
  ]
);

% Ranking global del estudiante
array[1..n_students] of int: global_student_ranking =
[
  grade_score[s]
  | s in 1..n_students
];

int: min_global_rank = min(global_student_ranking);
int: max_global_rank = max(global_student_ranking);

% ranking global normalizado
array[1..n_students] of int: global_student_ranking_norm =
[
  if max_global_rank > min_global_rank
  then 100 * (global_student_ranking[s] - min_global_rank)
       div (max_global_rank - min_global_rank)
  else 50
  endif
  | s in 1..n_students
];

% Combinación ponderada del interés del estudiante
% La nota y el historial actúan como factores de ajuste
% Se evita dar puntuación a asignaturas que el alumno no ha solicitado
array[1..n_students, 1..n_courses] of int: final_weighted_interest =
array2d(
  1..n_students,
  1..n_courses,
  [
    if pref[s,c] > 0 then
      weight_preferences * student_course_interest[s,c]
      + weight_grade * (global_student_ranking_norm[s] * student_course_interest[s,c] div 100)
      + weight_rejections * retry_bonus[s,c]
    else
      0
    endif
    | s in 1..n_students, c in 1..n_courses
  ]
);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% VARIABLES

% admitted[s,c] = 1 <-> estudiante s es admitido en asignatura c
array[1..n_students, 1..n_courses] of var 0..1: admitted;

% Créditos totales admitidos a un alumno
array[1..n_students] of var int: admitted_credits =
  [ sum(c in 1..n_courses)(credits[c] * admitted[s,c]) | s in 1..n_students ];

% Medida de la satisfacción de un alumno: número de asignaturas "acertadas"
% array[1..n_students] of var int: student_hits =
%   [ sum(c in 1..n_courses)(bool2int(pref[s,c] > 0) * admitted[s,c]) | s in 1..n_students ];

% Medida de la isatisfacción de un alumno: número de asignaturas admitidas y no solicitadas
array[1..n_students] of var int: student_norequests =
  [ sum(c in 1..n_courses)(bool2int(pref[s,c] = 0) * admitted[s,c]) | s in 1..n_students ];

% Medida de la satisfacción de un alumno: número de estrellas
array[1..n_students] of var int: student_stars =
  [ sum(c in 1..n_courses)(pref[s,c] * admitted[s,c]) | s in 1..n_students ];

% Medida de la satisfacción de un alumno: porcentaje de estrellas
% nota: el porcentaje se calcula sobre el máximo número de estrellas que se le podrían dar y que son 3 * max_credits div 3 (el primer 3 es por max estrellas y el segundo es el mínimo número de créditos por asignatura)
array[1..n_students] of var int: student_stars_percentage =
  [ 100 * student_stars[s] div min(3 * max_credits div 3, sum(c in 1..n_courses)(pref[s,c])) | s in 1..n_students ];

% Medida de la insatisfacción de un alumno: 
% array[1..n_students] of var int: student_dissatisfaction =
%   [ sum(c in 1..n_courses)(pref[s,c]) - student_stars[s] | s in 1..n_students ];

% Medida de la satisfacción de un alumno: ¿cuánto "intérés" se le ha concedido?
array[1..n_students] of var int: student_interest =
  [ sum(c in 1..n_courses)(admitted[s,c] * student_course_interest[s,c]) | s in 1..n_students ];

% Nueva medida de la satisfacción de un alumno: interés ponderado con ranking global
array[1..n_students] of var int: student_weighted_interest =
  [ sum(c in 1..n_courses)(admitted[s,c] * final_weighted_interest[s,c]) | s in 1..n_students ];

array[1..n_students] of var int: retry_score =
  [ sum(c in 1..n_courses)(admitted[s,c] * retry_bonus[s,c]) | s in 1..n_students ];

% % Medida de la satisfacción de una asignatura: número de estrellas
% array[1..n_courses] of var int: course_stars =
%   [ sum(s in 1..n_students)(pref[s,c] * admitted[s,c]) | c in 1..n_courses ];

% % Medida de la satisfacción de una asignatura
% array[1..n_courses] of var int: course_satisfaction =
%   % Número de estrellas
%   % [ course_stars[s] | c in 1..n_courses ];
%   % Porcentaje de estrellas
%   [ 100 * course_stars[c] div (3 * capacity[c]) | c in 1..n_courses ];

% total de créditos asignados
var int : total_admitted_credits = sum(s in 1..n_students, c in 1..n_courses)(credits[c] * admitted[s,c]);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% RESTRICCIONES

% Reparte todos los créditos ofertados
constraint total_credits_offered = total_admitted_credits;

% No admitir alumnos por encima del cupo
constraint forall(c in 1..n_courses) (sum(s in 1..n_students)(admitted[s,c]) <= capacity[c]);

% No dar créditos por encima del máximo
constraint forall(s in 1..n_students)(admitted_credits[s] <= max_credits);

% No dar más créditos que los demandados
constraint forall(s in 1..n_students)(admitted_credits[s] <= demanded_credits[s]);

% Dar al menos tantos créditos como los marcados en preferencias (!cuidado cuando no hay oferta suficiente!)
constraint forall(s in 1..n_students)(admitted_credits[s] >= min(9, demanded_credits[s]));

% Coherencia: no admitir si no se ha solicitado
% =====UNSATISFIABLE=====
% constraint forall(s in 1..n_students, c in 1..n_courses)(pref[s,c] = 0 -> admitted[s,c] = 0);

% Coherencia: no admitir en "demasiadas" que no se hayan solicitado
constraint forall(s in 1..n_students)(student_norequests[s] <= 1);

% Mínimo valor de estrellas para cada alumno
% constraint forall(s in 1..n_students)(student_stars[s] >= 3);

% Mínimo valor de satisfacción para cada alumno
% constraint forall(s in 1..n_students)(student_stars_percentage[s] >= 33);

% Mínimo valor de satisfacción del interés para cada alumno
% constraint forall(s in 1..n_students)(student_interest[s] >= 33);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% OBJETIVOS

% Función objetivo: maximizar "interés"
% solve maximize sum(s in 1..n_students)(student_interest[s]);

% Función objetivo: maximizar interés ponderado con ranking global
% preferencias = 95%, nota media = 3%, intentos previos = 2%
solve maximize sum(s in 1..n_students)(student_weighted_interest[s]);

% Función objetivo: minimizar insatisfacción de los alumnos
% solve minimize sum(s in 1..n_students)(student_dissatisfaction[s]);

% Función objetivo: maximizar número de aciertos
% solve maximize sum(s in 1..n_students)(student_hits[s]);

% Función objetivo: maximizar número de estrellas
% solve maximize sum(s in 1..n_students)(student_stars[s]);

% % Función objetivo: maximizar satisfacción de los alumnos
% solve maximize sum(s in 1..n_students)(student_satisfaction[s]);

% Función objetivo: maximizar satisfacción de las asignaturas
% solve maximize sum(c in 1..n_courses)(course_satisfaction[c]);

% Función objetivo: maximizar satisfacción de alumnos y asignaturas
% solve maximize sum(s in 1..n_students)(student_satisfaction[s]) + sum(c in 1..n_courses)(course_satisfaction[c]);

% Añade una segunda línea en la salida
output
[
  % Cabecera con códigos de asignatura
  "STUDENT"
  ++ concat([ ";" ++ course_names[c] ++ ";PREF" | c in 1..n_courses ])
  ++ ";DEMANDED"
  ++ ";ADMITTED"
  ++ ";MISSING"
  ++ ";STARS PERCENTAGE"
  ++ ";TOTAL INTEREST"
  ++ ";GRADE_SCORE"
  ++ ";RETRY_SCORE"
  ++ ";GLOBAL_RANKING"
  ++ ";WEIGHTED_INTEREST"
  ++ "\n"
]
++
[
  % Una línea por estudiante: correo ; demandado ; admitidos; créditos1 ; créditos2 ;...
  students[s]
  ++ concat([ ";" ++ show(credits[c] * fix(admitted[s,c])) ++ ";" ++ concat(["*" | i in 1..pref[s,c]]) | c in 1..n_courses ])
  ++ ";" ++ show(demanded_credits[s])
  ++ ";" ++ show(fix(admitted_credits[s]))
  ++ ";" ++ show(demanded_credits[s] - fix(admitted_credits[s]))
  ++ ";" ++ show(fix(student_stars_percentage[s]))
  ++ ";" ++ show(fix(student_interest[s]))
  ++ ";" ++ show(grade_score[s])
  ++ ";" ++ show(fix(retry_score[s]))
  ++ ";" ++ show(global_student_ranking[s])
  ++ ";" ++ show(fix(student_weighted_interest[s]))
  ++ "\n"  
  | s in 1..n_students
]
++
["total_credits_offered;", show(total_credits_offered), "\n"]
++
["total_demanded_credits;", show(total_demanded_credits), "\n"]
++
["total_admitted_credits;",show(total_admitted_credits),"\n"]
++
["Sum of student interest shown;",show(sum(s in 1..n_students, c in 1..n_courses)(student_course_interest[s,c])),"\n"]
++
["Sum of student interest assigned;",show(sum(s in 1..n_students)(student_interest[s])),"\n"]
++
["Sum of weighted interest assigned;",show(sum(s in 1..n_students)(student_weighted_interest[s])),"\n"]
++
[
  % Cabecera con códigos de asignatura
  "STUDENT"
  ++ concat([ ";" ++ course_names[c] | c in 1..n_courses ])
  ++ "\n"
]
++
[
  % Una línea por estudiante: correo ; demandado ; admitidos; créditos1 ; créditos2 ;...
  students[s]
  ++ concat([ ";" ++ show(if fix(admitted[s,c]) == 1 then "SI" else "NO" endif) | c in 1..n_courses ])
  ++ "\n"  
  | s in 1..n_students
]
;