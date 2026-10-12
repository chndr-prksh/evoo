#!/usr/bin/env python3
"""Builds the training and test data for Evoo's tool-calling model (FunctionGemma 270M).

    python3 Tools/build_dataset.py            # writes Tools/data/{train,valid,test}.jsonl and Tools/prefix.txt

Every example is something a person might say, and the tool call(s) Evoo should make. Phrasings are written out
by hand per tool (many ways to ask for the same thing), filled with different apps, queries, names and numbers,
and then roughened the way speech recognition does (no capitals, stray commas, "um", spelled-out numbers).

The TEST set uses different phrasings and different apps/queries/names from the training set, so a good score
means the model understood the request — not that it memorised a sentence.
"""
import json, sys, random, re, pathlib

ROOT = pathlib.Path(__file__).resolve().parent
TOOLS = json.loads((ROOT / "tools.json").read_text())["tools"]
E = "<escape>"

# ── The model's own format (see the chat template of google/functiongemma-270m-it) ──────────────────────────

def declaration(tool):
    props = []
    for key in sorted(tool["params"]):
        p = tool["params"][key]
        enum = ",enum:[" + ",".join(E + v + E for v in p["enum"]) + "]" if p.get("enum") else ""
        props.append(f"{key}:{{description:{E}{p['description']}{E}{enum},type:{E}{p['type'].upper()}{E}}}")
    params = ""
    if props: params += "properties:{" + ",".join(props) + "},"
    if tool["required"]: params += "required:[" + ",".join(E + r + E for r in tool["required"]) + "],"
    params += f"type:{E}OBJECT{E}}}"
    return f"<start_function_declaration>declaration:{tool['name']}{{description:{E}{tool['description']}{E},parameters:{{{params}}}<end_function_declaration>"

def prefix():
    """What every prompt starts with. The fine-tuned model has learned Evoo's tools, so it only needs their names
    (~150 tokens). `--full` writes the complete declarations instead (~2,000 tokens: what an untrained model needs,
    but twenty times slower to train on and to load)."""
    if "--full" in sys.argv:
        return ("<start_of_turn>developer\nYou are a model that can do function calling with the following functions"
                + "".join(declaration(t) for t in TOOLS) + "<end_of_turn>\n")
    return ("<start_of_turn>developer\nYou are a model that can do function calling with the following functions: "
            + ", ".join(t["name"] for t in TOOLS) + "<end_of_turn>\n")

def user_turn(text):
    return f"<start_of_turn>user\n{text}<end_of_turn>\n<start_of_turn>model\n"

def call_text(calls):
    out = ""
    for name, args in calls:
        body = ",".join(f"{k}:{v if isinstance(v, int) else E + str(v) + E}" for k, v in sorted(args.items()))
        out += f"<start_function_call>call:{name}{{{body}}}<end_function_call>"
    return out + "<start_function_response>"

# ── Things to fill the phrasings with. "TEST" values never appear in training. ──────────────────────────────

APPS = ["Chrome", "Safari", "Slack", "Notes", "Mail", "Calendar", "Spotify", "Zoom", "Word", "Excel", "PowerPoint", "Finder",
        "Terminal", "Messages", "WhatsApp", "Notion", "Figma", "VS Code", "Photos", "Music", "Maps", "Preview", "Outlook",
        "Teams", "Discord", "Telegram", "Keynote", "Pages", "Numbers", "Xcode", "Cursor", "Claude", "ChatGPT",
        "System Settings", "Calculator", "Reminders", "FaceTime", "Obsidian", "Linear", "Arc", "Firefox", "Edge"]
APPS_TEST = ["Brave", "Signal", "Postman", "Docker", "TextEdit", "Activity Monitor", "Books", "Podcasts", "Notes", "Chrome", "Slack"]
SITES = ["Gmail", "YouTube", "GitHub", "LinkedIn", "Twitter", "Reddit", "Amazon", "Netflix", "Google Docs", "Google Drive",
         "Google Calendar", "Wikipedia", "Hacker News", "Stack Overflow", "Canva", "Instagram", "Facebook",
         "github.com", "nytimes.com", "apple.com", "bbc.com", "openai.com", "notion.so"]
SITES_TEST = ["Google Maps", "Pinterest", "Coursera", "theverge.com", "anthropic.com", "Gmail", "YouTube"]
QUERIES = ["flights to Delhi", "best laptops for students", "how to make sourdough bread", "weather in London tomorrow",
           "python list comprehension", "cheap hotels in Goa", "the capital of Australia", "lo-fi study music",
           "how tides work", "noise cancelling headphones", "latest iPhone review", "product manager interview questions",
           "vegetarian dinner recipes", "how to tie a tie", "stock price of Nvidia", "train from Mumbai to Pune",
           "standing desk", "symptoms of dehydration", "react useEffect cleanup", "movies releasing this week",
           "how to write a cover letter", "pizza near me", "the history of the internet", "kubernetes ingress tutorial",
           "second hand bicycles", "world cup schedule", "how to learn Spanish fast", "air fryer chicken wings"]
QUERIES_TEST = ["restaurants open now", "difference between llm and slm", "running shoes for flat feet", "visa requirements for Japan",
                "how to fix a flat tire", "best sci-fi books", "swift async await example", "apartments in Bangalore"]
FILES = ["tax return", "invoice from March", "resume", "budget spreadsheet", "meeting notes", "passport scan",
         "lease agreement", "quarterly report", "presentation deck", "offer letter", "project plan", "bank statement",
         "flight tickets", "thesis draft", "design mockups"]
FILES_TEST = ["insurance policy", "vaccination certificate", "product roadmap", "recommendation letter"]
PEOPLE = ["Priya", "Rahul", "John", "Mike", "Divya", "Aarav", "Sarah", "Raj", "Emma", "David", "Neha", "Tom", "my manager", "the team", "mom"]
PEOPLE_TEST = ["Ananya", "Carlos", "Dr. Mehta", "the landlord"]
TASKS = ["call Raj", "buy milk", "submit the report", "pay the electricity bill", "book the dentist", "send the invoice",
         "pick up the laundry", "renew my passport", "water the plants", "email the professor", "take my medicine",
         "review the pull request", "order groceries", "cancel the subscription", "wish Divya happy birthday"]
