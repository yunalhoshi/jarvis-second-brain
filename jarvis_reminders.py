"""Reminders for Jarvis: "hatırlat / not al" saves a line, "bugün ne yapmam lazım" reads them back.

Reminders live in the vault note Notes/Hatırlatmalar.md, one line each:
    - [ ] 2026-10-12 16:00 | Pazartesi saat 4'te birisine dönmem lazım
    - [ ] tarihsiz | Ehliyeti yenile
A finished one is ticked by hand or by Claude: "- [x] ...".
Claude copies dated reminders to Google Calendar and then adds " | takvim" to the end of the line.
"""
import datetime
import os
import re
import threading

ROOT = os.path.dirname(os.path.abspath(__file__))
REMINDERS_FILE = os.path.join(ROOT, "Notes", "Hatırlatmalar.md")
CALENDAR_FILE = os.path.join(ROOT, "Notes", "Takvim.md")
REMINDERS_NOTE = "Hatırlatmalar"
CALENDAR_NOTE = "Takvim"
UNDATED = "tarihsiz"

WEEKDAYS = ["pazartesi", "salı", "çarşamba", "perşembe", "cuma", "cumartesi", "pazar"]
MONTHS = ["ocak", "şubat", "mart", "nisan", "mayıs", "haziran",
          "temmuz", "ağustos", "eylül", "ekim", "kasım", "aralık"]

SAVE_WORDS = re.compile(r"hatırlat(?!ma)|not al|not et|not düş|kaydet|unutma(?!\w)|aklında tut|aklına yaz")
TODO_WORDS = re.compile(r"ne yap|yapmam (lazım|gerek)|yapılacak|hatırlatma|ajanda")
PLAN_WORDS = re.compile(r"plan|program|ne var|neler var|işim var")
# Words that only carry the command, removed from the saved text
COMMAND_TAIL = re.compile(
    r"[\s,.]*(bunu |şunu |bana |lütfen )*(hatırlat\w*( mısın| misin)?|not al\w*( mısın| misin)?|not et\w*|not düş\w*|"
    r"kaydet\w*( misin)?|unutma|aklında tut\w*|aklına yaz\w*)[\s.!?]*$")
COMMAND_HEAD = re.compile(
    r"^(jarvis[\s,]*)?((bana |şunu |bunu |lütfen )*(hatırlat\w*|not al\w*|not et\w*|kaydet\w*|unutma|aklında tut\w*)"
    r"( ki| şunu| bunu)?[\s,:]+)")
# A line may end in " | takvim": the mark that it has been copied to Google Calendar (see CLAUDE.md)
LINE = re.compile(r"^- \[( |x|X)\] (\d{4}-\d{2}-\d{2}|tarihsiz)(?: (\d{2}:\d{2}))? \| (.+?)(?: \| takvim)?\s*$")
_lock = threading.Lock()


def tr_lower(text):
    """Lowercase the Turkish way (I -> ı, İ -> i)."""
    return text.replace("İ", "i").replace("I", "ı").lower()


def tr_title(word):
    return (word[:1].replace("i", "İ").upper() + word[1:]) if word else word


def day_label(day):
    return f"{tr_title(WEEKDAYS[day.weekday()])} {day.day} {tr_title(MONTHS[day.month - 1])}"


def find_day(text, today):
    """The day a sentence talks about (bugün, yarın, a weekday, '15 Ekim'), or None."""
    if re.search(r"\bbugün", text):
        return today
    if re.search(r"öbür gün|yarından sonra", text):
        return today + datetime.timedelta(days=2)
    if re.search(r"\byarın", text):
        return today + datetime.timedelta(days=1)
    match = re.search(r"\b(\d{1,2})\s+(" + "|".join(MONTHS) + r")", text)
    if match:
        try:
            day = datetime.date(today.year, MONTHS.index(match.group(2)) + 1, int(match.group(1)))
            return day if day >= today else day.replace(year=today.year + 1)
        except ValueError:
            pass
    for name in sorted(WEEKDAYS, key=len, reverse=True):          # "pazartesi" before "pazar"
        if re.search(r"\b" + name, text):
            return today + datetime.timedelta(days=(WEEKDAYS.index(name) - today.weekday()) % 7)
    return None


def find_time(text):
    """The clock time in a sentence as 'HH:MM', or None. 'saat 4' with no 'sabah' is taken as 16:00."""
    match = (re.search(r"saat\s*(\d{1,2})(?:[:.](\d{2}))?(\s*buçuk)?", text)                      # saat 4, saat 16:30
             or re.search(r"\b(\d{1,2})[:.](\d{2})()\b", text)                                    # 16:30
             or re.search(r"(?:sabah|akşam|gece|öğlen|ikindi|öğleden sonra)\s*(\d{1,2})(?:[:.](\d{2}))?(\s*buçuk)?", text)
             or re.search(r"\b(\d{1,2})()()['’](?:de|da|te|ta)\b", text))                          # 8'de
    if not match:
        return None
    hour = int(match.group(1))
    minute = 30 if match.group(3) else int(match.group(2) or 0)
    if hour > 23 or minute > 59:
        return None
    if "sabah" not in text and hour < 12:
        afternoon = re.search(r"akşam|öğleden sonra|ikindi", text) or ("gece" in text and hour >= 8)
        if afternoon or 1 <= hour <= 7:
            hour += 12
    return f"{hour:02d}:{minute:02d}"


