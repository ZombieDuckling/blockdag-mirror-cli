"""
A simple Tkinter GUI front-end for the BlockDAG mirror program.

This graphical interface lets you run the mirror job on demand and view
logs from previous runs.  It spawns the mirroring process in a background
thread so the UI remains responsive.
"""
import tkinter as tk
from tkinter import scrolledtext, messagebox
import threading
import logging
import logging.config
from pathlib import Path

from .mirror import run_mirror


logger = logging.getLogger(__name__)


class MirrorGUI(tk.Tk):
    """Main application window."""

    def __init__(self):
        super().__init__()
        self.title("BlockDAG Mirror")
        self.geometry("700x500")
        self.status_var = tk.StringVar(value="Idle")

        # Buttons
        tk.Button(self, text="Run Mirror", command=self.run_mirror_thread).pack(pady=5)
        tk.Button(self, text="View Logs", command=self.view_logs).pack(pady=5)

        # Status label
        tk.Label(self, textvariable=self.status_var).pack(pady=5)

        # Log area
        self.log_area = scrolledtext.ScrolledText(self, height=20)
        self.log_area.pack(fill="both", expand=True, padx=5, pady=5)

    def update_status(self, msg: str):
        """Update the status label and append to the log area."""
        self.status_var.set(msg)
        self.log_area.insert(tk.END, msg + "\n")
        self.log_area.see(tk.END)

    def run_mirror_thread(self):
        threading.Thread(target=self.run_mirror, daemon=True).start()

    def run_mirror(self):
        try:
            self.update_status("Running mirror job…")
            run_mirror()
            self.update_status("Mirror job completed successfully.")
        except Exception as e:
            logger.exception("Mirror run failed")
            self.update_status(f"Mirror run failed: {e}")
            messagebox.showerror("Error", str(e))

    def view_logs(self):
        """Open a window showing the current log output."""
        log_file = Path("logs/mirror.log")
        if not log_file.exists():
            messagebox.showinfo("Logs", "No log file found yet.")
            return
        try:
            content = log_file.read_text(encoding="utf-8")
        except Exception as e:
            messagebox.showerror("Error", f"Failed to read log file: {e}")
            return
        log_win = tk.Toplevel(self)
        log_win.title("Log Output")
        text_widget = scrolledtext.ScrolledText(log_win, wrap=tk.WORD)
        text_widget.insert(tk.END, content)
        text_widget.pack(fill="both", expand=True)


if __name__ == "__main__":
    # Load logging configuration if present
    if Path("logging.conf").exists():
        logging.config.fileConfig("logging.conf")
    app = MirrorGUI()
    app.mainloop()