TASKS_TEST = ["return the library books", "update my resume", "check the oven", "file the expense report"]
WHENS = ["tomorrow at 5", "tomorrow morning", "at 6 pm", "on Friday", "next Monday at 10 am", "tonight", "in an hour",
         "on Saturday at noon", "this evening", "at 9 tomorrow", "next week", "in 20 minutes", "on the 21st at 3 pm"]
WHENS_TEST = ["day after tomorrow at 4", "on Wednesday afternoon", "at half past seven", "in two hours"]
EVENTS = ["team standup", "lunch with Priya", "dentist appointment", "project review", "one on one with my manager",
          "gym session", "design critique", "flight to Mumbai", "parent teacher meeting", "interview with Kaggle"]
EVENTS_TEST = ["coffee with Carlos", "quarterly planning", "yoga class"]
NOTES = ["the wifi password is on the fridge", "idea for the app, voice search inside notes", "parking spot is B 42",
         "ask the landlord about the heater", "book recommendation, Thinking Fast and Slow", "the client prefers morning calls"]
NOTES_TEST = ["the spare key is with the neighbour", "try the pasta place on fifth street"]
BUTTONS = ["Send", "Submit", "Cancel", "Save", "Reply", "Reply all", "Next", "Continue", "Done", "Sign in", "Download",
           "Add to cart", "Accept", "Close", "Forward", "Share", "Join", "Post", "Search", "Skip"]
BUTTONS_TEST = ["Checkout", "Publish", "Not now", "Create account"]
PLACES = ["the airport", "Central Park", "the nearest pharmacy", "MG Road Bangalore", "my office", "Stanford University",
          "the train station", "Connaught Place", "the nearest petrol pump", "Times Square"]
PLACES_TEST = ["the Golden Gate Bridge", "India Gate", "the closest hospital"]
LANGS = ["Spanish", "French", "Hindi", "German", "Japanese", "Italian", "Portuguese", "Tamil", "Mandarin", "Arabic"]
LANGS_TEST = ["Korean", "Bengali", "Dutch"]
PHRASES = ["good morning", "thank you very much", "where is the station", "how much does this cost", "I am running late",
           "see you tomorrow", "can I have the bill please", "nice to meet you"]
PHRASES_TEST = ["happy birthday", "I don't understand", "one coffee please"]
REWRITES = ["make this more formal", "shorten this", "fix the grammar", "make it friendlier", "rewrite this as bullet points",
            "make this sound more confident", "simplify this", "translate this to Hindi", "make it more concise",
            "turn this into a polite email", "make this less wordy", "rewrite this for a five year old"]
REWRITES_TEST = ["make this more persuasive", "tighten this up", "translate this to French"]
REPLIES = ["I'll be there at five", "sounds good", "I can't make it today", "thanks, I'll check and get back",
           "yes, let's do Thursday", "please send the updated deck", "I'm running ten minutes late", "congratulations"]
REPLIES_TEST = ["I need one more day", "that works for me", "no thanks"]
SHORTCUTS = ["Morning Routine", "Start Focus", "Log Water", "Daily Standup", "Work Mode", "Good Night"]
SHORTCUTS_TEST = ["Leave Home", "Reading Mode"]
TEXTS = ["hello world", "thanks for your help", "see you at six", "best regards", "I will send it tonight", "on my way"]
TEXTS_TEST = ["talk soon", "happy to help"]
KEYS = [("command shift t", ["command shift T", "cmd shift T"]), ("escape", ["escape", "the escape key"]), ("enter", ["enter", "return", "the enter key"]),
        ("command k", ["command K"]), ("control c", ["control C", "ctrl C"]), ("tab", ["tab", "the tab key"]), ("space", ["space", "space bar", "the space bar"]),
        ("command comma", ["command comma"]), ("f5", ["F5"]), ("option left", ["option left"]), ("command shift 4", ["command shift 4", "command shift four"]),
        ("delete", ["delete", "the delete key"]), ("command option escape", ["command option escape"]), ("down", ["the down arrow", "down arrow"]),
        ("command w", ["command W"]), ("shift tab", ["shift tab"])]
KEYS_TEST = [("command shift n", ["command shift N"]), ("command l", ["command L"]), ("up", ["the up arrow"]), ("control a", ["control A"])]
NUM_WORDS = {5: "five", 10: "ten", 15: "fifteen", 20: "twenty", 25: "twenty five", 30: "thirty", 40: "forty", 45: "forty five", 50: "fifty",
             60: "sixty", 70: "seventy", 75: "seventy five", 80: "eighty", 90: "ninety", 100: "a hundred", 0: "zero", 2: "two", 3: "three", 1: "one",
             8: "eight", 12: "twelve", 35: "thirty five", 55: "fifty five", 65: "sixty five", 85: "eighty five"}

# ── Phrasings. Each entry: (ways to say it, arguments). "{x}" is filled from a list above. ───────────────────

def fixed(tool, key, table):
    """Tools whose argument is one of a few choices: many ways to ask for each choice."""
    return [(phr, tool, {key: value}) for value, phrasings in table.items() for phr in phrasings]

