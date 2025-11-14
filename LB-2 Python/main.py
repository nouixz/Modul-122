#!/usr/bin/env python3
"""
Passwort-Manager (GUI) mit SQLite und Regex-Validierung

Funktionen:
- GUI mit tkinter (Service, Benutzername/E-Mail, Passwort-Hinweis)
- SQLite3-Datenbank: Tabelle erstellen (CREATE TABLE IF NOT EXISTS), INSERT, SELECT mit Filter
- Regex-Validierung für E-Mail (einfaches Muster)
- DB-Pfad via Umgebungsvariable DB_PATH konfigurierbar (Standard: ./data/passwords.db)

Hinweis zu Docker/GUI:
Die GUI kann in einem Docker-Container nur mit X11-Weiterleitung angezeigt werden (Linux: /tmp/.X11-unix mounten; macOS: XQuartz).
Für die Bewertung stehen Struktur und Technik im Vordergrund; lokal starten ist am einfachsten.
"""

from __future__ import annotations

import os
import re
import sqlite3
from contextlib import closing
from datetime import datetime
import tkinter as tk
from tkinter import ttk, messagebox


# ----------------------------- Konfiguration ------------------------------
APP_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_DATA_DIR = os.path.join(APP_DIR, "data")
os.makedirs(DEFAULT_DATA_DIR, exist_ok=True)

DB_PATH = os.environ.get("DB_PATH", os.path.join(DEFAULT_DATA_DIR, "passwords.db"))


# ----------------------------- Datenbank-Logik ----------------------------
def get_conn() -> sqlite3.Connection:
	return sqlite3.connect(DB_PATH)


def init_db() -> None:
	with closing(get_conn()) as conn, conn:  # auto-commit context
		conn.execute(
			"""
			CREATE TABLE IF NOT EXISTS entries (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
				service TEXT NOT NULL,
				username TEXT NOT NULL,
				hint TEXT,
				created_at TEXT NOT NULL
			)
			"""
		)


def insert_entry(service: str, username: str, hint: str | None) -> None:
	now = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
	with closing(get_conn()) as conn, conn:
		conn.execute(
			"INSERT INTO entries(service, username, hint, created_at) VALUES (?, ?, ?, ?)",
			(service, username, hint or "", now),
		)


def query_entries(search: str | None = None) -> list[tuple]:
	with closing(get_conn()) as conn:
		if search and search.strip():
			like = f"%{search.strip()}%"
			cur = conn.execute(
				"SELECT id, service, username, hint, created_at FROM entries WHERE service LIKE ? ORDER BY created_at DESC",
				(like,),
			)
		else:
			cur = conn.execute(
				"SELECT id, service, username, hint, created_at FROM entries ORDER BY created_at DESC"
			)
		return list(cur.fetchall())


# ----------------------------- Validierung --------------------------------
EMAIL_REGEX = re.compile(r"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$")


def is_valid_email(value: str) -> bool:
	return EMAIL_REGEX.match(value) is not None


