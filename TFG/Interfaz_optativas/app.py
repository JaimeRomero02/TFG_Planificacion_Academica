import re
import csv
import io
import streamlit as st
from pathlib import Path
import tempfile
import subprocess


st.set_page_config(
    page_title="Asignación de optativas",
    layout="wide"
)

st.title("Asignación de optativas con MiniZinc")

st.markdown(
    """
    Esta interfaz permite cargar un archivo `.dzn`, ajustar parámetros del modelo
    y ejecutar MiniZinc sin modificar manualmente el código.
    """
)

# Ruta del modelo MiniZinc
MODEL_PATH = Path("models/optativas.mzn")

# Ruta del ejecutable de MiniZinc
MINIZINC_PATH = r"C:\Program Files\MiniZinc\minizinc.exe"


# ------------------------------------------------------------
# FUNCIONES AUXILIARES
# ------------------------------------------------------------

def extract_int_parameter(dzn_text: str, name: str, default: int) -> int:
    """
    Extrae un parámetro entero del .dzn.
    Ejemplo: max_credits = 12;
    """
    match = re.search(
        rf"^\s*{name}\s*=\s*(\d+)\s*;",
        dzn_text,
        flags=re.MULTILINE
    )
    if match:
        return int(match.group(1))
    return default


def extract_int_array(dzn_text: str, name: str) -> list[int]:
    """
    Extrae un array de enteros del .dzn.
    Ejemplo: capacity = [7, 3, 33];
    """
    match = re.search(
        rf"^\s*{name}\s*=\s*\[(.*?)\]\s*;",
        dzn_text,
        flags=re.MULTILINE | re.DOTALL
    )

    if not match:
        return []

    content = match.group(1)
    values = re.findall(r"-?\d+", content)
    return [int(v) for v in values]


def extract_string_array(dzn_text: str, name: str) -> list[str]:
    """
    Extrae un array de strings del .dzn.
    Ejemplo: course_names = ["A", "B", "C"];
    """
    match = re.search(
        rf"^\s*{name}\s*=\s*\[(.*?)\]\s*;",
        dzn_text,
        flags=re.MULTILINE | re.DOTALL
    )

    if not match:
        return []

    content = match.group(1)
    values = re.findall(r'"([^"]*)"', content)
    return values


def minizinc_array(values: list[int]) -> str:
    """
    Convierte una lista de Python en un array MiniZinc.
    Ejemplo: [1, 2, 3] -> "[1, 2, 3]"
    """
    return "[" + ", ".join(str(v) for v in values) + "]"


def replace_configurable_parameters(
    dzn_text: str,
    weight_preferences: int,
    weight_grade: int,
    weight_rejections: int,
    max_previous_rejections_considered: int,
    max_credits_value: int,
    capacity_values: list[int],
    credits_values: list[int],
    avg_grade_values: list[int],
) -> str:
    """
    Elimina del .dzn cualquier asignación previa de los parámetros configurables
    y añade los valores seleccionados desde la interfaz.
    """

    parameter_names = [
        "weight_preferences",
        "weight_grade",
        "weight_rejections",
        "max_previous_rejections_considered",
        "max_credits",
        "capacity",
        "credits",
        "avg_grade_100",
    ]

    cleaned_text = dzn_text

    for name in parameter_names:
        cleaned_text = re.sub(
            rf"^\s*{name}\s*=\s*[^;]*;\s*$",
            "",
            cleaned_text,
            flags=re.MULTILINE | re.DOTALL,
        )

    capacity_text = minizinc_array(capacity_values)
    credits_text = minizinc_array(credits_values)
    avg_grade_text = minizinc_array(avg_grade_values)

    extra_params = f"""

% Parámetros configurables generados desde Streamlit
max_credits = {max_credits_value};
capacity = {capacity_text};
credits = {credits_text};
avg_grade_100 = {avg_grade_text};

weight_preferences = {weight_preferences};
weight_grade = {weight_grade};
weight_rejections = {weight_rejections};
max_previous_rejections_considered = {max_previous_rejections_considered};
"""

    return cleaned_text.strip() + extra_params