EDIT = {
 "copy": ["copy", "copy that", "copy this", "copy it", "copy the selection", "copy the selected text", "copy this to the clipboard", "grab a copy of this"],
 "cut": ["cut", "cut that", "cut this", "cut the selection", "cut it out", "cut the selected text"],
 "paste": ["paste", "paste that", "paste it", "paste it here", "paste here", "paste the clipboard", "paste what I copied", "drop that in here"],
 "undo": ["undo", "undo that", "undo the last thing", "take that back", "oops undo", "revert that", "undo my last change"],
 "redo": ["redo", "redo that", "redo it", "do that again", "bring that back", "redo the last change"],
 "select_all": ["select all", "select everything", "select all the text", "highlight everything", "select the whole thing", "highlight all of it"],
 "save": ["save", "save this", "save the file", "save it", "save my work", "save the document", "save changes"],
 "find": ["find", "find on page", "find in this page", "open find", "search this page", "search in this document", "find in page"],
 "bold": ["bold", "make it bold", "bold that", "make this bold", "bold the selection", "turn on bold"],
 "italic": ["italic", "italicize that", "make it italic", "make this italic", "italics"],
 "underline": ["underline", "underline that", "underline this", "make it underlined"],
 "print": ["print", "print this", "print the page", "print this document", "send this to the printer", "open the print dialog"],
 "delete_word": ["delete the last word", "delete that word", "remove the last word", "delete word", "erase the last word"],
 "delete_line": ["delete this line", "delete the line", "remove this line", "clear this line", "erase the whole line"],
}
EDIT_TEST = {"copy": ["copy all of that for me", "can you copy what's selected"], "paste": ["stick that in here", "paste what's on the clipboard"],
 "undo": ["I didn't mean that, undo", "go back one step"], "save": ["save what I have", "hit save"], "select_all": ["grab all the text", "select the entire page"],
 "find": ["let me search within this page"], "bold": ["bold this bit"], "print": ["I need a printout of this"], "redo": ["put that change back"],
 "cut": ["cut the highlighted part"], "delete_word": ["get rid of that last word"], "delete_line": ["wipe this line"], "italic": ["put that in italics"], "underline": ["add an underline"]}

BROWSER = {
 "new_tab": ["new tab", "open a new tab", "open new tab", "create a new tab", "give me a new tab", "start a new tab", "new browser tab"],
 "close_tab": ["close tab", "close this tab", "close the tab", "close the current tab", "shut this tab", "get rid of this tab", "kill this tab"],
 "reopen_tab": ["reopen tab", "reopen the last tab", "reopen closed tab", "bring back the tab I closed", "restore the last tab", "undo close tab"],
 "next_tab": ["next tab", "go to the next tab", "switch to the next tab", "move to the tab on the right", "tab right"],
 "previous_tab": ["previous tab", "go to the previous tab", "switch to the last tab", "back one tab", "the tab on the left", "tab left"],
 "back": ["go back", "back", "go back a page", "previous page", "take me back", "back to the last page"],
 "forward": ["go forward", "forward", "go forward a page", "next page", "forward one page"],
 "refresh": ["refresh", "reload", "refresh the page", "reload the page", "reload this", "refresh this page", "hit refresh"],
 "new_window": ["new window", "open a new window", "open new window", "give me a new window", "create a new window"],
 "close_window": ["close window", "close this window", "close the window", "shut this window"],
 "zoom_in": ["zoom in", "make it bigger", "make the text bigger", "zoom in a bit", "increase the zoom", "enlarge the page"],
 "zoom_out": ["zoom out", "make it smaller", "make the text smaller", "zoom out a bit", "decrease the zoom", "shrink the page"],
}
BROWSER_TEST = {"new_tab": ["I need another tab", "pop open a fresh tab"], "close_tab": ["I'm done with this tab", "close out this tab"],
 "reopen_tab": ["I closed that by mistake, bring the tab back"], "next_tab": ["jump to the next tab over"], "previous_tab": ["go to the tab before this one"],
 "back": ["return to the previous page"], "forward": ["go ahead one page"], "refresh": ["load this page again"], "new_window": ["start a fresh window"],
 "close_window": ["I'm finished with this window, close it"], "zoom_in": ["the text is too small, zoom in"], "zoom_out": ["this is too big, zoom out"]}

SCROLL = {"down": ["scroll down", "page down", "scroll down a bit", "go down", "move down the page", "scroll further down", "keep scrolling"],
 "up": ["scroll up", "page up", "scroll up a bit", "go up", "move up the page", "scroll back up"],
 "top": ["scroll to the top", "go to the top", "back to the top", "top of the page", "jump to the top", "take me to the start"],
 "bottom": ["scroll to the bottom", "go to the bottom", "bottom of the page", "jump to the end", "all the way down", "go to the end of the page"]}
SCROLL_TEST = {"down": ["show me more below", "move the page down"], "up": ["go back up a little"], "top": ["all the way back up to the beginning"], "bottom": ["skip to the very end of this page"]}

VOLUME_STEP = {"up": ["volume up", "turn the volume up", "louder", "turn it up", "make it louder", "increase the volume", "raise the volume", "a bit louder", "crank it up", "I can't hear it, turn it up"],
 "down": ["volume down", "turn the volume down", "quieter", "turn it down", "make it quieter", "lower the volume", "reduce the volume", "a bit quieter", "softer", "it's too loud"]}
VOLUME_STEP_TEST = {"up": ["bump the sound up a little", "can you make that louder"], "down": ["bring the sound down a notch", "that's too loud, lower it"]}
MUTE = {"on": ["mute", "mute the sound", "mute the volume", "mute my Mac", "silence it", "turn the sound off", "kill the sound", "mute everything", "go silent"],
 "off": ["unmute", "unmute the sound", "turn the sound back on", "unmute my Mac", "sound on", "bring the sound back"]}
MUTE_TEST = {"on": ["shut the audio off", "no sound please"], "off": ["turn the audio back on"]}
MEDIA = {"play_pause": ["play", "pause", "pause the music", "play the music", "resume", "pause the video", "play pause", "stop the music", "resume playback", "pause this", "continue playing"],
 "next": ["next song", "next track", "skip this song", "skip", "skip this track", "play the next one", "skip to the next song"],
 "previous": ["previous song", "previous track", "go back a song", "last song", "play the previous one", "back a track"]}
MEDIA_TEST = {"play_pause": ["hold the music for a second", "start the music again"], "next": ["I don't like this one, skip it"], "previous": ["play that last song again"]}
BRIGHT = {"up": ["brightness up", "make the screen brighter", "increase the brightness", "brighter", "turn the brightness up", "raise the brightness", "the screen is too dark"],
 "down": ["brightness down", "dim the screen", "make the screen dimmer", "lower the brightness", "decrease the brightness", "dimmer", "the screen is too bright"]}
