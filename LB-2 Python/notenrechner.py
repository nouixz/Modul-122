import sqlite3
import re
import os
from datetime import date, datetime
from tabulate import tabulate
import csv
import json
from fpdf import FPDF

# ---------- KONFIGURATION ----------

# Ordner, in dem dieses Skript liegt
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# Datenbankdatei IM GLEICHEN ORDNER wie dieses Skript (Notenomat)
DB_NAME = os.path.join(BASE_DIR, "noten.db")

# Vorgegebene Fächer
SUBJECTS = [
    "Fachenglisch",
    "Gesellschaft",
    "Sport",
    "Sprache und Kommunikation",
    "122 Abläufe mit Scriptsprache"
]

# Terminal-Farben (ANSI)
COLOR_RESET = "\033[0m"
COLOR_GREEN = "\033[32m"
COLOR_YELLOW = "\033[33m"
COLOR_RED = "\033[31m"

def color_grade(grade: float) -> str:
    # 6 gut, 1 schlecht
    if grade >= 5.0:
        color = COLOR_GREEN      # sehr gut / gut (5–6)
    elif grade >= 4.0:
        color = COLOR_YELLOW     # genügend (4–4.9)
    else:
        color = COLOR_RED        # ungenügend (1–3.9)
    return f"{color}{grade:.1f}{COLOR_RESET}"

# ---------- DB-FUNKTIONEN ----------

def get_connection():
    """Verbindung zur SQLite-Datenbank herstellen."""
    return sqlite3.connect(DB_NAME)

def init_db():
    """Erstellt Tabellen und Fächer, falls sie noch nicht existieren."""
    conn = get_connection()
    cur = conn.cursor()

    # Tabelle für Fächer
    cur.execute("""
        CREATE TABLE IF NOT EXISTS subjects (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL
        );
    """)

    # Tabelle für Noten
    cur.execute("""
        CREATE TABLE IF NOT EXISTS grades (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            subject_id INTEGER NOT NULL,
            grade REAL NOT NULL,
            date TEXT NOT NULL,
            FOREIGN KEY(subject_id) REFERENCES subjects(id)
        );
    """)

    # Fächer einfügen, falls nicht vorhanden
    for subj in SUBJECTS:
        cur.execute("INSERT OR IGNORE INTO subjects (name) VALUES (?);", (subj,))

    conn.commit()
    conn.close()

def get_subjects():
    """Liest alle Fächer aus der DB aus."""
    conn = get_connection()
    cur = conn.cursor()
    cur.execute("SELECT id, name FROM subjects ORDER BY id;")
    rows = cur.fetchall()
    conn.close()
    return rows

def insert_grade(subject_id, grade_value, grade_date):
    """Neue Note in die DB einfügen."""
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO grades (subject_id, grade, date) VALUES (?, ?, ?);",
        (subject_id, grade_value, grade_date)
    )
    conn.commit()
    conn.close()

def get_grades_by_subject(subject_id):
    """Alle Noten zu einem Fach zurückgeben."""
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(
        "SELECT grade, date FROM grades WHERE subject_id = ? ORDER BY date;",
        (subject_id,)
    )
    rows = cur.fetchall()
    conn.close()
    return rows

def get_all_grades():
    """Alle Noten mit Fachnamen zurückgeben."""
    conn = get_connection()
    cur = conn.cursor()
    cur.execute("""
        SELECT s.name, g.grade, g.date
        FROM grades g
        JOIN subjects s ON g.subject_id = s.id
        ORDER BY s.name, g.date;
    """)
    rows = cur.fetchall()
    conn.close()
    return rows

def get_average_by_subject(subject_id):
    """Durchschnittsnote für ein Fach berechnen."""
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(
        "SELECT AVG(grade) FROM grades WHERE subject_id = ?;",
        (subject_id,)
    )
    result = cur.fetchone()[0]
    conn.close()
    return result

def get_overall_average():
    """Gesamtdurchschnitt über alle Fächer."""
    conn = get_connection()
    cur = conn.cursor()
    cur.execute("SELECT AVG(grade) FROM grades;")
    result = cur.fetchone()[0]
    conn.close()
    return result

def grade_exists(subject_id, grade_value, grade_date) -> bool:
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(
        "SELECT 1 FROM grades WHERE subject_id=? AND grade=? AND date=? LIMIT 1;",
        (subject_id, grade_value, grade_date)
    )
    exists = cur.fetchone() is not None
    conn.close()
    return exists