def intent(question):
    """'save', 'list' or None (None: an ordinary question for Claude or the note search)."""
    text = tr_lower(question)
    if SAVE_WORDS.search(text) and "hatırlatma" not in text:
        return "save"
    if TODO_WORDS.search(text):
        return "list"
    if PLAN_WORDS.search(text) and find_day(text, datetime.date.today()):
        return "list"
    return None


def read_reminders():
    items = []
    try:
        with open(REMINDERS_FILE, encoding="utf-8-sig") as handle:
            for line in handle:
                match = LINE.match(line.strip())
                if match:
                    items.append({"done": match.group(1) != " ", "day": match.group(2),
                                  "time": match.group(3) or "", "text": match.group(4)})
    except OSError:
        pass
    return items


def read_calendar(day):
    """Events of one day from the calendar copy in Notes/Takvim.md."""
    wanted = tr_lower(day_label(day))
    events = []
    try:
        with open(CALENDAR_FILE, encoding="utf-8-sig") as handle:
            for line in handle:
                cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
                if line.lstrip().startswith("|") and len(cells) >= 3 and tr_lower(cells[0]) == wanted:
                    events.append(cells[1] + " " + cells[2].replace("[[", "").replace("]]", ""))
    except OSError:
        pass
    return events


def save(question, now=None):
    now = now or datetime.datetime.now()
    text = tr_lower(question)
    day = find_day(text, now.date())
    time = find_time(text)
    if time and not day:                                           # "saat 5'te ara" with no day: today, or tomorrow if past
        day = now.date() if time > now.strftime("%H:%M") else now.date() + datetime.timedelta(days=1)

    # Keep what was said, minus the command words at either end ("... hatırlatır mısın", "not al: ...")
    body = question.strip()
    tail = COMMAND_TAIL.search(tr_lower(body))
    if tail:
        body = body[:tail.start()]
    head = COMMAND_HEAD.match(tr_lower(body))
    if head:
        body = body[head.end():]
    body = body.strip(" ,.:;") or question.strip()
    body = ("İ" if body[0] == "i" else body[0].upper()) + body[1:]
    body = body.replace("|", "/").replace("\n", " ")

    stamp = (day.isoformat() if day else UNDATED) + (f" {time}" if time and day else "")
    with _lock:
        if not os.path.exists(REMINDERS_FILE):
            with open(REMINDERS_FILE, "w", encoding="utf-8") as handle:
                handle.write(
                    "---\ntitle: Hatırlatmalar\ntype: note\ntags: [hatırlatma, yapılacak]\n"
                    f"created: {now.date().isoformat()}\nhub: Personal\n---\n\n# Hatırlatmalar\n\n"
                    "Jarvis'e \"hatırlat\" ya da \"not al\" dediğimde buraya eklenir.\n\n## Liste\n")
        with open(REMINDERS_FILE, "r+", encoding="utf-8") as handle:
            content = handle.read()
            handle.write(("" if content.endswith("\n") else "\n") + f"- [ ] {stamp} | {body}\n")

    when = (day_label(day) + (f" saat {time}" if time else "")) if day else "tarihsiz"
    return {"answer": f"Kaydettim. {when}: {body}", "notes": [REMINDERS_NOTE], "engine": "Hatırlatma kaydedildi"}


def list_day(question, now=None):
    now = now or datetime.datetime.now()
    today = now.date()
    day = find_day(tr_lower(question), today) or today
    name = "Bugün" if day == today else "Yarın" if day == today + datetime.timedelta(days=1) else day_label(day)
    open_items = [item for item in read_reminders() if not item["done"]]
    dated = sorted((item for item in open_items if item["day"] == day.isoformat()), key=lambda item: item["time"] or "99")
    undated = [item for item in open_items if item["day"] == UNDATED] if day == today else []
    overdue = [item for item in open_items if item["day"] != UNDATED and item["day"] < today.isoformat()] if day == today else []
    events = read_calendar(day)

    parts, notes = [], []
    if dated:
        parts.append("Hatırlatmaların: " + "; ".join((item["time"] + " " if item["time"] else "") + item["text"] for item in dated) + ".")
    if events:
        parts.append("Takvimde: " + "; ".join(events) + ".")
        notes.append(CALENDAR_NOTE)
    if undated:
        parts.append("Tarihsiz notların: " + "; ".join(item["text"] for item in undated) + ".")
    if overdue:
        parts.append("Geçmişten kalanlar: " + "; ".join(item["text"] for item in overdue) + ".")
    if dated or undated or overdue:
        notes.insert(0, REMINDERS_NOTE)
    head = name if name == day_label(day) else f"{name}, {day_label(day)}"
    answer = f"{head}. " + " ".join(parts) if parts else f"{head} için kayıtlı bir şey yok."
    return {"answer": answer, "notes": notes, "engine": "Hatırlatmalar ve takvim"}


def handle(question):
    """Answer dict for a reminder command or question, or None when it is neither."""
    kind = intent(question)
    if kind == "save":
        return save(question)
    if kind == "list":
        return list_day(question)
    return None