BRIGHT_TEST = {"up": ["I can barely see the screen, brighten it"], "down": ["tone the screen brightness down"]}
DARK = {"on": ["dark mode", "turn on dark mode", "switch to dark mode", "enable dark mode", "dark mode on", "go dark", "use the dark theme"],
 "off": ["light mode", "turn off dark mode", "switch to light mode", "disable dark mode", "dark mode off", "use the light theme", "go back to light mode"]}
DARK_TEST = {"on": ["make everything dark themed"], "off": ["I want the light appearance back"]}
WINDOW = {"left": ["move this to the left half", "snap this window to the left", "put this on the left", "left half", "window to the left side", "tile this left", "move it to the left"],
 "right": ["move this to the right half", "snap this window to the right", "put this on the right", "right half", "window to the right side", "tile this right", "move it to the right"],
 "top": ["move this to the top half", "put this window on top", "top half", "snap it to the top"],
 "bottom": ["move this to the bottom half", "put this window at the bottom", "bottom half", "snap it to the bottom"],
 "maximize": ["maximize", "maximize this window", "make this bigger", "make the window fill the screen", "maximize it", "make this window as big as possible"],
 "center": ["center this window", "center the window", "put this in the middle", "center it", "move this to the center"],
 "full_screen": ["full screen", "go full screen", "make this full screen", "enter full screen", "full screen mode"],
 "minimize": ["minimize", "minimize this window", "minimize it", "hide this window", "put this window away", "shrink this to the dock"]}
WINDOW_TEST = {"left": ["dock this window on the left side of the screen"], "right": ["I want this window on the right hand side"], "maximize": ["blow this window up to fill the display"],
 "minimize": ["tuck this window away"], "full_screen": ["take this window full screen"], "center": ["put the window dead center"], "top": ["this window should take the upper half"], "bottom": ["send this window to the lower half"]}
SYSTEM = {"lock_screen": ["lock the screen", "lock my Mac", "lock the computer", "lock it", "lock screen", "I'm stepping away, lock the Mac"],
 "screenshot": ["take a screenshot", "screenshot", "capture the screen", "grab a screenshot", "screenshot this", "take a screen capture"],
 "mission_control": ["mission control", "show all windows", "show me all my windows", "open mission control", "show everything that's open"],
 "show_desktop": ["show the desktop", "show desktop", "hide all windows", "clear the screen", "let me see the desktop"]}
SYSTEM_TEST = {"lock_screen": ["secure the laptop, I'm leaving"], "screenshot": ["snap a picture of my screen"], "mission_control": ["spread out all the open windows"], "show_desktop": ["move the windows out of the way so I can see the desktop"]}
READ = {"start": ["read this aloud", "read it to me", "read this out loud", "read the selection", "read that back to me", "speak this", "read this"],
 "stop": ["stop reading", "stop talking", "be quiet", "stop the reading", "that's enough reading"]}
READ_TEST = {"start": ["can you say this out loud for me"], "stop": ["okay you can stop reading now"]}

TRAIN = []   # (phrasing, tool, args) with {slots}
TEST = []
for table, test_table, tool, key in [(EDIT, EDIT_TEST, "edit", "action"), (BROWSER, BROWSER_TEST, "browser", "action"), (SCROLL, SCROLL_TEST, "scroll", "direction"),
        (VOLUME_STEP, VOLUME_STEP_TEST, "change_volume", "direction"), (MUTE, MUTE_TEST, "mute", "state"), (MEDIA, MEDIA_TEST, "media", "action"),
        (BRIGHT, BRIGHT_TEST, "brightness", "direction"), (DARK, DARK_TEST, "dark_mode", "state"), (WINDOW, WINDOW_TEST, "window", "action"),
        (SYSTEM, SYSTEM_TEST, "system", "action"), (READ, READ_TEST, "read_aloud", "action")]:
    TRAIN += fixed(tool, key, table)
    TEST += fixed(tool, key, test_table)

def slot(tool, phrasings, args):
    return [(p, tool, args) for p in phrasings]

TRAIN += slot("open_app", ["open {app}", "launch {app}", "start {app}", "switch to {app}", "go to {app}", "bring up {app}", "pull up {app}", "show me {app}",
    "open the {app} app", "open up {app}", "take me to {app}", "jump to {app}", "I need {app}", "get {app} open", "fire up {app}", "switch over to {app}", "bring {app} to the front"], {"name": "{app}"})
TEST += slot("open_app", ["let me see {app}", "I want to use {app} now", "get me into {app}", "{app} please", "move over to {app}"], {"name": "{app}"})
TRAIN += slot("quit_app", ["quit {app}", "close {app}", "exit {app}", "shut down {app}", "kill {app}", "quit the {app} app", "close out of {app}", "stop {app}"], {"name": "{app}"})
TEST += slot("quit_app", ["I'm done with {app}, quit it", "terminate {app}", "get rid of {app}"], {"name": "{app}"})
TRAIN += slot("open_website", ["open {site}", "go to {site}", "visit {site}", "take me to {site}", "pull up {site}", "open the {site} website", "bring up {site}", "navigate to {site}", "load {site}", "show me {site}"], {"site": "{site}"})
TEST += slot("open_website", ["I want to check {site}", "head over to {site}", "get {site} up in the browser"], {"site": "{site}"})