# ---------- HILFSFUNKTIONEN (EIN-/AUSGABEN + REGEX) ----------

def input_grade():
    """
    Fragt eine Note ab und prüft sie mit Regex.
    Gültig: 1–6, optional .0 oder .5 (z.B. 4, 4.5, 5.0)
    """
    pattern = re.compile(r"^[1-6](\.0|\.5)?$")
    while True:
        user_input = input("Note eingeben (z.B. 4, 4.5, 5): ").strip()
        if pattern.match(user_input):
            grade_value = float(user_input)
            if 1.0 <= grade_value <= 6.0:
                return grade_value
        print("Ungültige Note. Erlaubt sind Werte zwischen 1 und 6, mit .0 oder .5.")

def select_subject():
    """Lässt den Benutzer ein Fach aus der Liste wählen und gibt (id, name) zurück."""
    subjects = get_subjects()
    print("\nVerfügbare Fächer:")
    for sid, name in subjects:
        print(f"{sid}) {name}")
    while True:
        choice = input("Fach-ID wählen: ").strip()
        if not choice.isdigit():
            print("Bitte eine gültige Zahl eingeben.")
            continue
        choice = int(choice)
        for sid, name in subjects:
            if sid == choice:
                return sid, name
        print("Ungültige Fach-ID, bitte erneut versuchen.")

def input_date():
    """
    Optionales Datum eingeben.
    Leere Eingabe = heutiges Datum.
    Einfache Regex-Prüfung für das Format YYYY-MM-DD.
    """
    today_str = date.today().isoformat()  # z.B. 2025-11-21
    user = input(f"Datum eingeben (YYYY-MM-DD) oder leer für heute ({today_str}): ").strip()
    if user == "":
        return today_str

    if re.match(r"^\d{4}-\d{2}-\d{2}$", user):
        return user
    else:
        print("Ungültiges Format, verwende heutiges Datum.")
        return today_str

# ---------- MENÜ-AKTIONEN ----------

def action_add_grade():
    print("\n--- Note erfassen ---")
    subj_id, subj_name = select_subject()
    grade_value = input_grade()
    grade_date = input_date()
    if grade_exists(subj_id, grade_value, grade_date):
        print("Diese Note für dieses Fach an diesem Datum existiert bereits.\n")
        return
    insert_grade(subj_id, grade_value, grade_date)
    print(f"Note {grade_value} für '{subj_name}' am {grade_date} gespeichert.\n")

def action_show_all_grades():
    print("\n--- Alle Noten ---")
    rows = get_all_grades()
    if not rows:
        print("Noch keine Noten erfasst.\n")
        return
    table = [
        [subj_name, f"{grade:.1f}", gdate]
        for subj_name, grade, gdate in rows
    ]
    print(tabulate(table, headers=["Fach", "Note", "Datum"], tablefmt="github"))
    print()

def action_show_subject_grades():
    print("\n--- Noten pro Fach ---")
    subj_id, subj_name = select_subject()
    rows = get_grades_by_subject(subj_id)
    if not rows:
        print(f"Für '{subj_name}' sind noch keine Noten erfasst.\n")
        return
    print(f"Noten für '{subj_name}':")
    for grade, gdate in rows:
        print(f"- {color_grade(grade)} am {gdate}")
    avg = get_average_by_subject(subj_id)
    if avg is not None:
        print(f"Durchschnitt für {subj_name}: {color_grade(avg)}\n")

def action_show_overall_average():
    print("\n--- Gesamtdurchschnitt ---")
    avg = get_overall_average()
    if avg is None:
        print("Noch keine Noten erfasst.\n")
    else:
        print(f"Gesamtdurchschnitt aller Fächer: {color_grade(avg)}\n")

def export_csv(path: str | None = None):
    if path is None:
        ts = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
        path = os.path.join(BASE_DIR, f"noten_export_{ts}.csv")
    rows = get_all_grades()
    if not rows:
        print("Keine Noten zum Exportieren.")
        return
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, delimiter=";")
        writer.writerow(["Fach", "Note", "Datum"])
        writer.writerows(rows)
    print(f"Exportiert nach {path}")