# ----------------------------- GUI ----------------------------------------
class PasswordManagerApp(tk.Tk):
	def __init__(self) -> None:
		super().__init__()
		self.title("Passwort-Manager")
		self.geometry("760x520")
		self.minsize(680, 420)
		self._build_ui()
		self._load_entries()

	def _build_ui(self) -> None:
		# Eingabeformular
		frm_form = ttk.LabelFrame(self, text="Neuer Eintrag")
		frm_form.pack(side=tk.TOP, fill=tk.X, padx=12, pady=8)

		ttk.Label(frm_form, text="Dienstname:").grid(row=0, column=0, sticky=tk.W, padx=8, pady=6)
		self.var_service = tk.StringVar()
		self.ent_service = ttk.Entry(frm_form, textvariable=self.var_service, width=40)
		self.ent_service.grid(row=0, column=1, sticky=tk.W, padx=8, pady=6)

		ttk.Label(frm_form, text="Benutzername/E-Mail:").grid(row=1, column=0, sticky=tk.W, padx=8, pady=6)
		self.var_username = tk.StringVar()
		self.ent_username = ttk.Entry(frm_form, textvariable=self.var_username, width=40)
		self.ent_username.grid(row=1, column=1, sticky=tk.W, padx=8, pady=6)

		ttk.Label(frm_form, text="Passwort-Hinweis:").grid(row=2, column=0, sticky=tk.W, padx=8, pady=6)
		self.var_hint = tk.StringVar()
		self.ent_hint = ttk.Entry(frm_form, textvariable=self.var_hint, width=40)
		self.ent_hint.grid(row=2, column=1, sticky=tk.W, padx=8, pady=6)

		frm_buttons = ttk.Frame(frm_form)
		frm_buttons.grid(row=0, column=2, rowspan=3, sticky=tk.NE, padx=8, pady=6)

		self.btn_save = ttk.Button(frm_buttons, text="Eintrag speichern", command=self._on_save)
		self.btn_save.grid(row=0, column=0, sticky=tk.EW, padx=4, pady=4)

		self.btn_clear = ttk.Button(frm_buttons, text="Felder leeren", command=self._on_clear)
		self.btn_clear.grid(row=1, column=0, sticky=tk.EW, padx=4, pady=4)

		# Suche/Filter
		frm_filter = ttk.LabelFrame(self, text="Suche")
		frm_filter.pack(side=tk.TOP, fill=tk.X, padx=12, pady=4)

		ttk.Label(frm_filter, text="Dienst enthält:").grid(row=0, column=0, sticky=tk.W, padx=8, pady=6)
		self.var_search = tk.StringVar()
		ent_search = ttk.Entry(frm_filter, textvariable=self.var_search, width=40)
		ent_search.grid(row=0, column=1, sticky=tk.W, padx=8, pady=6)

		btn_refresh = ttk.Button(frm_filter, text="Aktualisieren", command=self._load_entries)
		btn_refresh.grid(row=0, column=2, sticky=tk.W, padx=8, pady=6)

		# Liste
		frm_list = ttk.Frame(self)
		frm_list.pack(side=tk.TOP, fill=tk.BOTH, expand=True, padx=12, pady=8)

		columns = ("service", "username", "hint", "created_at")
		self.tree = ttk.Treeview(frm_list, columns=columns, show="headings", height=10)
		self.tree.heading("service", text="Dienst")
		self.tree.heading("username", text="Benutzer/E-Mail")
		self.tree.heading("hint", text="Hinweis")
		self.tree.heading("created_at", text="Erstellt (UTC)")
		self.tree.column("service", width=180, anchor=tk.W)
		self.tree.column("username", width=200, anchor=tk.W)
		self.tree.column("hint", width=220, anchor=tk.W)
		self.tree.column("created_at", width=120, anchor=tk.W)

		vsb = ttk.Scrollbar(frm_list, orient="vertical", command=self.tree.yview)
		self.tree.configure(yscroll=vsb.set)
		self.tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
		vsb.pack(side=tk.RIGHT, fill=tk.Y)

		# Statusleiste
		self.var_status = tk.StringVar(value=f"Datenbank: {DB_PATH}")
		lbl_status = ttk.Label(self, textvariable=self.var_status, anchor=tk.W)
		lbl_status.pack(side=tk.BOTTOM, fill=tk.X, padx=12, pady=4)

		# Events
		self.bind("<Return>", lambda _e: self._on_save())

	# ------------------------- Event-Handler ------------------------------
	def _on_clear(self) -> None:
		self.var_service.set("")
		self.var_username.set("")
		self.var_hint.set("")
		self.ent_service.focus_set()
		self.var_status.set("Felder geleert.")

	def _on_save(self) -> None:
		service = self.var_service.get().strip()
		username = self.var_username.get().strip()
		hint = self.var_hint.get().strip()

		# Pflichtfelder prüfen
		if not service:
			messagebox.showerror("Fehler", "Dienstname ist erforderlich.")
			return
		if not username:
			messagebox.showerror("Fehler", "Benutzername/E-Mail ist erforderlich.")
			return

		# E-Mail-Validierung: Wenn ein '@' enthalten ist, muss Regex passen
		if "@" in username and not is_valid_email(username):
			messagebox.showerror("Fehler", "Die E-Mail-Adresse ist ungültig.")
			return

		try:
			insert_entry(service, username, hint)
		except Exception as ex:
			messagebox.showerror("DB-Fehler", f"Eintrag konnte nicht gespeichert werden:\n{ex}")
			return

		self._load_entries()
		self._on_clear()
		self.var_status.set("Eintrag gespeichert.")

	def _load_entries(self) -> None:
		search = self.var_search.get().strip() if hasattr(self, "var_search") else ""
		try:
			rows = query_entries(search)
		except Exception as ex:
			messagebox.showerror("DB-Fehler", f"Einträge konnten nicht geladen werden:\n{ex}")
			return

		# Liste neu füllen
		for item in self.tree.get_children():
			self.tree.delete(item)
		for _id, service, username, hint, created_at in rows:
			self.tree.insert("", tk.END, values=(service, username, hint, created_at))
		self.var_status.set(f"Einträge: {len(rows)} | DB: {DB_PATH}")


def main() -> None:
	init_db()
	app = PasswordManagerApp()
	app.mainloop()


if __name__ == "__main__":
	main()