SEARCH = [("google", ["search Google for {q}", "google {q}", "search for {q} on Google", "look up {q} on Google", "do a Google search for {q}", "google search {q}"]),
          ("youtube", ["search YouTube for {q}", "YouTube {q}", "find {q} on YouTube", "look up {q} on YouTube", "play {q} on YouTube", "show me videos about {q}"]),
          ("wikipedia", ["search Wikipedia for {q}", "look up {q} on Wikipedia", "Wikipedia {q}", "find the Wikipedia page for {q}"]),
          ("amazon", ["search Amazon for {q}", "find {q} on Amazon", "look for {q} on Amazon", "shop for {q} on Amazon"]),
          ("maps", ["search maps for {q}", "find {q} on the map", "look up {q} in Maps", "show {q} on the map"]),
          ("github", ["search GitHub for {q}", "find {q} on GitHub", "look up {q} on GitHub"]),
          ("reddit", ["search Reddit for {q}", "find {q} on Reddit", "what does Reddit say about {q}"]),
          ("chatgpt", ["ask ChatGPT {q}", "ask ChatGPT about {q}", "ChatGPT {q}"]),
          ("claude", ["ask Claude {q}", "ask Claude about {q}"]),
          ("perplexity", ["ask Perplexity {q}", "search Perplexity for {q}"])]
for site, phrs in SEARCH: TRAIN += slot("web_search", phrs, {"query": "{q}", "site": site})
TRAIN += slot("web_search", ["search for {q}", "look up {q}", "search the web for {q}", "find out about {q}", "do a search for {q}", "search {q}", "look online for {q}", "I want to search for {q}"], {"query": "{q}"})
TEST += slot("web_search", ["can you google {q} for me", "run a Google search on {q}"], {"query": "{q}", "site": "google"})
TEST += slot("web_search", ["pull up YouTube videos on {q}"], {"query": "{q}", "site": "youtube"})
TEST += slot("web_search", ["check Amazon for {q}"], {"query": "{q}", "site": "amazon"})
TEST += slot("web_search", ["see what Wikipedia has on {q}"], {"query": "{q}", "site": "wikipedia"})
TEST += slot("web_search", ["find information about {q} online", "I need to look something up, {q}"], {"query": "{q}"})

TRAIN += slot("find_file", ["find the file {file}", "search my Mac for {file}", "find my {file}", "where is my {file}", "look for {file} on my computer", "spotlight {file}",
    "find the {file} document", "search my files for {file}", "locate my {file}", "find {file} on this Mac", "open spotlight and search {file}", "search my computer for the {file}"], {"query": "{file}"})
TEST += slot("find_file", ["dig up my {file} from my files", "I can't find my {file}, search the Mac", "where did I save the {file}"], {"query": "{file}"})
TRAIN += slot("press_keys", ["press {keyname}", "hit {keyname}", "tap {keyname}", "push {keyname}", "press the keys {keyname}", "do {keyname}"], {"keys": "{keys}"})
TEST += slot("press_keys", ["give {keyname} a press", "use the shortcut {keyname}"], {"keys": "{keys}"})
TRAIN += slot("set_volume", ["volume {n}", "set the volume to {n}", "set volume to {n} percent", "volume {n} percent", "turn the volume to {n}", "make the volume {n}", "put the volume at {n}",
    "change the volume to {n}", "volume to {n}", "bring the volume down to {n}", "raise the volume to {n}", "sound at {n} percent", "set the sound to {n}"], {"percent": "{n}"})
TEST += slot("set_volume", ["I want the volume at {n}", "take the volume to {n} percent", "sound level {n}"], {"percent": "{n}"})
TRAIN += slot("click", ["click {btn}", "click the {btn} button", "click on {btn}", "press the {btn} button", "tap {btn}", "hit the {btn} button", "click the {btn} link", "select {btn}", "choose {btn}"], {"label": "{btn}"})
TEST += slot("click", ["go ahead and click {btn}", "push the button that says {btn}"], {"label": "{btn}"})
TRAIN += slot("type_text", ["type {text}", "write {text}", "type out {text}", "type the words {text}", "enter the text {text}", "type in {text}"], {"text": "{text}"})
TEST += slot("type_text", ["put in the words {text}", "key in {text}"], {"text": "{text}"})
TRAIN += slot("add_reminder", ["remind me to {task} {when}", "remind me {when} to {task}", "set a reminder to {task} {when}", "add a reminder to {task} {when}", "create a reminder {when} to {task}",
    "don't let me forget to {task} {when}", "I need a reminder to {task} {when}"], {"task": "{task}", "when": "{when}"})
TRAIN += slot("add_reminder", ["remind me to {task}", "set a reminder to {task}", "add a reminder to {task}", "reminder to {task}", "don't let me forget to {task}", "add {task} to my reminders"], {"task": "{task}"})
TEST += slot("add_reminder", ["make sure I {task} {when}", "nudge me {when} to {task}"], {"task": "{task}", "when": "{when}"})
TEST += slot("add_reminder", ["put {task} on my reminders list"], {"task": "{task}"})
TRAIN += slot("add_event", ["schedule {event} {when}", "add {event} to my calendar {when}", "put {event} on my calendar {when}", "create an event {event} {when}", "book {event} {when}",
    "set up {event} {when}", "add a calendar event {event} {when}", "block time for {event} {when}"], {"title": "{event}", "when": "{when}"})