def export_json(path: str | None = None):
    if path is None:
        ts = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
        path = os.path.join(BASE_DIR, f"noten_export_{ts}.json")
    rows = get_all_grades()
    if not rows:
        print("Keine Noten zum Exportieren.")
        return
    data = [
        {"subject": s, "grade": g, "date": d}
        for s, g, d in rows
    ]
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"Exportiert nach {path}")

def export_pdf(path: str | None = None):
    if path is None:
        ts = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
        path = os.path.join(BASE_DIR, f"notenbericht_{ts}.pdf")
    rows = get_all_grades()
    if not rows:
        print("Keine Noten zum Exportieren.")
        return

    # PDF Grundlayout
    pdf = FPDF()
    pdf.add_page()

    # Titel
    pdf.set_font("Arial", "B", 18)
    pdf.cell(0, 12, "Notenbericht", ln=True, align="C")

    # Datum / Meta feiner
    pdf.set_font("Arial", "", 10)
    pdf.set_text_color(80, 80, 80)
    pdf.ln(3)
    pdf.cell(0, 6, f"Erstellt am: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}", ln=True, align="C")
    pdf.ln(5)

    # dünne Trennlinie
    pdf.set_draw_color(180, 180, 180)
    pdf.set_line_width(0.3)
    pdf.line(10, pdf.get_y(), 200, pdf.get_y())
    pdf.ln(6)

    # Tabellenkopf
    pdf.set_text_color(0, 0, 0)
    pdf.set_font("Arial", "B", 12)
    pdf.set_draw_color(0, 0, 0)
    pdf.set_line_width(0.4)

    col_widths = [95, 25, 50]  # Fach, Note, Datum
    headers = ["Fach", "Note", "Datum"]

    # Hellgrauer Hintergrund für Header
    pdf.set_fill_color(230, 230, 230)
    for width, header in zip(col_widths, headers):
        pdf.cell(width, 8, header, border=1, align="C", fill=True)
    pdf.ln(8)

    # Tabellenzeilen mit farbiger Notenspalte
    pdf.set_font("Arial", "", 12)
    for subj_name, grade, gdate in rows:
        # Fach (weiß)
        pdf.set_fill_color(255, 255, 255)
        pdf.cell(col_widths[0], 8, subj_name, border=1, fill=True)

        # Note je nach Wert farbig hinterlegen
        if grade >= 5.0:
            pdf.set_fill_color(200, 255, 200)  # grünlich
        elif grade >= 4.0:
            pdf.set_fill_color(255, 255, 200)  # gelblich
        else:
            pdf.set_fill_color(255, 200, 200)  # rötlich
        pdf.cell(col_widths[1], 8, f"{grade:.1f}", border=1, align="C", fill=True)

        # Datum (weiß)
        pdf.set_fill_color(255, 255, 255)
        pdf.cell(col_widths[2], 8, gdate, border=1, align="C", fill=True)
        pdf.ln(8)

    # Gesamtdurchschnitt unten
    overall = get_overall_average()
    if overall is not None:
        pdf.ln(8)
        pdf.set_font("Arial", "B", 13)
        pdf.set_text_color(40, 40, 40)
        pdf.cell(0, 10, f"Gesamtdurchschnitt aller Fächer: {overall:.2f}", ln=True, align="R")

    pdf.output(path)
    print(f"PDF erstellt: {path}")

# ---------- HAUPTMENÜ / KONTROLLSTRUKTUREN ----------

def main_menu():
    init_db()
    while True:  # while-Schleife als Hauptkontrollstruktur
        print("====== Notenomat ======")
        print("1) Note erfassen")
        print("2) Alle Noten anzeigen")
        print("3) Noten nach Fach anzeigen")
        print("4) Gesamtdurchschnitt anzeigen")
        print("5) Exportiere Noten als CSV")
        print("6) Exportiere Noten als JSON")
        print("7) Exportiere Noten als PDF")
        print("8) Beenden")
        choice = input("Auswahl: ").strip()

        if choice == "1":
            action_add_grade()
        elif choice == "2":
            action_show_all_grades()
        elif choice == "3":
            action_show_subject_grades()
        elif choice == "4":
            action_show_overall_average()
        elif choice == "5":
            export_csv()
        elif choice == "6":
            export_json()
        elif choice == "7":
            export_pdf()
        elif choice == "8":
            print("Programm beendet.")
            break
        else:
            print("Ungültige Auswahl, bitte erneut versuchen.\n")

if __name__ == "__main__":
    main_menu()