def parse_assigned_courses(output_text: str) -> list[dict]:
    """
    Extrae de la salida de MiniZinc la tabla final con SI/NO
    y devuelve una lista con cada estudiante y sus asignaturas asignadas.
    """

    lines = [line.strip() for line in output_text.splitlines() if line.strip()]

    # Buscar las cabeceras que empiezan por STUDENT;
    student_headers = [
        i for i, line in enumerate(lines)
        if line.startswith("STUDENT;")
    ]

    # La salida tiene dos tablas:
    # 1. Tabla detallada con créditos, preferencias e indicadores.
    # 2. Tabla final con SI/NO.
    if len(student_headers) < 2:
        return []

    start_index = student_headers[1]

    header = lines[start_index].split(";")
    course_names_from_output = header[1:]

    assignments = []

    for line in lines[start_index + 1:]:
        if line.startswith("----------") or line.startswith("=========="):
            break

        parts = line.split(";")

        if len(parts) < 2:
            continue

        student = parts[0]
        values = parts[1:]

        assigned_courses = [
            course_names_from_output[i]
            for i, value in enumerate(values)
            if i < len(course_names_from_output)
            and value.replace('"', "").strip() == "SI"
        ]

        assignments.append(
            {
                "Estudiante": student,
                "Asignaturas asignadas": ", ".join(assigned_courses)
            }
        )

    return assignments


def generate_assignments_csv(assignments: list[dict]) -> str:
    """
    Genera un CSV con el resumen de asignaciones.
    """

    output = io.StringIO()
    writer = csv.DictWriter(
        output,
        fieldnames=["Estudiante", "Asignaturas asignadas"],
        delimiter=";"
    )

    writer.writeheader()

    for row in assignments:
        writer.writerow(row)

    return output.getvalue()


# ------------------------------------------------------------
# SUBIDA DE ARCHIVO
# ------------------------------------------------------------

uploaded_dzn = st.file_uploader(
    "Sube el archivo de datos MiniZinc (.dzn)",
    type=["dzn"]
)


if uploaded_dzn is None:
    st.info("Sube un archivo `.dzn` para comenzar.")