TRAIN += slot("add_event", ["schedule {event} {when} for {dur}", "add {event} {when} for {dur}", "book {event} {when} for {dur}", "put {event} on my calendar {when} for {dur}"], {"title": "{event}", "when": "{when}", "minutes": "{durm}"})
TEST += slot("add_event", ["I have {event} {when}, add it to the calendar", "calendar entry for {event} {when}"], {"title": "{event}", "when": "{when}"})
TEST += slot("add_event", ["pencil in {event} {when}, it'll take {dur}"], {"title": "{event}", "when": "{when}", "minutes": "{durm}"})
TRAIN += slot("set_timer", ["set a timer for {dur}", "timer for {dur}", "start a {dur} timer", "set a {dur} timer", "count down {dur}", "timer {dur}", "start a timer for {dur}", "give me a {dur} timer"], {"minutes": "{durm}"})
TRAIN += slot("set_timer", ["set a timer for {dur} for {label}", "start a {dur} timer for {label}", "{dur} timer for {label}", "set a {label} timer for {dur}"], {"minutes": "{durm}", "label": "{label}"})
TEST += slot("set_timer", ["let me know when {dur} have passed", "I need a countdown of {dur}"], {"minutes": "{durm}"})
TEST += slot("set_timer", ["time {dur} for {label}"], {"minutes": "{durm}", "label": "{label}"})
TRAIN += slot("save_note", ["note that {note}", "save a note {note}", "take a note {note}", "make a note {note}", "note to self {note}", "jot down {note}", "write this down {note}", "add a note {note}", "remember that {note}"], {"text": "{note}"})
TEST += slot("save_note", ["keep a note of this, {note}", "quick note, {note}"], {"text": "{note}"})
TRAIN += slot("search_history", ["what did I say about {q}", "search my history for {q}", "find what I dictated about {q}", "look in my dictations for {q}", "search my past dictations for {q}", "when did I mention {q}"], {"query": "{q}"})
TEST += slot("search_history", ["did I dictate anything about {q}", "go through my earlier dictations for {q}"], {"query": "{q}"})
TRAIN += slot("compose_email", ["new email", "compose an email", "write a new email", "start an email", "open a new email", "create a new email", "draft an email"], {})
TRAIN += slot("compose_email", ["email {person}", "write an email to {person}", "new email to {person}", "send an email to {person}", "compose an email to {person}", "draft an email to {person}", "start an email to {person}"], {"to": "{person}"})
TRAIN += slot("compose_email", ["email {person} about {subject}", "write an email to {person} about {subject}", "new email to {person} about {subject}", "send {person} an email about {subject}", "draft an email to {person} regarding {subject}"], {"to": "{person}", "subject": "{subject}"})
TRAIN += slot("compose_email", ["email {person} saying {reply}", "send an email to {person} saying {reply}", "write to {person} that {reply}", "email {person} and tell them {reply}"], {"to": "{person}", "body": "{reply}"})
TEST += slot("compose_email", ["I need to write to {person} by email"], {"to": "{person}"})
TEST += slot("compose_email", ["shoot {person} an email about {subject}"], {"to": "{person}", "subject": "{subject}"})
TEST += slot("compose_email", ["drop {person} an email saying {reply}"], {"to": "{person}", "body": "{reply}"})
TRAIN += slot("get_directions", ["directions to {place}", "get directions to {place}", "how do I get to {place}", "navigate to {place}", "take me to {place}", "show me the way to {place}", "route to {place}", "give me directions to {place}"], {"destination": "{place}"})
TEST += slot("get_directions", ["what's the best route to {place}", "I need to drive to {place}, show the directions"], {"destination": "{place}"})
TRAIN += slot("rewrite_selection", ["{rewrite}"], {"instruction": "{rewrite}"})
TEST += slot("rewrite_selection", ["{rewrite}"], {"instruction": "{rewrite}"})
TRAIN += slot("reply", ["reply saying {reply}", "reply that {reply}", "write a reply saying {reply}", "respond saying {reply}", "reply with {reply}", "answer this saying {reply}", "write back {reply}"], {"intent": "{reply}"})
TEST += slot("reply", ["tell them {reply} in a reply", "send back a response that says {reply}"], {"intent": "{reply}"})
TRAIN += slot("translate", ["translate {phrase} to {lang}", "translate {phrase} into {lang}", "how do you say {phrase} in {lang}", "say {phrase} in {lang}", "what is {phrase} in {lang}", "translate to {lang}, {phrase}", "in {lang}, {phrase}"], {"text": "{phrase}", "language": "{lang}"})
TEST += slot("translate", ["I need {phrase} in {lang}", "put {phrase} into {lang} for me"], {"text": "{phrase}", "language": "{lang}"})
TRAIN += slot("class_notes", ["start class notes", "start taking class notes", "open class notes", "take lecture notes", "begin class notes", "class notes", "start a lecture", "start note taking for class"], {})
TRAIN += slot("class_notes", ["search my class notes for {q}", "search my notes for {q}", "find {q} in my class notes", "look up {q} in my lecture notes", "search note {q}", "what do my notes say about {q}"], {"query": "{q}"})
TEST += slot("class_notes", ["the lecture is starting, take notes"], {})
TEST += slot("class_notes", ["check my lecture notes for anything on {q}"], {"query": "{q}"})
TRAIN += slot("run_shortcut", ["run shortcut {sc}", "run the {sc} shortcut", "run my {sc} shortcut", "start the {sc} shortcut", "run the shortcut called {sc}", "trigger {sc} shortcut"], {"name": "{sc}"})
TEST += slot("run_shortcut", ["kick off my {sc} shortcut", "execute the shortcut named {sc}"], {"name": "{sc}"})
TRAIN += slot("transcribe_file", ["transcribe a file", "transcribe an audio file", "transcribe a recording", "transcribe this video file", "I want to transcribe a file", "convert a recording to text", "transcribe a meeting recording"], {})
TEST += slot("transcribe_file", ["turn an audio recording into text", "I have a video file to transcribe"], {})

NEGATIVES = ["I think we should ship it on Friday", "the meeting went well and everyone agreed", "let's meet tomorrow at the coffee shop", "thanks for the update, I will take a look",
    "I copied the wrong number into the report", "the volume of sales went up last quarter", "she said the window was open all night", "can you believe how fast this year went",
    "I'm not sure whether we need another tab in the spreadsheet", "the search took forever but we found it", "my email got lost somewhere", "he reminded me about the deadline yesterday",
    "I was typing when the power went out", "the timer on the oven is broken", "we scrolled through the photos for an hour", "our new website looks great", "what a beautiful morning",
    "I have a question about the invoice", "please review my comments when you get a chance", "the brightness of the stars was amazing", "I love the dark chocolate one",
    "it's a note worthy achievement", "that app is really well designed", "the file was too large to attach", "we need to talk about the budget", "sounds good to me",
    "I'll be there in ten minutes", "happy birthday, hope you have a great day", "the screenshot she sent was blurry", "translate is not the right word for it",
    "you should close the deal by Friday", "the directions on the box were confusing", "I pressed him for an answer", "they muted me during the call by accident",
    "paste is my favorite kind of pasta sauce", "I undid all my hard work by mistake", "playing music helps me focus", "this is the best coffee in town", "see you next week",
    "hello, how are you doing today", "I don't know what to say", "the weather is nice", "one two three testing", "that reminds me of a funny story", "okay", "never mind", "um", "what"]
