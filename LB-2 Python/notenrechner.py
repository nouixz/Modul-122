import sqlite3
import re
import os
from datetime import date

# ---------- KONFIGURATION ----------

# Ordner, in dem dieses Skript liegt
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# Datenbankdatei IM GLEICHEN ORDNER wie notenrechner.py
DB_NAME = os.path.join(BASE_DIR, "noten.db")

# Vorgegebene Fächer
SUBJECTS = [
    "Fachenglisch",
    "Gesellschaft",
    "Sport",
    "Sprache und Kommunikation",
    "122 Abläufe mit Scriptsprache"
]

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
    insert_grade(subj_id, grade_value, grade_date)
    print(f"Note {grade_value} für '{subj_name}' am {grade_date} gespeichert.\n")

def action_show_all_grades():
    print("\n--- Alle Noten ---")
    rows = get_all_grades()
    if not rows:
        print("Noch keine Noten erfasst.\n")
        return
    for subj_name, grade, gdate in rows:
        print(f"{subj_name:30} | {grade:.1f} | {gdate}")
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
        print(f"- {grade:.1f} am {gdate}")
    avg = get_average_by_subject(subj_id)
    if avg is not None:
        print(f"Durchschnitt für {subj_name}: {avg:.2f}\n")

def action_show_overall_average():
    print("\n--- Gesamtdurchschnitt ---")
    avg = get_overall_average()
    if avg is None:
        print("Noch keine Noten erfasst.\n")
    else:
        print(f"Gesamtdurchschnitt aller Fächer: {avg:.2f}\n")

# ---------- HAUPTMENÜ / KONTROLLSTRUKTUREN ----------

def main_menu():
    init_db()
    while True:  # while-Schleife als Hauptkontrollstruktur
        print("====== Notenrechner ======")
        print("1) Note erfassen")
        print("2) Alle Noten anzeigen")
        print("3) Noten nach Fach anzeigen")
        print("4) Gesamtdurchschnitt anzeigen")
        print("5) Beenden")
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
            print("Programm beendet.")
            break
        else:
            print("Ungültige Auswahl, bitte erneut versuchen.\n")

if __name__ == "__main__":
    main_menu()