else:
    dzn_text = uploaded_dzn.read().decode("utf-8")

    original_max_credits = extract_int_parameter(dzn_text, "max_credits", 12)

    original_capacity = extract_int_array(dzn_text, "capacity")
    original_credits = extract_int_array(dzn_text, "credits")
    original_avg_grade_100 = extract_int_array(dzn_text, "avg_grade_100")

    course_names = extract_string_array(dzn_text, "course_names")
    students = extract_string_array(dzn_text, "students")

    if not original_capacity:
        st.error("No se ha podido leer el parámetro `capacity` del archivo .dzn.")
        st.stop()

    if not original_credits:
        st.error("No se ha podido leer el parámetro `credits` del archivo .dzn.")
        st.stop()

    if not original_avg_grade_100:
        st.error("No se ha podido leer el parámetro `avg_grade_100` del archivo .dzn.")
        st.stop()

    if not course_names:
        course_names = [f"Asignatura {i + 1}" for i in range(len(original_capacity))]

    if not students:
        students = [f"Estudiante {i + 1}" for i in range(len(original_avg_grade_100))]

    if len(course_names) != len(original_capacity):
        st.warning(
            "El número de nombres de asignaturas no coincide con el número de capacidades. "
            "Se usarán nombres genéricos."
        )
        course_names = [f"Asignatura {i + 1}" for i in range(len(original_capacity))]

    if len(course_names) != len(original_credits):
        st.warning(
            "El número de nombres de asignaturas no coincide con el número de créditos. "
            "Se usarán nombres genéricos."
        )
        course_names = [f"Asignatura {i + 1}" for i in range(len(original_credits))]

    if len(students) != len(original_avg_grade_100):
        st.warning(
            "El número de estudiantes no coincide con el número de notas medias. "
            "Se usarán nombres genéricos."
        )
        students = [f"Estudiante {i + 1}" for i in range(len(original_avg_grade_100))]

    # ------------------------------------------------------------
    # PARÁMETROS EN LA BARRA LATERAL
    # ------------------------------------------------------------

    st.sidebar.header("Parámetros del modelo")

    weight_preferences = st.sidebar.slider(
        "Peso preferencias",
        min_value=0,
        max_value=1000,
        value=950,
        step=10
    )

    weight_grade = st.sidebar.slider(
        "Peso nota media",
        min_value=0,
        max_value=1000,
        value=30,
        step=10
    )

    weight_rejections = st.sidebar.slider(
        "Peso rechazos previos",
        min_value=0,
        max_value=1000,
        value=20,
        step=10
    )

    max_previous_rejections_considered = st.sidebar.slider(
        "Máximo de rechazos considerados",
        min_value=0,
        max_value=5,
        value=4,
        step=1
    )

    st.sidebar.header("Parámetros del escenario")

    max_credits_value = st.sidebar.number_input(
        "Créditos máximos por estudiante",
        min_value=0,
        max_value=30,
        value=original_max_credits,
        step=1
    )

    # ------------------------------------------------------------
    # EDICIÓN DE CAPACIDADES
    # ------------------------------------------------------------

    st.subheader("Capacidades de asignaturas")

    st.markdown(
        """
        Puedes modificar las plazas disponibles de cada asignatura antes de ejecutar el modelo.
        """
    )

    capacity_values = []

    with st.expander("Editar capacidades", expanded=False):
        for i, course_name in enumerate(course_names):
            value = st.number_input(
                f"{course_name}",
                min_value=0,
                max_value=300,
                value=original_capacity[i],
                step=1,
                key=f"capacity_{i}"
            )
            capacity_values.append(value)

    # ------------------------------------------------------------
    # EDICIÓN DE CRÉDITOS POR ASIGNATURA
    # ------------------------------------------------------------

    st.subheader("Créditos de asignaturas")

    st.markdown(
        """
        Puedes modificar los créditos de cada asignatura.  
        Este parámetro debe cambiarse con cuidado, ya que afecta al cómputo de créditos demandados,
        admitidos y ofertados.
        """
    )

    credits_values = []

    with st.expander("Editar créditos por asignatura", expanded=False):
        for i, course_name in enumerate(course_names):
            value = st.number_input(
                f"{course_name}",
                min_value=0,
                max_value=30,
                value=original_credits[i],
                step=1,
                key=f"credits_{i}"
            )
            credits_values.append(value)

    # ------------------------------------------------------------
    # EDICIÓN DE NOTAS MEDIAS
    # ------------------------------------------------------------

    st.subheader("Notas medias del alumnado")

    st.markdown(
        """
        Puedes modificar la nota media de cada estudiante.  
        La nota se introduce multiplicada por 100. Por ejemplo, 7.50 se representa como 750.
        """
    )

    avg_grade_values = []

    with st.expander("Editar notas medias", expanded=False):
        for i, student in enumerate(students):
            value = st.number_input(
                f"{student}",
                min_value=0,
                max_value=1000,
                value=original_avg_grade_100[i],
                step=1,
                key=f"avg_grade_{i}"
            )
            avg_grade_values.append(value)

    # ------------------------------------------------------------
    # GENERACIÓN DEL DZN FINAL
    # ------------------------------------------------------------

    final_dzn_text = replace_configurable_parameters(
        dzn_text=dzn_text,
        weight_preferences=weight_preferences,
        weight_grade=weight_grade,
        weight_rejections=weight_rejections,
        max_previous_rejections_considered=max_previous_rejections_considered,
        max_credits_value=max_credits_value,
        capacity_values=capacity_values,
        credits_values=credits_values,
        avg_grade_values=avg_grade_values,
    )

    # ------------------------------------------------------------
    # VISTA PREVIA
    # ------------------------------------------------------------

    st.subheader("Vista previa de parámetros")

    st.write(
        {
            "max_credits": max_credits_value,
            "weight_preferences": weight_preferences,
            "weight_grade": weight_grade,
            "weight_rejections": weight_rejections,
            "max_previous_rejections_considered": max_previous_rejections_considered,
        }
    )

    st.subheader("Vista previa de capacidades")

    st.dataframe(
        {
            "Asignatura": course_names,
            "Capacidad": capacity_values,
        },
        width="stretch"
    )

    st.subheader("Vista previa de créditos")

    st.dataframe(
        {
            "Asignatura": course_names,
            "Créditos": credits_values,
        },
        width="stretch"
    )

    st.subheader("Vista previa de notas medias")

    st.dataframe(
        {
            "Estudiante": students,
            "Nota media x100": avg_grade_values,
        },
        width="stretch"
    )

    with st.expander("Ver archivo .dzn generado"):
        st.code(final_dzn_text, language="minizinc")

    # ------------------------------------------------------------
    # EJECUCIÓN DEL MODELO
    # ------------------------------------------------------------

    if st.button("Ejecutar modelo"):
        if not MODEL_PATH.exists():
            st.error(f"No se ha encontrado el modelo: {MODEL_PATH}")

        elif not Path(MINIZINC_PATH).exists():
            st.error(f"No se ha encontrado MiniZinc en: {MINIZINC_PATH}")

        else:
            st.info("Ejecutando MiniZinc...")

            with tempfile.NamedTemporaryFile(
                mode="w",
                suffix=".dzn",
                delete=False,
                encoding="utf-8"
            ) as temp_dzn:
                temp_dzn.write(final_dzn_text)
                temp_dzn_path = temp_dzn.name

            command = [
                MINIZINC_PATH,
                "--solver",
                "HiGHS",
                "--time-limit",
                "120000",
                str(MODEL_PATH),
                temp_dzn_path
            ]

            try:
                result = subprocess.run(
                    command,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=125
                )

                st.subheader("Comando ejecutado")
                st.code(" ".join(command))

                output_text = (
                    result.stdout.decode("utf-8", errors="replace")
                    if result.stdout
                    else ""
                )

                error_text = (
                    result.stderr.decode("utf-8", errors="replace")
                    if result.stderr
                    else ""
                )

                # DEPURACIÓN
                # st.subheader("Depuración")
                # st.write(
                #     {
                #         "returncode": result.returncode,
                #         "stdout_length": len(output_text),
                #         "stderr_length": len(error_text),
                #     }
                # )

                if result.returncode == 0:
                    st.success("Modelo ejecutado correctamente.")

                    if output_text.strip():
                        st.subheader("Resultados de la asignación")
                        st.code(output_text)

                        assigned_courses = parse_assigned_courses(output_text)

                        if assigned_courses:
                            st.subheader("Resumen de asignaturas asignadas por estudiante")

                            st.dataframe(
                                assigned_courses,
                                width="stretch"
                            )

                            summary_csv = generate_assignments_csv(assigned_courses)

                            st.download_button(
                                label="Descargar resumen de asignaciones CSV",
                                data=summary_csv,
                                file_name="resumen_asignaciones.csv",
                                mime="text/csv"
                            )
                        else:
                            st.warning(
                                "No se ha podido generar el resumen de asignaturas asignadas."
                            )

                    else:
                        st.warning("MiniZinc no ha devuelto salida por stdout.")

                        if error_text.strip():
                            st.subheader("Salida por stderr")
                            st.code(error_text)

                    download_text = output_text if output_text.strip() else error_text

                    if download_text.strip():
                        st.download_button(
                            label="Descargar salida completa",
                            data=download_text,
                            file_name="resultado_optativas.csv",
                            mime="text/csv"
                        )
                    else:
                        st.warning("No hay salida disponible para descargar.")

                else:
                    st.error("MiniZinc devolvió un error.")

                    if error_text.strip():
                        st.subheader("Error")
                        st.code(error_text)

                    if output_text.strip():
                        st.subheader("Salida parcial")
                        st.code(output_text)

            except FileNotFoundError:
                st.error(
                    "No se ha encontrado el comando de MiniZinc. "
                    "Comprueba que MiniZinc está instalado correctamente."
                )

            except subprocess.TimeoutExpired:
                st.error("La ejecución ha superado el tiempo máximo permitido.")