NEGATIVES_TEST = ["I think the tab in my shirt is annoying", "the new window in the kitchen lets in a lot of light", "he searched everywhere for his keys last night",
    "my calendar has been packed all month", "the reminder she gave me was helpful", "I opened the letter and read it twice", "nothing else to add from my side",
    "that's a bold claim to make", "the volume was fine at the concert", "good night everyone"]

LABELS = ["the pasta", "the laundry", "my break", "the eggs", "the meeting", "tea"]
SUBJECTS = ["the invoice", "tomorrow's meeting", "the project update", "my leave next week", "the budget review", "the interview schedule"]
DURS = [(1, ["1 minute", "one minute", "a minute"]), (2, ["2 minutes", "two minutes"]), (5, ["5 minutes", "five minutes"]), (10, ["10 minutes", "ten minutes"]), (15, ["15 minutes", "fifteen minutes", "a quarter of an hour"]),
        (20, ["20 minutes", "twenty minutes"]), (25, ["25 minutes", "twenty five minutes"]), (30, ["30 minutes", "thirty minutes", "half an hour"]), (45, ["45 minutes", "forty five minutes"]),
        (60, ["an hour", "one hour", "60 minutes"]), (90, ["an hour and a half", "90 minutes", "ninety minutes"]), (120, ["two hours", "2 hours"])]
DURS_TEST = [(3, ["three minutes"]), (40, ["forty minutes"]), (75, ["an hour and fifteen minutes"]), (180, ["three hours"])]

MORE_SUBJECTS, MORE_LABELS = [], []
VOLUMES = [5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 75, 80, 90, 100]

def fill(rng, phrasing, args, test):
    """One concrete example from a phrasing: picks values for every {slot}."""
    pick = lambda train, tst: rng.choice(tst if test else train)
    v = {}
    if "{app}" in phrasing: v["app"] = pick(APPS, APPS_TEST)
    if "{site}" in phrasing: v["site"] = pick(SITES, SITES_TEST)
    if "{q}" in phrasing: v["q"] = pick(QUERIES, QUERIES_TEST)
    if "{file}" in phrasing: v["file"] = pick(FILES, FILES_TEST)
    if "{btn}" in phrasing: v["btn"] = pick(BUTTONS, BUTTONS_TEST)
    if "{text}" in phrasing: v["text"] = pick(TEXTS, TEXTS_TEST)
    if "{task}" in phrasing: v["task"] = pick(TASKS, TASKS_TEST)
    if "{when}" in phrasing: v["when"] = pick(WHENS, WHENS_TEST)
    if "{event}" in phrasing: v["event"] = pick(EVENTS, EVENTS_TEST)
    if "{note}" in phrasing: v["note"] = pick(NOTES, NOTES_TEST)
    if "{person}" in phrasing: v["person"] = pick(PEOPLE, PEOPLE_TEST)
    if "{subject}" in phrasing: v["subject"] = rng.choice(SUBJECTS if test else SUBJECTS + MORE_SUBJECTS)
    if "{reply}" in phrasing: v["reply"] = pick(REPLIES, REPLIES_TEST)
    if "{place}" in phrasing: v["place"] = pick(PLACES, PLACES_TEST)
    if "{rewrite}" in phrasing: v["rewrite"] = pick(REWRITES, REWRITES_TEST)
    if "{phrase}" in phrasing: v["phrase"] = pick(PHRASES, PHRASES_TEST)
    if "{lang}" in phrasing: v["lang"] = pick(LANGS, LANGS_TEST)
    if "{sc}" in phrasing: v["sc"] = pick(SHORTCUTS, SHORTCUTS_TEST)
    if "{label}" in phrasing: v["label"] = rng.choice(LABELS if test else LABELS + MORE_LABELS)
    if "{keyname}" in phrasing:
        keys, names = pick(KEYS, KEYS_TEST)
        v["keyname"], v["keys"] = rng.choice(names), keys
    if "{dur}" in phrasing:
        minutes, names = pick(DURS, DURS_TEST)
        v["dur"], v["durm"] = rng.choice(names), minutes
    if "{n}" in phrasing:
        n = rng.choice(VOLUMES if not test else [35, 45, 55, 65, 85, 0])
        v["n"], v["nval"] = (NUM_WORDS[n] if rng.random() < 0.5 else str(n)), n
    text = phrasing
    for k, val in v.items(): text = text.replace("{" + k + "}", str(val))
    out = {}
    for k, val in args.items():
        if val == "{n}": out[k] = v["nval"]
        elif val == "{durm}": out[k] = v["durm"]
        elif isinstance(val, str) and val.startswith("{"): out[k] = v[val[1:-1]]
        else: out[k] = val
    return text, out

POLITE = ["", "", "", "", "please ", "can you ", "could you ", "hey Evoo, ", "okay ", "go ahead and ", "I want you to ", "would you ", "Evoo, "]
TAILS = ["", "", "", "", "", " please", " for me", " now", " thanks", " real quick"]
FILLERS = ["um ", "uh ", "so ", "okay so ", "alright "]

def roughen(rng, text):
    """Write it the way speech recognition does: sometimes tidy, sometimes all lowercase, sometimes with noise."""
    r = rng.random()
    if r < 0.35: text = text[0].upper() + text[1:] + rng.choice([".", ".", "", "?"]) if not text.endswith(("?", ".")) else text
    elif r < 0.75: text = text.lower()
    else: text = text[0].upper() + text[1:]
    if rng.random() < 0.08: text = rng.choice(FILLERS) + text[0].lower() + text[1:]
    if rng.random() < 0.06 and " " in text: # a stray comma, like "Volume, thirty."
        words = text.split(" "); i = rng.randrange(0, len(words) - 1); words[i] += ","; text = " ".join(words)
    return text

def example(rng, phrasing, tool, args, test, plain=False):
    text, filled = fill(rng, phrasing, args, test)
    if not plain and tool != "no_action" and tool != "rewrite_selection":
        if not text.lower().startswith(("i ", "can ", "how ", "what ", "where ", "when ", "did ", "don't ", "{")):
            text = rng.choice(POLITE) + text
        text += rng.choice(TAILS)
    return text, [(tool, filled)]

CHAINABLE = {"open_app", "quit_app", "open_website", "web_search", "edit", "browser", "scroll", "set_volume", "change_volume", "mute", "media", "brightness",
             "dark_mode", "window", "click", "system", "press_keys", "set_timer", "find_file"}
JOINS = [" and ", " and then ", ", then ", " then ", ". ", ", and ", " and after that ", ", after that ", " and also "]
JOINS_TRAIN = JOINS + [", ", ", ", ". Then ", " next ", ", next ", " and finally ", ", and then ", " followed by ", ". After that ", " plus "]

def chain(rng, pool, test):
    n = rng.choice([2, 2, 2, 3] if test else [2, 2, 3, 3, 3, 4])
    parts, calls = [], []
    for _ in range(n):
        phrasing, tool, args = rng.choice(pool)
        text, filled = fill(rng, phrasing, args, test)
        parts.append(text); calls.append((tool, filled))
    text = parts[0]
    for p in parts[1:]: text += rng.choice(JOINS if test else JOINS_TRAIN) + p
    if rng.random() < 0.3: text = rng.choice(["please ", "can you ", "okay "]) + text
    return text, calls

MIN_PER_TOOL = 300

def build(seed, per_phrasing, chains, test):
    rng = random.Random(seed)
    src = TEST if test else TRAIN
    rows = []
    for phrasing, tool, args in src:
        for i in range(per_phrasing if "{" in phrasing else max(2, per_phrasing // 2)):
            text, calls = example(rng, phrasing, tool, args, test, plain=(i == 0))
            rows.append((roughen(rng, text), calls))
    pool = [t for t in src if t[1] in CHAINABLE]
    for _ in range(chains):
        text, calls = chain(rng, pool, test)
        rows.append((roughen(rng, text), calls))
    for neg in (NEGATIVES_TEST if test else NEGATIVES):
        for _ in range(1 if test else 2):
            rows.append((roughen(rng, neg), [("no_action", {})]))
    # Every tool gets a fair share: top up the ones with few phrasings (more fillings, more polite forms).
    if not test:
        by_tool = {}
        for phrasing, tool, args in src: by_tool.setdefault(tool, []).append((phrasing, tool, args))
        count = {}
        for _, calls in rows:
            for n, _ in calls: count[n] = count.get(n, 0) + 1
        for tool, items in by_tool.items():
            for _ in range(max(0, MIN_PER_TOOL - count.get(tool, 0)) * 3):
                phrasing, _, args = rng.choice(items)
                text, calls = example(rng, phrasing, tool, args, test, plain=False)
                if tool == "rewrite_selection": text = rng.choice(POLITE) + text + rng.choice(TAILS)
                rows.append((roughen(rng, text), calls))
    seen, out = set(), []
    for text, calls in rows:
        if text.lower() in seen: continue
        seen.add(text.lower()); out.append((text, calls))
    rng.shuffle(out)
    return out

# Real failures from real use: always in the test set, never in training.
FIELD = [("Copy, then open new tab and then paste.", [("edit", {"action": "copy"}), ("browser", {"action": "new_tab"}), ("edit", {"action": "paste"})]),
         ("Close the tab and switch to Claude.", [("browser", {"action": "close_tab"}), ("open_app", {"name": "Claude"})]),
         ("Volume, thirty.", [("set_volume", {"percent": 30})]),
         ("Press space bar.", [("press_keys", {"keys": "space"})]),
         ("Can you make it a bit louder", [("change_volume", {"direction": "up"})]),
         ("Put this window on the left and open Slack", [("window", {"action": "left"}), ("open_app", {"name": "Slack"})]),
         ("Remind me to call Raj tomorrow at five", [("add_reminder", {"task": "call Raj", "when": "tomorrow at five"})]),
         ("Multi command not working.", [("no_action", {})]),
         ("Search Google for flights to Delhi and mute", [("web_search", {"query": "flights to Delhi", "site": "google"}), ("mute", {"state": "on"})])]

import more
more.extend(globals())
more.extend3(globals())   # training only: far more names to fill in and ways to ask (see more.py)

def main():
    data = ROOT / "data"; data.mkdir(exist_ok=True)
    pre = prefix()
    (ROOT / "prefix.txt").write_text(pre)
    train = build(1, per_phrasing=9, chains=8000, test=False)
    test = build(2, per_phrasing=2, chains=80, test=True) + [(t, c) for t, c in FIELD]
    train_texts = {t.lower() for t, _ in train}
    test = [(t, c) for t, c in test if t.lower() not in train_texts]
    cut = int(len(train) * 0.96)
    def write(name, rows):
        with open(data / name, "w") as f:
            for text, calls in rows:
                f.write(json.dumps({"user": text, "calls": [{"name": n, "args": a} for n, a in calls],
                                    "prompt": pre + user_turn(text), "completion": call_text(calls)}, ensure_ascii=False) + "\n")
    write("train.jsonl", train[:cut]); write("valid.jsonl", train[cut:]); write("test.jsonl", test)
    per_tool = {}
    for _, calls in train:
        for n, _ in calls: per_tool[n] = per_tool.get(n, 0) + 1
    print(f"tools: {len(TOOLS)} · phrasings: {len(TRAIN)} train, {len(TEST)} test")
    print(f"examples: {cut} train, {len(train) - cut} valid, {len(test)} test · prefix: {len(pre)} characters")
    print("fewest examples:", sorted(per_tool.items(), key=lambda kv: kv[1])[:5])

if __name__ == "__main__":
    main()
