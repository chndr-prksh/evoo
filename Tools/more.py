"""More variety for the training examples (never the test set): bigger pools of names to fill in, and many more ways
of asking for each tool — blunt, polite, indirect ("it's too loud"), and need-based ("I'm done with this tab").

A small model given few distinct examples memorises them. Given thousands of different names and phrasings, the only
thing left to learn is the pattern: which tool, and which words to copy into its arguments."""
import itertools, random

rng = random.Random(7)

def combos(*parts, limit=400):
    out = [" ".join(p).replace("  ", " ").strip() for p in itertools.product(*parts)]
    rng.shuffle(out)
    return out[:limit]

APPS = """Brave Browser|Opera|Vivaldi|DuckDuckGo|Tor Browser|Microsoft Edge|Google Chrome|Sublime Text|Visual Studio Code|IntelliJ|PyCharm|WebStorm|Android Studio|
iTerm|Warp|Ghostty|Zed|Nova|BBEdit|TextMate|Sketch|Photoshop|Illustrator|Lightroom|Premiere Pro|After Effects|Final Cut Pro|Logic Pro|GarageBand|iMovie|DaVinci Resolve|
Blender|Unity|Affinity Photo|Pixelmator|Canva|Miro|Loom|OBS|QuickTime Player|VLC|IINA|Apple TV|Kindle|Audible|Shazam|Voice Memos|Stocks|Weather|Clock|Home|Contacts|
Freeform|Journal|Passwords|Shortcuts|Automator|Console|Disk Utility|Font Book|Image Capture|Migration Assistant|Script Editor|Stickies|Time Machine|App Store|News|
Bear|Things|Todoist|TickTick|OmniFocus|Evernote|OneNote|Craft|Roam|Logseq|Day One|Ulysses|Scrivener|iA Writer|Typora|Drafts|Raycast|Alfred|Rectangle|Magnet|
1Password|Bitwarden|Dashlane|Dropbox|Google Drive|OneDrive|Box|Transmit|Cyberduck|FileZilla|Tower|Fork|GitHub Desktop|Sourcetree|TablePlus|Sequel Pro|DBeaver|
Insomnia|Proxyman|Charles|Wireshark|Parallels|UTM|VMware Fusion|Steam|Epic Games|Minecraft|Chess|Skype|Webex|Google Meet|Slack Huddle|Mattermost|Element|
Thunderbird|Spark|Airmail|Superhuman|Fantastical|BusyCal|Cron|Notion Calendar|Tableau|Power BI|MATLAB|RStudio|Jupyter|Anki|Duolingo|Zotero|Mendeley|Grammarly|
Tidal|Deezer|Pocket Casts|Overcast|Reeder|NetNewsWire|Tweetbot|Ivory|Mastodon|Bluesky|Threads|Robinhood|Zerodha Kite|Groww|QuickBooks|Xero|Tally|Zoho|Salesforce|
HubSpot|Jira|Asana|Trello|ClickUp|Monday|Basecamp|Airtable|Coda|Retool|Vercel|Postico|Simulator|Instruments|Reality Composer|Swift Playgrounds|TestFlight|Xcode Cloud""".replace("\n", "").split("|")

SITES = """Hotmail|Yahoo Mail|Outlook web|Google Sheets|Google Slides|Google Photos|Google Translate|Google News|Google Scholar|Google Flights|Bing|DuckDuckGo|
Twitch|Vimeo|Spotify web|SoundCloud|Medium|Substack|Quora|Product Hunt|Dribbble|Behance|Figma web|Notion web|Trello|Jira|Zomato|Swiggy|Uber Eats|DoorDash|Flipkart|
Myntra|eBay|Etsy|Walmart|Target|Best Buy|IKEA|Booking.com|Airbnb|MakeMyTrip|Expedia|Skyscanner|IRCTC|Udemy|Khan Academy|edX|LeetCode|HackerRank|Kaggle|Hugging Face|
arXiv|PubMed|ESPN|Cricbuzz|IMDb|Rotten Tomatoes|Goodreads|Zillow|Indeed|Glassdoor|Naukri|PayPal|Stripe dashboard|AWS console|Azure portal|Google Cloud console|
Vercel dashboard|Netlify|Cloudflare|Disney Plus|Prime Video|Hotstar|Hulu|the New York Times|the Guardian|BBC News|CNN|TechCrunch|Wired|The Economist|Bloomberg|
espn.com|imdb.com|medium.com|stackoverflow.com|wikipedia.org|youtube.com|reddit.com|amazon.in|flipkart.com|linkedin.com|x.com|twitch.tv|figma.com|canva.com|
zoom.us|dropbox.com|paypal.com|booking.com|airbnb.com|netflix.com|spotify.com|kaggle.com|huggingface.co|arxiv.org|docs.python.org|developer.apple.com|news.ycombinator.com""".replace("\n", "").split("|")

TOPICS = """electric cars|solar panels|mechanical keyboards|running shoes|wireless earbuds|office chairs|air purifiers|espresso machines|hiking boots|yoga mats|protein powder|
gaming laptops|4K monitors|robot vacuums|smart watches|baby strollers|winter jackets|rain boots|camping tents|water bottles|backpacks|desk lamps|bookshelves|houseplants|
guitar lessons|piano chords|chess openings|sourdough starter|meal prep|intermittent fasting|marathon training|home workouts|meditation|sleep hygiene|back pain|migraines|
seasonal allergies|vitamin D|credit scores|index funds|mortgage rates|tax deductions|freelance contracts|resume templates|cover letters|salary negotiation|remote jobs|
machine learning|neural networks|large language models|vector databases|rust programming|typescript generics|docker compose|git rebase|sql joins|css grid|swiftui navigation|
regular expressions|binary search|graph algorithms|system design|kubernetes pods|aws lambda|postgres indexes|redis caching|oauth tokens|the roman empire|world war two|
the french revolution|ancient egypt|the silk road|black holes|the james webb telescope|climate change|coral reefs|volcanoes|the northern lights|monsoon season|
the stock market|inflation|cryptocurrency|interest rates|the olympics|formula one|the premier league|ipl cricket|wimbledon|the super bowl|bollywood movies|oscar winners|
jazz music|classical guitar|indie rock|podcasts about history|true crime documentaries|anime recommendations|board games|lego sets|origami|watercolor painting|
calligraphy|street photography|drone footage|wedding planning|baby names|puppy training|cat food|aquarium fish|bird watching|vegetable gardening|composting|
apartment hunting|moving checklists|home insurance|car maintenance|bike repair|public transport|visa applications|passport renewal|travel insurance|jet lag|
thai food|italian restaurants|vegan desserts|biryani recipes|ramen|homemade pizza|cold brew coffee|green tea|smoothies|birthday cakes|christmas gifts|diwali decorations""".replace("\n", "").split("|")
CITIES = "Paris|Tokyo|New York|Singapore|Dubai|Sydney|Berlin|Toronto|Hyderabad|Chennai|Kolkata|Jaipur|Seattle|Austin|Boston|Chicago|Amsterdam|Barcelona|Rome|Lisbon|Bangkok|Bali|Cape Town|Nairobi|Mexico City".split("|")

def queries():
    out = []
    frames = ["{t}", "{t}", "best {t}", "how to get started with {t}", "{t} for beginners", "{t} near me", "{t} in {c}", "cheap {t}", "{t} reviews", "what are {t}",
              "history of {t}", "{t} tips", "latest news on {t}", "{t} vs alternatives", "how does {t} work", "is {t} worth it", "top ten {t}", "{t} tutorial",
              "why is {t} so popular", "{t} explained simply", "things to do in {c}", "weather in {c} this weekend", "flights from {c} to {c2}", "hotels in {c} under budget",
              "time in {c} right now", "population of {c}", "best time to visit {c}"]
    for _ in range(2200):
        out.append(rng.choice(frames).format(t=rng.choice(TOPICS), c=rng.choice(CITIES), c2=rng.choice(CITIES)))
    return sorted(set(out))

FIRST = """Aditi|Akash|Alex|Alice|Amit|Ana|Andre|Anita|Arjun|Ben|Bella|Carla|Chen|Chloe|Chris|Daniel|Deepa|Diego|Elena|Ethan|Farah|Fatima|Gabriel|Grace|Hannah|Harsh|
Ibrahim|Isha|Jack|James|Jia|Julia|Karan|Kavya|Kevin|Lakshmi|Laura|Leo|Liam|Lucas|Maya|Meera|Michael|Mohammed|Nadia|Nikhil|Nina|Noah|Olivia|Omar|Pooja|Rachel|Ravi|
Rohan|Sam|Sanjay|Sofia|Sunita|Tara|Thomas|Uma|Varun|Vikram|Wei|Yuki|Zara|Zoe""".replace("\n", "").split("|")
PEOPLE = FIRST + ["my boss", "my wife", "my husband", "my brother", "my sister", "dad", "the accountant", "the client", "HR", "the recruiter", "my professor", "the dentist",
          "customer support", "the design team", "everyone in sales", "my co-founder", "the hiring manager", "Dr. Shah", "Professor Lee", "Mr. Kapoor", "Ms. Fernandez",
          "Aditi Rao", "Kevin Brooks", "Maya Patel", "the vendor", "our lawyer", "the school office", "my roommate", "the engineering leads", "accounts payable"]

TASKS = combos(["call", "text", "email", "message", "meet", "thank", "check in with", "follow up with", "pay", "invite"], FIRST[:30], limit=120) + combos(
    ["buy", "order", "pick up", "return", "replace", "find"], ["bread", "eggs", "coffee beans", "a phone charger", "printer ink", "dog food", "light bulbs", "a birthday gift", "toothpaste", "stamps", "batteries", "a new notebook", "vitamins", "detergent"], limit=70) + combos(
    ["finish", "review", "submit", "send", "print", "update", "back up", "sign", "proofread", "share"], ["the slides", "the contract", "my timesheet", "the proposal", "the budget", "the homework", "the newsletter", "the design doc", "my tax forms", "the meeting minutes", "the release notes", "the quarterly numbers"], limit=90) + [
    "take out the trash", "feed the cat", "walk the dog", "stretch", "drink water", "stand up", "charge my laptop", "book flights", "renew the car insurance", "pay rent",
    "schedule a haircut", "clean the kitchen", "do the laundry", "call the bank", "check the mail", "water the garden", "pick up the kids", "go to the gym", "take a break",
    "start dinner", "turn off the oven", "move the car", "top up my metro card", "refill my prescription", "cancel the gym membership", "read chapter four", "practice guitar"]

DAYS = ["today", "tomorrow", "tonight", "this afternoon", "this evening", "on Monday", "on Tuesday", "on Wednesday", "on Thursday", "on Friday", "on Saturday", "on Sunday",
        "next Tuesday", "next Friday", "this weekend", "next month", "on the 3rd", "on the 15th", "on March 12th", "on June 1st", "day after tomorrow", "first thing tomorrow"]
TIMES = ["", "", "at 8", "at 9 am", "at 10:30", "at noon", "at 1 pm", "at 2:15", "at 3", "at 4 pm", "at 5:30", "at 6", "at 7 pm", "at 8:45 pm", "at nine", "at eleven thirty",
         "in the morning", "in the afternoon", "at quarter past four", "at midnight", "before lunch", "after work"]
WHENS = sorted(set([f"{d} {t}".strip() for d in DAYS for t in TIMES if not (d in ("tonight", "this afternoon", "this evening") and "morning" in t)]
               + ["in ten minutes", "in 15 minutes", "in half an hour", "in 45 minutes", "in three hours", "in a couple of hours", "in two days", "in a week", "at 6:30", "at 7 am", "at noon"]))

EVENTS = combos(["lunch", "dinner", "coffee", "a call", "a meeting", "a catch-up", "drinks", "breakfast", "a walk", "a video call"], ["with"], FIRST[:40], limit=120) + [
    "sprint planning", "the board meeting", "budget review", "doctor's appointment", "haircut", "car service", "piano lesson", "swim practice", "book club", "date night",
    "the product demo", "all hands", "client onboarding", "performance review", "team offsite", "webinar on pricing", "physio session", "school pickup", "house viewing",
    "tax filing", "flight to Delhi", "train to Pune", "movie night", "birthday party", "wedding rehearsal", "study group", "office hours", "code review", "retro",
    "investor call", "vendor negotiation", "user interviews", "design review", "launch rehearsal", "weekly sync", "town hall", "interview with the candidate"]

SENTENCES = """I'll send it over tonight|the report is ready for review|let's move the meeting to Thursday|I'm on my way|running five minutes behind|can we talk later today|
thanks so much for the help|that sounds perfect|I'll get back to you by Friday|please find the file attached|the numbers look good to me|we should discuss this in person|
I've already paid the invoice|the package arrived this morning|let me know what you think|I agree with the plan|no worries at all|see you at the office|
I can do Tuesday or Wednesday|we need more time on this|the demo went really well|I'm working from home tomorrow|could you share the link|happy to jump on a call|
I'll take care of it|let's keep it simple|the deadline is next week|I just landed|dinner is at eight|the keys are under the mat|call me when you're free|
I forgot my charger|the build is passing now|we're out of milk|the gate code is four two seven one|my flight is delayed|I'll bring the documents|
the meeting room is on the third floor|we hit our target this month|the printer is out of paper|let's not rush this|I'll think about it and let you know|
it was great meeting you|I'm sorry for the late reply|the wifi is down again|your order has shipped|we can skip the appetizers|the rent is due on the first|
I need a few more details|please ignore my last message|let's celebrate this weekend|everything is on track|I'll be offline for an hour|the offer expires tonight""".replace("\n", "").split("|")
NOTES = SENTENCES + combos(["remember", "idea,", "todo,", "", "important,"], ["the garage code is 1984", "ask about the warranty", "try the new bakery downtown", "the meeting moved to room five",
        "compare three quotes before buying", "the doctor said twice a day", "use the blue folder for receipts", "the server restarts at midnight", "her birthday is in May",
        "the recipe needs two cups of flour", "parking is free after six", "the report template is in Drive", "book the venue by March", "the spare charger is in the drawer"], limit=60)

BUTTONS = """OK|Yes|No|Apply|Back|Edit|Delete|Remove|Open|Upload|Attach|Confirm|Agree|Decline|Allow|Deny|Retry|Refresh|Log in|Log out|Sign up|Subscribe|Unsubscribe|Follow|
Like|Comment|Buy now|Place order|Pay now|Add|New|Create|Start|Stop|Pause|Play|Record|Mute|Leave|End call|Raise hand|Send message|New chat|Compose|Archive|Mark as read|
Snooze|Print|Export|Import|Copy link|Open in new tab|Learn more|Read more|Show more|See all|View details|Get started|Try for free|Contact us|Help|Settings|Profile|
Notifications|Dark mode|Filter|Sort|Clear all|Select all|Undo|Redo|Insert|Format|Run|Build|Deploy|Merge|Commit|Push|Pull request|Approve|Request changes|Resolve|
Book now|Check availability|Reserve|Track order|Apply coupon|Proceed to payment|Save draft|Discard|Schedule send|Add attachment|Turn on|Turn off|Got it|Maybe later|
Remind me later|Install|Update|Restart|Shut down|Agree and continue|I understand|Verify|Resend code|Use another account""".replace("\n", "").split("|")

FILES = combos(["", "", "my", "the", "last year's", "the latest", "the signed", "the old", "the final"], ["contract", "invoice", "receipt", "resume", "cover letter", "transcript", "rent agreement", "medical report",
        "boarding pass", "tax form", "payslip", "expense sheet", "wedding photos", "pitch deck", "meeting recording", "research paper", "user manual", "floor plan", "warranty card",
        "birth certificate", "driving licence scan", "bank statement", "electricity bill", "project proposal", "marketing plan", "budget", "roadmap", "syllabus", "lab report", "cv"], limit=170) + combos(
        ["the", "that"], ["pdf", "spreadsheet", "presentation", "document", "photo", "screenshot", "zip file", "video"], ["about", "from", "for", "called"],
        ["the trip", "last week", "the client", "taxes", "onboarding", "the wedding", "Q3", "the interview", "physics", "the audit"], limit=110)

PLACES = """the nearest ATM|the closest coffee shop|the nearest gas station|the nearest metro station|the city library|the bus terminal|Terminal 3|the downtown office|home|work|
my parents' house|the gym|the dentist|the vet|the post office|the embassy|the convention center|the stadium|the beach|the old town|the botanical garden|the science museum|
the zoo|Heathrow Airport|JFK|Mumbai airport|Bangalore airport|Marine Drive|Cubbon Park|Koramangala|Indiranagar|Bandra|Powai|Cyber City Gurgaon|Hitech City|Brooklyn Bridge|
Union Square|Golden Temple|the Taj Mahal|the Eiffel Tower|Big Ben|Shibuya Crossing|the Louvre|Fisherman's Wharf|Pike Place Market|the nearest hospital|a pharmacy nearby|
the nearest grocery store|42 Wallaby Way|221B Baker Street|1600 Amphitheatre Parkway|Phoenix Mall|the IKEA store|the Apple Store|the university campus|the high school|
the courthouse|the police station|the nearest charging station|the hotel|the wedding venue|the conference hotel|the lake|the trailhead|the ferry terminal""".replace("\n", "").split("|")

LANGS = "Korean|Russian|Turkish|Greek|Swedish|Polish|Thai|Vietnamese|Indonesian|Urdu|Punjabi|Marathi|Gujarati|Telugu|Kannada|Malayalam|Swahili|Hebrew|Persian|Czech|Finnish|Norwegian|Danish|Ukrainian|Chinese|Cantonese|Nepali|Filipino".split("|")
LANGS = [l for l in LANGS if l not in ("Korean",)]
PHRASES = SENTENCES[:30] + ["good night", "excuse me", "I'm sorry", "where is the bathroom", "how are you", "what time is it", "I love you", "cheers", "welcome", "please wait a moment",
           "the food was delicious", "I would like a table for two", "do you speak English", "my name is Sam", "can you help me", "turn left at the corner", "I am lost",
           "congratulations on your new job", "get well soon", "the check please", "I have a reservation", "how far is the airport", "that is too expensive", "see you later"]
REWRITES = combos(["make this", "make it", "rewrite this to be", "can you make this", "I want this to sound", "make the selected text", "change this to be", "rework this so it's"],
                  ["more formal", "more casual", "shorter", "longer", "friendlier", "more professional", "clearer", "simpler", "more polite", "more direct", "funnier", "more confident",
                   "less aggressive", "more detailed", "more concise", "warmer", "more enthusiastic", "easier to read"], limit=110) + [
    "fix the spelling", "fix the typos here", "correct the grammar in this", "clean this up", "polish this paragraph", "turn this into bullet points", "summarize this", "summarize this in one line",
    "expand on this", "turn this into a tweet", "rewrite this as a formal email", "make this a numbered list", "rephrase this", "say this differently", "translate this to Spanish",
    "translate this into German", "put this in plain English", "make this sound like a lawyer wrote it", "convert this to a table", "shorten this to two sentences", "add a friendly greeting to this",
    "remove the jargon from this", "make this suitable for LinkedIn", "rewrite this in the past tense", "make this paragraph flow better", "cut this in half"]
SHORTCUTS = """Start Work|End Work|Bedtime|Commute|Gym Time|Deep Work|Focus Hour|Coffee Break|Log Mood|Log Weight|Track Expense|New Invoice|Scan Document|Resize Images|
Make PDF|Clean Desktop|Empty Downloads|Backup Photos|Daily Journal|Weekly Review|Meeting Mode|Presentation Mode|Movie Night|Party Lights|Toggle VPN|Call Home|
Text Running Late|Share Location|Playlist Shuffle|Read Later|Save Article|Translate Clipboard|Shorten Link|Battery Report|Dev Setup|Kill Port|Open Standup Links|Travel Checklist""".replace("\n", "").split("|")
TEXTS = SENTENCES + ["yes", "no problem", "sounds good", "Dear team", "Kind regards", "to whom it may concern", "one moment please", "call you back soon", "meeting at four", "approved",
         "let's go", "thank you for your time", "will do", "noted with thanks", "please confirm", "my address is 12 Park Street", "the code is seven seven three", "lol", "good idea"]
LABELS = ["the rice", "the cake", "the pizza", "my nap", "the wash", "the tea", "coffee", "the workout", "my stretch break", "the interview", "the presentation", "the cookies", "the chicken",
          "study time", "the kids' screen time", "parking", "the plank", "meditation", "the face mask", "the dryer", "the standup", "focus"]
SUBJECTS = ["the offsite", "next week's schedule", "the contract renewal", "my resignation", "a refund", "the late delivery", "the job application", "the Q4 numbers", "a meeting request",
            "the broken link", "feedback on the draft", "the conference tickets", "an invoice correction", "the onboarding plan", "vacation days", "the security review",
            "the school trip", "our dinner plans", "the rent increase", "the apartment viewing", "a quick question", "the workshop agenda", "payment confirmation", "the design handoff"]

MODS = ["command", "command shift", "command option", "control", "control shift", "option", "command control", "shift"]
KEYNAMES = list("abdefghijkmopqrsuvxyz123568") + ["up", "down", "left", "right", "enter", "escape", "tab", "space", "delete", "f1", "f2", "f3", "f6", "f10", "f12", "comma", "period", "slash"]
def keys():
    out = []
    for _ in range(140):
        m, k = rng.choice(MODS), rng.choice(KEYNAMES)
        if m == "shift" and len(k) == 1: m = "command shift"
        canon = f"{m} {k}"
        spoken = [f"{m} {k.upper() if len(k) == 1 else k}", f"{m.replace('command', 'cmd').replace('control', 'ctrl')} {k.upper() if len(k) == 1 else k}", f"{m} plus {k}", f"{m} and {k}"]
        out.append((canon, spoken))
    for k in ["escape", "enter", "tab", "space", "delete", "up", "down", "left", "right", "f1", "f2", "f11", "f12", "home", "end", "page up", "page down"]:
        out.append((k, [k, f"the {k} key", f"{k} key"]))
    return out

ONES = "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen".split()
TENS = "x x twenty thirty forty fifty sixty seventy eighty ninety".split()
def number_word(n):
    if n < 20: return ONES[n]
    if n == 100: return rng.choice(["a hundred", "one hundred", "hundred"])
    return TENS[n // 10] + ("" if n % 10 == 0 else " " + ONES[n % 10])
def durations():
    out = []
    for m in [1, 2, 4, 5, 6, 7, 8, 9, 10, 12, 15, 18, 20, 25, 30, 35, 45, 50, 55, 60, 90, 120, 150, 240]:
        if m < 60: names = [f"{m} minutes" if m > 1 else "1 minute", f"{number_word(m)} minutes" if m > 1 else "one minute", f"{m} min" if m > 1 else "a minute"]
        else:
            h = m / 60
            names = {60: ["an hour", "one hour", "1 hour", "sixty minutes"], 90: ["an hour and a half", "ninety minutes", "one and a half hours"], 120: ["two hours", "2 hours", "a couple of hours"],
                     150: ["two and a half hours", "two hours thirty minutes"], 240: ["four hours", "4 hours"]}[m]
        if m == 30: names += ["half an hour", "thirty minutes"]
        if m == 15: names += ["a quarter of an hour"]
        if m == 45: names += ["three quarters of an hour"]
        out.append((m, names))
    return out

# ── More ways to ask ────────────────────────────────────────────────────────────────────────────────────────

FIXED = {
 ("edit", "action"): {
  "copy": ["copy this text", "copy the highlighted text", "copy what I selected", "copy this for me", "I need to copy this", "put this on the clipboard", "copy that line", "duplicate this to the clipboard", "do a copy", "hit copy", "command C this", "copy the whole selection", "take a copy of that"],
  "cut": ["cut this text", "cut what's selected", "cut that out of here", "do a cut", "cut this line", "I want to cut this", "hit cut", "remove this and keep it on the clipboard", "cut this part", "snip this out", "cut the highlighted text"],
  "paste": ["paste it in", "paste it right here", "do a paste", "hit paste", "paste the text", "paste what I just copied", "put it here", "insert what I copied", "paste from the clipboard", "I want to paste", "paste that in", "paste my clipboard here", "put the copied text here"],
  "undo": ["undo it", "undo this", "undo the last action", "undo what I just did", "that was a mistake, undo it", "reverse that", "undo that change", "wait undo", "no no undo that", "cancel my last edit", "hit undo", "step back one edit", "I messed up, undo"],
  "redo": ["redo that change", "redo what I undid", "hit redo", "redo my last action", "I undid too much, redo", "reapply that", "redo the edit", "undo the undo", "put back what I just undid", "redo please"],
  "select_all": ["select all of it", "select all the content", "select the whole document", "highlight all the text", "select everything here", "mark everything", "choose all", "hit select all", "select the full text", "highlight the whole page", "select every line"],
  "save": ["save the document now", "save this file", "save my changes", "save it now", "hit save now", "save everything", "save the current file", "make sure this is saved", "I want to save this", "store my changes", "save progress", "do a save", "write this to disk"],
  "find": ["find in this document", "search within this file", "find something on this page", "open the find bar", "open search in this page", "bring up find", "I want to search this page", "look for a word on this page", "show the find box", "hit find", "search inside this page"],
  "bold": ["make the selection bold", "bold this text", "bold the selected text", "set this in bold", "put this in bold", "I want this bold", "bold it", "make that word bold", "apply bold", "make these words bold", "toggle bold"],
  "italic": ["italicize this", "italicize the selection", "make that italic", "put this in italic", "set this in italics", "apply italics", "make these words italic", "I want this in italics", "toggle italic", "slant this text"],
  "underline": ["underline the selection", "underline this text", "underline the selected words", "put a line under this", "apply underline", "make this underlined", "I want this underlined", "toggle underline", "underline it"],
  "print": ["print this page", "print the document", "print it", "print this file", "print this out", "I want to print this", "bring up print", "send it to the printer", "hit print", "get this printed", "make a hard copy of this"],
  "delete_word": ["delete the previous word", "delete the word before the cursor", "remove that last word", "erase that word", "take out the last word", "scratch the last word", "delete one word back", "backspace a word", "kill the last word", "drop the last word"],
  "delete_line": ["delete the current line", "delete the whole line", "remove the entire line", "erase this line", "get rid of this line", "kill this line", "clear the line I'm on", "delete everything on this line", "take out this line", "scrap this line"],
 },
 ("browser", "action"): {
  "new_tab": ["open another tab", "one more tab", "add a tab", "new tab here", "make a new tab", "I want a new tab", "open a blank tab", "fresh tab", "open an empty tab", "let's get a new tab", "hit new tab", "bring up a new tab", "another tab"],
  "close_tab": ["close this one tab", "close the tab I'm on", "I don't need this tab anymore", "shut the tab", "close that tab", "this tab can go", "exit this tab", "remove this tab", "close the active tab", "hit close tab", "ditch this tab", "I'm finished with this tab", "done here, close the tab"],
  "reopen_tab": ["reopen the tab I just closed", "bring back the last tab", "get that tab back", "oops reopen that tab", "restore the closed tab", "I didn't mean to close that tab", "open the last closed tab", "reopen my last tab", "undo closing that tab", "bring the closed tab back"],
  "next_tab": ["go to the tab on the right", "next tab over", "move one tab right", "switch tab to the right", "show the next tab", "go one tab forward", "cycle to the next tab", "the next tab please", "tab forward", "hop to the next tab"],
  "previous_tab": ["go to the tab on the left", "previous tab over", "move one tab left", "switch tab to the left", "show the previous tab", "go one tab back", "cycle to the previous tab", "the earlier tab", "tab backward", "hop to the previous tab", "the tab I was just on"],
  "back": ["go back one page", "back a page", "go to the previous page", "back to where I was", "take me to the last page", "navigate back", "hit back", "go back in the browser", "back up one page", "the page before this one", "return to the last page"],
  "forward": ["go forward one page", "forward a page", "navigate forward", "hit forward", "go forward in the browser", "the page after this one", "move forward a page", "take me forward", "go forward again", "forward to the next page"],
  "refresh": ["refresh this", "reload this page", "refresh the browser", "reload the site", "refresh this tab", "this page is stuck, reload it", "update the page", "reload the tab", "give the page a refresh", "do a refresh", "load the page again please", "fetch this page again"],
  "new_window": ["open another window", "new browser window", "make a new window", "I want a new window", "another window", "open a separate window", "fresh window", "bring up a new window", "open a blank window", "one more window"],
  "close_window": ["close this whole window", "close the entire window", "shut the window", "close that window", "I don't need this window", "this window can go", "exit this window", "close the active window", "close all tabs in this window", "done with this window, close it", "ditch this window", "get rid of this window"],
  "zoom_in": ["zoom in more", "zoom in on the page", "make the page bigger", "make everything bigger", "I can't read this, zoom in", "bigger text", "increase the text size", "enlarge this", "magnify the page", "zoom in a little", "it's too small, make it bigger", "bump up the zoom"],
  "zoom_out": ["zoom out more", "zoom out of the page", "make the page smaller", "make everything smaller", "smaller text", "decrease the text size", "reduce the zoom", "zoom out a little", "it's too large, make it smaller", "bring the zoom down", "pull back the zoom", "everything is huge, zoom out"],
 },
 ("scroll", "direction"): {
  "down": ["scroll down more", "scroll down the page", "go further down", "keep going down", "show me what's below", "scroll down a little", "next screen", "move down", "scroll lower", "down a page", "read on, scroll down", "more, scroll down", "continue down the page"],
  "up": ["scroll up more", "scroll up the page", "go further up", "go back up", "show me what's above", "scroll up a little", "previous screen", "move up", "scroll higher", "up a page", "back up the page a bit"],
  "top": ["scroll all the way up", "go all the way to the top", "back to the beginning of the page", "jump to the start", "top of the document", "take me to the top", "scroll to the very top", "return to the top", "go to the start of the page", "beginning of the document", "all the way up"],
  "bottom": ["scroll all the way down", "go all the way to the bottom", "jump to the bottom", "end of the document", "take me to the bottom", "scroll to the very bottom", "go to the end", "bottom of the document", "skip to the bottom", "all the way to the end", "the very end of the page"],
 },
 ("change_volume", "direction"): {
  "up": ["turn up the volume", "turn the sound up", "sound up", "more volume", "raise the sound", "increase the sound", "volume higher", "a little louder", "louder please", "I can barely hear this", "it's too quiet", "boost the volume", "pump up the volume", "nudge the volume up", "make the audio louder", "up the volume"],
  "down": ["turn down the volume", "turn the sound down", "sound down", "less volume", "lower the sound", "decrease the volume", "volume lower", "a little quieter", "quieter please", "this is too loud", "it's way too loud", "drop the volume", "take the volume down", "nudge the volume down", "make the audio quieter", "tone it down"],
 },
 ("mute", "state"): {
  "on": ["mute it", "mute the audio", "mute the speakers", "mute the computer", "silence the Mac", "silence the sound", "turn off the sound", "turn the audio off", "sound off", "no audio", "cut the sound", "stop the sound", "make it silent", "quiet mode", "I need silence", "mute the laptop", "hush"],
  "off": ["unmute it", "unmute the audio", "unmute the speakers", "unmute the computer", "turn the sound on", "turn on the sound again", "audio back on", "sound back on", "take it off mute", "I want sound again", "stop muting", "unmute the laptop", "undo the mute", "restore the sound"],
 },
 ("media", "action"): {
  "play_pause": ["pause it", "pause the song", "pause playback", "pause the podcast", "stop playing", "hold on, pause", "play it", "play the song", "start playing", "resume the music", "resume the video", "keep playing", "unpause", "hit play", "hit pause", "toggle playback", "pause that for a moment", "start the music", "carry on playing", "freeze the video"],
  "next": ["next", "next one", "skip this one", "skip this", "skip the song", "play the next song", "play the next track", "go to the next song", "next video", "skip ahead to the next track", "move to the next one", "change the song", "another song", "I'm tired of this song, next", "not this song, skip"],
  "previous": ["previous", "previous one", "go back one song", "play the last song", "play the previous track", "the song before this", "back to the previous song", "go to the previous track", "previous video", "replay the last track", "back one song", "the one before", "rewind to the previous song"],
 },
 ("brightness", "direction"): {
  "up": ["brighten the screen", "brighter screen", "more brightness", "turn up the brightness", "screen brightness up", "increase screen brightness", "make the display brighter", "it's too dim", "I can't see the screen well", "bump the brightness", "light up the screen more", "boost the brightness", "make it brighter"],
  "down": ["darken the screen", "dimmer screen", "less brightness", "turn down the brightness", "screen brightness down", "reduce screen brightness", "make the display dimmer", "it's too bright", "the screen is hurting my eyes", "drop the brightness", "dim it a little", "make it dimmer", "lower the screen brightness"],
 },
 ("dark_mode", "state"): {
  "on": ["turn dark mode on", "put it in dark mode", "switch on dark mode", "dark theme", "dark appearance", "change to dark mode", "make it dark mode", "I want dark mode", "activate dark mode", "go to dark mode", "set the theme to dark", "night mode", "switch the Mac to dark"],
  "off": ["turn dark mode off", "put it in light mode", "switch off dark mode", "light theme", "light appearance", "change to light mode", "make it light mode", "I want light mode", "get out of dark mode", "set the theme to light", "day mode", "switch the Mac to light", "no more dark mode", "turn on light mode"],
 },
 ("window", "action"): {
  "left": ["snap left", "window left", "send this window left", "put the window on the left half", "this window on the left", "move the window to the left side of the screen", "left side please", "push this to the left", "left half of the screen", "stick this window to the left", "pin this to the left"],
  "right": ["snap right", "window right", "send this window right", "put the window on the right half", "this window on the right", "move the window to the right side of the screen", "right side please", "push this to the right", "right half of the screen", "stick this window to the right", "pin this to the right"],
  "top": ["snap to the top half", "window on the top half", "send this window to the top", "put the window in the upper half", "top half of the screen", "move this window up to the top half", "this goes on the top half", "upper half please"],
  "bottom": ["snap to the bottom half", "window on the bottom half", "send this window to the bottom", "put the window in the lower half", "bottom half of the screen", "move this window down to the bottom half", "this goes on the bottom half", "lower half please"],
  "maximize": ["maximize the window", "make this window bigger", "make the window larger", "fill the screen with this window", "expand this window", "make this take the whole screen", "stretch this window out", "biggest size", "enlarge the window", "window as large as it goes", "make the window full size"],
  "center": ["center this", "center the window on the screen", "put this window in the center", "move the window to the middle", "middle of the screen", "window in the middle", "bring this to the center", "center this app", "put it in the middle of the screen"],
  "full_screen": ["fullscreen", "go fullscreen", "make it full screen", "full screen this", "put this in full screen", "switch to full screen", "full screen please", "this app in full screen", "turn on full screen", "enter fullscreen mode", "watch this in full screen"],
  "minimize": ["minimize this", "minimize the window", "send this to the dock", "hide the window", "get this window out of the way", "put this away", "shrink this window", "collapse this window", "minimize this app", "drop this to the dock", "make this window go away for now"],
 },
 ("system", "action"): {
  "lock_screen": ["lock", "lock the Mac", "lock this computer", "lock my screen", "lock the laptop", "lock everything", "I'm going for lunch, lock it", "lock up", "put up the lock screen", "lock my computer now", "lock the machine", "I'm away, lock the screen", "screen lock"],
  "screenshot": ["take a screenshot of this", "grab the screen", "capture this", "screen capture", "screenshot the screen", "take a picture of the screen", "snap a screenshot", "capture what's on screen", "I need a screenshot", "get a screenshot", "screen grab", "take a snapshot of the screen", "save a picture of this screen"],
  "mission_control": ["show mission control", "show all my open windows", "all windows", "see all windows", "show every window", "overview of my windows", "what do I have open", "show all open apps", "window overview", "let me see everything open", "bring up mission control"],
  "show_desktop": ["go to the desktop", "show me the desktop", "reveal the desktop", "desktop", "hide everything", "move everything aside", "clear the windows away", "get the windows out of the way", "I need to see my desktop", "take me to the desktop", "show my desktop files"],
 },
 ("read_aloud", "action"): {
  "start": ["read this to me", "read it out", "read it aloud", "read the selected text", "read out the selection", "say this out loud", "read this paragraph aloud", "speak the selection", "can you read this", "read what I selected", "read that aloud", "read this page to me", "narrate this", "voice this"],
  "stop": ["stop", "stop reading that", "stop speaking", "quiet", "enough", "you can stop", "stop reading aloud", "shush", "silence", "cut the reading", "okay stop", "no more reading", "pause the reading"],
 },
}

SLOTS = [
 ("open_app", {"name": "{app}"}, ["open {app} for me", "launch the {app} app", "start up {app}", "{app}", "open my {app}", "go into {app}", "switch to the {app} app", "I want {app}", "I need to open {app}",
   "can I get {app}", "{app}, open it", "bring {app} up", "pop open {app}", "get {app} running", "show {app}", "run {app}", "boot up {app}", "head to {app}", "back to {app}", "focus {app}", "activate {app}",
   "let's go to {app}", "I want to work in {app}", "time to use {app}", "open {app} now", "where's {app}, open it", "change to {app}", "flip to {app}", "hop over to {app}", "put {app} in front",
   "I'd like to open {app}", "start the {app} application", "load {app}", "go back to {app}", "pull {app} up"]),
 ("quit_app", {"name": "{app}"}, ["quit {app} for me", "close the {app} app", "exit out of {app}", "shut {app}", "end {app}", "{app} can be closed", "I don't need {app} anymore", "close {app} completely",
   "force quit {app}", "turn off {app}", "stop running {app}", "close down {app}", "quit out of {app}", "make {app} quit", "I'm finished with {app}", "we're done with {app}, close it", "exit the {app} application",
   "shut {app} down", "kill the {app} app", "{app}, quit it"]),
 ("open_website", {"site": "{site}"}, ["open {site} for me", "go to the {site} site", "visit the {site} website", "{site} website", "open {site} in the browser", "browse to {site}", "I want to go to {site}",
   "can you open {site}", "get me to {site}", "let's go to {site}", "open up {site}", "launch {site}", "go on {site}", "check {site}", "bring me to {site}", "surf to {site}", "open the site {site}",
   "pull {site} up in a tab", "I need to visit {site}", "show {site}"]),
 ("web_search", {"query": "{q}"}, ["search for {q} online", "look up {q} for me", "search the internet for {q}", "web search {q}", "find {q}", "find me {q}", "I'm looking for {q}", "can you look up {q}",
   "search up {q}", "run a search for {q}", "I want to know about {q}", "check online for {q}", "look for {q} on the web", "do a web search on {q}", "find results for {q}", "show me results for {q}",
   "let's search {q}", "search on the web, {q}", "I need info on {q}", "see what you can find about {q}", "research {q}", "browse for {q}"]),
 ("web_search", {"query": "{q}", "site": "google"}, ["google for {q}", "search on Google for {q}", "find {q} on Google", "google me {q}", "check Google for {q}", "use Google to find {q}", "I want to google {q}", "ask Google about {q}", "Google it, {q}", "search {q} in Google"]),
 ("web_search", {"query": "{q}", "site": "youtube"}, ["search on YouTube for {q}", "YouTube search {q}", "videos of {q}", "find videos on {q}", "watch {q} on YouTube", "look for {q} videos on YouTube", "check YouTube for {q}", "I want to watch videos about {q}", "open YouTube and search {q}", "show me {q} on YouTube"]),
 ("web_search", {"query": "{q}", "site": "wikipedia"}, ["search on Wikipedia for {q}", "Wikipedia article on {q}", "check Wikipedia for {q}", "what does Wikipedia say about {q}", "open the Wikipedia entry for {q}", "wiki {q}", "read about {q} on Wikipedia"]),
 ("web_search", {"query": "{q}", "site": "amazon"}, ["search on Amazon for {q}", "Amazon {q}", "look up {q} on Amazon", "buy {q} on Amazon", "find me {q} on Amazon", "show {q} on Amazon", "see {q} prices on Amazon", "order {q} from Amazon"]),
 ("web_search", {"query": "{q}", "site": "maps"}, ["find {q} on Maps", "search Google Maps for {q}", "where is {q} on the map", "map of {q}", "look for {q} on the map", "show me {q} in Maps", "locate {q} on the map"]),
 ("web_search", {"query": "{q}", "site": "github"}, ["search on GitHub for {q}", "GitHub {q}", "look for {q} repos on GitHub", "find repositories about {q} on GitHub", "check GitHub for {q}"]),
 ("web_search", {"query": "{q}", "site": "reddit"}, ["search on Reddit for {q}", "Reddit {q}", "look up {q} on Reddit", "check Reddit for {q}", "see Reddit threads about {q}", "find Reddit posts on {q}"]),
 ("web_search", {"query": "{q}", "site": "chatgpt"}, ["ask Chat GPT about {q}", "ChatGPT, {q}", "send {q} to ChatGPT", "get ChatGPT to explain {q}", "ask ChatGPT to tell me about {q}", "open ChatGPT and ask {q}"]),
 ("web_search", {"query": "{q}", "site": "claude"}, ["Claude, {q}", "send {q} to Claude", "get Claude to explain {q}", "open Claude and ask {q}", "ask Claude to tell me about {q}", "have Claude look into {q}"]),
 ("web_search", {"query": "{q}", "site": "perplexity"}, ["Perplexity {q}", "ask Perplexity about {q}", "look up {q} on Perplexity", "use Perplexity to research {q}", "open Perplexity and ask {q}"]),
 ("find_file", {"query": "{file}"}, ["find {file}", "search for {file} on my Mac", "find my file {file}", "look up {file} in my files", "where's {file}", "I need {file}, find it", "search this computer for {file}",
   "locate {file}", "find the document {file}", "pull up {file} from my files", "look through my files for {file}", "can you find {file} on my laptop", "I'm looking for {file} on this Mac", "search Finder for {file}",
   "check my documents for {file}", "hunt down {file}", "which folder has {file}", "find where I put {file}", "spotlight search {file}", "get me {file} from my computer"]),
 ("press_keys", {"keys": "{keys}"}, ["press {keyname} for me", "hit {keyname} now", "tap the {keyname} keys", "do a {keyname}", "send {keyname}", "type the shortcut {keyname}", "key press {keyname}", "trigger {keyname}",
   "push the keys {keyname}", "I need you to press {keyname}", "keyboard shortcut {keyname}", "{keyname}", "press down {keyname}", "hit the shortcut {keyname}", "fire {keyname}"]),
 ("set_volume", {"percent": "{n}"}, ["volume at {n}", "set volume {n}", "sound to {n}", "sound {n} percent", "make it {n} percent volume", "volume level {n}", "set the audio to {n} percent", "adjust the volume to {n}",
   "drop the volume to {n}", "bump the volume to {n}", "lower the volume to {n} percent", "increase the volume to {n} percent", "I want it at {n} percent volume", "{n} percent volume", "volume should be {n}",
   "get the volume to {n}", "move the volume to {n}", "set the speakers to {n} percent", "keep the volume at {n}", "turn it to {n} percent"]),
 ("click", {"label": "{btn}"}, ["click {btn} for me", "click the button {btn}", "press {btn}", "press on {btn}", "tap the {btn} button", "tap on {btn}", "hit {btn}", "push {btn}", "click where it says {btn}",
   "click the one that says {btn}", "press the {btn} link", "select the {btn} option", "choose the {btn} button", "pick {btn}", "click the {btn} tab", "hit the {btn} link", "I want to click {btn}",
   "find the {btn} button and click it", "use the {btn} button", "activate the {btn} button", "click on the {btn} option", "the {btn} button, click it"]),
 ("type_text", {"text": "{text}"}, ["type this, {text}", "type the following, {text}", "write out {text}", "write the words {text}", "enter {text}", "input {text}", "type exactly {text}", "put down {text}",
   "insert the text {text}", "write down here {text}", "fill in {text}", "type this in, {text}", "add the text {text}", "I want you to type {text}", "just type {text}", "type the message {text}",
   "write this, {text}", "spell out {text}"]),
 ("add_reminder", {"task": "{task}", "when": "{when}"}, ["remind me {when} that I need to {task}", "set a reminder for {when} to {task}", "reminder {when}, {task}", "I have to {task} {when}, remind me",
   "{when} remind me to {task}", "ping me {when} to {task}", "can you remind me to {task} {when}", "add a reminder for {when}, {task}", "I need to {task} {when}, set a reminder", "make a reminder to {task} {when}",
   "put a reminder to {task} {when}", "give me a reminder {when} to {task}", "alert me {when} to {task}", "tell me to {task} {when}", "remember to remind me to {task} {when}", "schedule a reminder to {task} {when}"]),
 ("add_reminder", {"task": "{task}"}, ["I need to remember to {task}", "make a reminder to {task}", "create a reminder to {task}", "remind me I have to {task}", "put {task} in my reminders", "new reminder, {task}",
   "reminder, {task}", "add {task} to my to-do list", "I have to {task}, remind me", "can you remind me to {task}", "note a reminder to {task}", "stick {task} in reminders", "add a to-do to {task}",
   "I shouldn't forget to {task}", "help me remember to {task}"]),
 ("add_event", {"title": "{event}", "when": "{when}"}, ["schedule {event} for {when}", "add {event} {when} to the calendar", "put {event} in my calendar for {when}", "create a calendar event for {event} {when}",
   "new event, {event} {when}", "book {event} for {when}", "calendar, {event} {when}", "I've got {event} {when}, put it on the calendar", "set up a calendar invite for {event} {when}", "mark {event} on my calendar {when}",
   "add an event called {event} {when}", "{when} I have {event}, add it to my calendar", "plan {event} for {when}", "block my calendar {when} for {event}", "make a calendar entry, {event} {when}",
   "put {event} down for {when}", "arrange {event} {when}", "create a meeting {event} {when}"]),
 ("add_event", {"title": "{event}", "when": "{when}", "minutes": "{durm}"}, ["schedule {dur} for {event} {when}", "add {event} {when} lasting {dur}", "block {dur} {when} for {event}", "create a {dur} event {event} {when}",
   "put {event} on the calendar {when}, {dur} long", "book {dur} {when} for {event}", "{event} {when} for {dur}, add it to my calendar", "set up {event} {when}, make it {dur}", "new {dur} meeting {event} {when}"]),
 ("set_timer", {"minutes": "{durm}"}, ["timer, {dur}", "set timer {dur}", "put a timer on for {dur}", "start counting down {dur}", "{dur} timer", "{dur} on the clock", "time me for {dur}", "countdown for {dur}",
   "wake me in {dur}", "tell me when {dur} is up", "alert me in {dur}", "start a countdown of {dur}", "I need a timer for {dur}", "can you set a timer for {dur}", "run a timer for {dur}", "set an alarm for {dur} from now",
   "ping me in {dur}", "buzz me in {dur}", "make a {dur} timer", "start the clock for {dur}"]),
 ("set_timer", {"minutes": "{durm}", "label": "{label}"}, ["timer for {label}, {dur}", "set a {dur} timer called {label}", "start a timer for {label} for {dur}", "{label} timer, {dur}", "put {dur} on the timer for {label}",
   "countdown {dur} for {label}", "set {dur} for {label}", "I need a {dur} timer for {label}", "run a {dur} timer for {label}", "{dur} for {label}, start a timer"]),
 ("save_note", {"text": "{note}"}, ["note, {note}", "note this down, {note}", "make a note that {note}", "save this note, {note}", "take this down, {note}", "new note, {note}", "write a note, {note}", "add to my notes, {note}",
   "jot this down, {note}", "save this thought, {note}", "keep this in my notes, {note}", "I want to note that {note}", "note for later, {note}", "record a note, {note}", "put this in my notes, {note}",
   "store a note, {note}", "remember this, {note}", "scribble this down, {note}", "log this, {note}", "don't lose this, {note}"]),
 ("search_history", {"query": "{q}"}, ["what did I dictate about {q}", "what did I write about {q}", "search my dictation history for {q}", "find my dictation about {q}", "look through my history for {q}",
   "find the thing I said about {q}", "search what I said earlier for {q}", "have I said anything about {q}", "show my past dictations about {q}", "pull up what I dictated on {q}", "look up my old dictation on {q}",
   "find my earlier message about {q}", "what was it I said about {q}", "check my history for {q}", "search my previous dictations about {q}", "when did I talk about {q}"]),
 ("compose_email", {}, ["start a new email", "new mail", "new email message", "open a blank email", "I want to write an email", "I need to send an email", "begin an email", "new message in mail", "let's write an email",
   "open an email draft", "start drafting an email", "get a new email going", "fresh email", "create an email"]),
 ("compose_email", {"to": "{person}"}, ["email to {person}", "start an email for {person}", "write {person} an email", "I need to email {person}", "send {person} an email", "open a new email to {person}", "mail {person}",
   "begin an email to {person}", "I want to email {person}", "new message to {person} by email", "let's email {person}", "create an email for {person}", "drop an email to {person}", "get an email started to {person}",
   "write a mail to {person}", "shoot an email to {person}"]),
 ("compose_email", {"to": "{person}", "subject": "{subject}"}, ["email {person} regarding {subject}", "write {person} an email about {subject}", "start an email to {person} with the subject {subject}", "new email for {person}, subject {subject}",
   "compose an email to {person} about {subject}", "I need to email {person} about {subject}", "mail {person} about {subject}", "draft a message to {person} about {subject}", "send an email about {subject} to {person}",
   "write to {person} about {subject}", "an email to {person} on {subject}", "email about {subject} for {person}", "let {person} know about {subject} by email", "open an email to {person}, the subject is {subject}"]),
 ("compose_email", {"to": "{person}", "body": "{reply}"}, ["email {person} that {reply}", "write an email to {person} saying {reply}", "send {person} an email saying {reply}", "tell {person} by email that {reply}", "draft an email to {person}, {reply}",
   "email to {person}, say {reply}", "mail {person} and say {reply}", "compose an email to {person} that says {reply}", "write {person} an email, {reply}", "let {person} know by email, {reply}", "new email to {person} with the message {reply}",
   "send a mail to {person} telling them {reply}", "shoot {person} an email that says {reply}"]),
 ("get_directions", {"destination": "{place}"}, ["directions for {place}", "show directions to {place}", "how do I reach {place}", "how to get to {place}", "navigate me to {place}", "find a route to {place}",
   "map the way to {place}", "I need directions to {place}", "what's the way to {place}", "take me to {place} on the map", "guide me to {place}", "start navigation to {place}", "how far is {place}, show the route",
   "drive to {place}", "walking directions to {place}", "open directions to {place}", "I want to go to {place}, get directions", "get me a route to {place}", "plot a route to {place}", "which way to {place}"]),
 ("rewrite_selection", {"instruction": "{rewrite}"}, ["{rewrite}"]),
 ("reply", {"intent": "{reply}"}, ["reply to this saying {reply}", "reply and say {reply}", "respond with {reply}", "respond that {reply}", "write a reply that {reply}", "write back saying {reply}", "answer saying {reply}",
   "answer them that {reply}", "send a reply, {reply}", "reply to them, {reply}", "reply back {reply}", "draft a reply saying {reply}", "let them know {reply}", "say back that {reply}", "reply to this message with {reply}",
   "respond to this email saying {reply}", "write a response, {reply}", "tell them in reply that {reply}", "shoot back a reply, {reply}", "reply, {reply}"]),
 ("translate", {"text": "{phrase}", "language": "{lang}"}, ["translate {phrase} in {lang}", "{phrase} in {lang}", "translate this to {lang}, {phrase}", "how would I say {phrase} in {lang}", "how to say {phrase} in {lang}",
   "give me {phrase} in {lang}", "write {phrase} in {lang}", "what's {phrase} in {lang}", "{lang} for {phrase}", "the {lang} translation of {phrase}", "translate into {lang}, {phrase}", "convert {phrase} to {lang}",
   "type {phrase} in {lang}", "can you translate {phrase} to {lang}", "in {lang} please, {phrase}", "say this in {lang}, {phrase}", "{phrase}, translate that to {lang}", "render {phrase} in {lang}"]),
 ("class_notes", {}, ["start class mode", "begin lecture notes", "start the lecture notes", "I'm in class, take notes", "open lecture mode", "record this lecture", "take notes for this class", "start recording the class",
   "class is starting", "lecture mode", "begin taking notes for the lecture", "note down this lecture", "start my class notes", "my class is about to begin, start notes"]),
 ("class_notes", {"query": "{q}"}, ["search class notes for {q}", "find {q} in my lecture notes", "look in my class notes for {q}", "what did the professor say about {q}", "search my lectures for {q}", "check my class notes for {q}",
   "find notes on {q}", "do my class notes mention {q}", "search my lecture notes about {q}", "pull up my class notes on {q}", "where in my notes is {q}", "look through my lectures for {q}", "search note for {q}"]),
 ("run_shortcut", {"name": "{sc}"}, ["run {sc} shortcut", "run my shortcut {sc}", "launch the {sc} shortcut", "do the {sc} shortcut", "fire the {sc} shortcut", "activate the {sc} shortcut", "use the {sc} shortcut",
   "start my {sc} shortcut", "run the Apple shortcut {sc}", "shortcut {sc}", "play the {sc} shortcut", "I want to run the {sc} shortcut", "can you run {sc} shortcut", "call the {sc} shortcut", "run the shortcut named {sc}",
   "go ahead and run my {sc} shortcut"]),
 ("transcribe_file", {}, ["transcribe a file for me", "transcribe this recording", "transcribe an audio recording", "I need to transcribe a recording", "transcribe a video", "get a transcript of a file", "make a transcript from a recording",
   "write out what's said in a file", "transcribe my voice memo", "pick a file to transcribe", "open a file and transcribe it", "transcribe this podcast file", "transcribe an interview recording", "convert audio to text",
   "I have a recording I want transcribed", "speech to text for a file", "transcribe the meeting audio"]),
]

SUBJ = ["I", "we", "she", "he", "they", "my manager", "the team", "our client", "my sister", "the teacher", "everyone"]
NEG_FRAMES = [
 "{s} opened the {o} and nothing happened", "{s} already closed the {o} yesterday", "the {o} was on mute the whole time", "{s} couldn't find the {o} anywhere", "the {o} keeps scrolling by itself",
 "{s} saved the {o} twice by accident", "that {o} is taking up the whole screen", "{s} said the {o} was too loud", "the {o} is brighter than the old one", "{s} copied the {o} from last year",
 "the timer on the {o} never works", "{s} will email about the {o} later", "the {o} reminded {s} of home", "{s} searched for the {o} all morning", "there's a new {o} in the office",
 "{s} pressed the {o} too hard", "the {o} was translated badly", "{s} took a note about the {o}", "the {o} got deleted somehow", "{s} can't remember where the {o} went",
 "I think the {o} looks fine", "honestly the {o} was better before", "do you know if the {o} is ready", "{s} will print the {o} tomorrow maybe", "the {o} is in dark blue",
 "{s} had to quit the {o} early", "the {o} played for an hour", "{s} skipped the {o} last week", "the window near the {o} is broken", "{s} typed up the {o} last night"]
NEG_OBJ = ["report", "presentation", "meeting", "project", "invoice", "movie", "song", "book", "article", "spreadsheet", "door", "printer", "package", "recipe", "speaker", "lamp", "curtain", "garage",
           "schedule", "contract", "photo album", "playlist", "letter", "ticket", "phone", "tablet", "heater", "microwave", "form", "survey"]
NEG_PLAIN = """how was your weekend|I'll see you at the usual place|that was a really long day|the traffic was terrible this morning|let me think about it|I'm not feeling great today|
we should grab lunch sometime|did you watch the game last night|the kids are finally asleep|it's raining again|I can't believe it's already October|my back hurts from sitting|
that sounds like a plan|I was just about to say that|tell me more about your trip|what do you think we should do|the food was amazing|I'm so tired|we're almost there|
the results come out next week|he's moving to a new city|they just had a baby|I really enjoyed the book|it costs way too much|let's talk about something else|
I have no idea what happened|that's exactly what I meant|maybe we can try again next time|the presentation went better than expected|I need a vacation|
yes|no|maybe|sure|right|hmm|okay then|thank you|thanks a lot|sorry about that|wait what|hello|testing|never mind that|forget it|one second|
the quick brown fox jumps over the lazy dog|can you hear me|is this thing on|I was saying something else|actually nothing|scratch that""".replace("\n", "").split("|")

def negatives():
    out = list(NEG_PLAIN)
    for _ in range(420):
        out.append(rng.choice(NEG_FRAMES).format(s=rng.choice(SUBJ), o=rng.choice(NEG_OBJ)))
    return sorted(set(out))

def extend(g):
    """Adds all of the above to build_dataset's training pools. Anything the test set uses is kept out."""
    def grow(name, extra, key=lambda v: v):
        held = {str(key(v)).lower() for v in g[name + "_TEST"]} if name + "_TEST" in g else set()
        have = {str(key(v)).lower() for v in g[name]}
        g[name] += [v for v in dict.fromkeys(extra) if str(key(v)).lower() not in held and str(key(v)).lower() not in have] if not isinstance(extra[0], tuple) else \
                   [v for v in extra if str(key(v)).lower() not in held and str(key(v)).lower() not in have]
    grow("APPS", APPS); grow("SITES", SITES); grow("QUERIES", queries()); grow("FILES", FILES); grow("PEOPLE", PEOPLE); grow("TASKS", TASKS); grow("WHENS", WHENS)
    grow("EVENTS", EVENTS); grow("NOTES", NOTES); grow("BUTTONS", BUTTONS); grow("PLACES", PLACES); grow("LANGS", LANGS); grow("PHRASES", PHRASES); grow("REWRITES", REWRITES)
    grow("REPLIES", SENTENCES); grow("SHORTCUTS", SHORTCUTS); grow("TEXTS", TEXTS); grow("KEYS", keys(), key=lambda v: v[0]); grow("DURS", durations(), key=lambda v: v[0])
    g["MORE_LABELS"] += LABELS; g["MORE_SUBJECTS"] += SUBJECTS
    for n in range(0, 101): g["NUM_WORDS"].setdefault(n, number_word(n))
    g["VOLUMES"] = [n for n in range(1, 101) if n not in (35, 45, 55, 65, 85)]

    test_phrasings = {p.lower() for p, _, _ in g["TEST"]} | {n.lower() for n in g["NEGATIVES_TEST"]}
    seen = {(p.lower(), t) for p, t, _ in g["TRAIN"]}
    def add(phrasing, tool, args):
        if phrasing.lower() in test_phrasings or (phrasing.lower(), tool) in seen: return
        seen.add((phrasing.lower(), tool)); g["TRAIN"].append((phrasing, tool, dict(args)))
    for (tool, key), table in FIXED.items():
        for value, phrasings in table.items():
            for p in phrasings: add(p, tool, {key: value})
    for tool, args, phrasings in SLOTS:
        for p in phrasings: add(p, tool, args)
    g["NEGATIVES"] += [n for n in negatives() if n.lower() not in test_phrasings and n not in g["NEGATIVES"]]

# ── Round 3: the three weak spots of the second model ───────────────────────────────────────────────────────
# 1. It shortened long free text ("running shoes for flat feet" → "running shoes"): many longer things to copy.
# 2. It acted on ordinary sentences that happen to contain a command word: many more of those, as no_action.
# 3. It dropped steps from three-step chains: more and longer chains (see build_dataset.py).

QUALIFIERS = ["for small apartments", "for people with bad knees", "under five hundred dollars", "that ship internationally", "with free delivery", "for a family of four",
              "open on Sundays", "open late tonight", "with good reviews", "for complete beginners", "without a subscription", "that work offline", "for left handed people",
              "for long flights", "in walking distance", "with vegetarian options", "for rainy weather", "made in India", "with a student discount", "for older laptops",
              "that don't need wifi", "for dry skin", "with a long battery life", "for cold climates", "on a tight budget", "for two people", "before the end of the month",
              "for a ten year old", "with step by step instructions", "that are easy to clean", "for working parents", "near the city center", "for wide feet", "at the weekend"]
def long_queries():
    out = set()
    while len(out) < 1500:
        t, q = rng.choice(TOPICS), rng.choice(QUALIFIERS)
        out.add(rng.choice(["{t} {q}", "best {t} {q}", "cheap {t} {q}", "{t} in {c} {q}", "how to choose {t} {q}", "where to find {t} {q}", "difference between {t} and {t2}",
                            "{t} and {t2} compared", "is {t} better than {t2} {q}", "what to know about {t} before buying", "requirements for {t} in {c}", "{t} that are {q2} and {q3}"])
                .format(t=t, t2=rng.choice(TOPICS), q=q, c=rng.choice(CITIES), q2=rng.choice(["cheap", "reliable", "popular", "new", "small", "quiet"]), q3=rng.choice(["easy to use", "well reviewed", "good for travel", "safe for kids"])))
    return sorted(out)

CLAUSES = ["and I'll explain the rest when we meet", "but only if the weather holds", "so please don't wait for me", "because the client moved the deadline", "and thanks again for covering",
           "unless you hear otherwise from me", "and we can sort out the details later", "so let's plan around that", "but I might be a few minutes late", "and bring the signed copy with you",
           "since the office is closed on Monday", "and tell the others for me", "if that still works for you", "as soon as the review is done", "and no need to reply"]
def long_sentences():
    return sorted({f"{s} {c}" for s in SENTENCES for c in rng.sample(CLAUSES, 4)})

MORE_SLOTS = [
 ("type_text", {"text": "{text}"}, ["punch in {text}", "put {text} in here", "enter the words {text}", "type in the words {text}", "write in {text}", "add the words {text}", "type the sentence {text}", "write the line {text}",
   "put the text {text} here", "the text is {text}, type it", "{text}, type that", "type this for me, {text}", "drop in the words {text}"]),
 ("reply", {"intent": "{reply}"}, ["reply {reply}", "tell them {reply}", "write back that {reply}", "send a reply that says {reply}", "reply to say {reply}", "say {reply} in the reply", "answer with {reply}", "respond, {reply}",
   "get back to them saying {reply}", "the reply should say {reply}"]),
 ("save_note", {"text": "{note}"}, ["a quick one to note, {note}", "note down that {note}", "save this, {note}", "put a note, {note}", "one for my notes, {note}", "write a note that says {note}", "keep track of this, {note}"]),
 ("search_history", {"query": "{q}"}, ["did I say something about {q}", "find where I talked about {q}", "anything in my dictations about {q}", "go back through what I dictated for {q}", "search everything I dictated for {q}"]),
 ("find_file", {"query": "{file}"}, ["I can't find {file}, look on the Mac", "I lost {file}, search for it", "where did {file} go", "help me find {file}", "search the Mac for {file}", "dig out {file}", "track down {file} in my documents",
   "where have I kept {file}", "look for the file {file}"]),
 ("translate", {"text": "{phrase}", "language": "{lang}"}, ["I want {phrase} in {lang}", "get me {phrase} in {lang}", "{phrase} but in {lang}", "turn {phrase} into {lang}", "make {phrase} {lang}", "I need to say {phrase} in {lang}",
   "{phrase}, in {lang} please", "change {phrase} to {lang}"]),
 ("add_reminder", {"task": "{task}", "when": "{when}"}, ["poke me {when} to {task}", "I must {task} {when}, remind me", "see that I {task} {when}", "{when} I need to {task}, remind me", "buzz me {when} about needing to {task}",
   "remind me {when}, I need to {task}", "don't let me skip this, {task} {when}"]),
 ("add_event", {"title": "{event}", "when": "{when}"}, ["{event} is {when}, put it on my calendar", "there's {event} {when}, add it", "note {event} in the calendar for {when}", "add to calendar, {event} {when}", "I'm doing {event} {when}, calendar it",
   "calendar this, {event} {when}", "make an event for {event} {when}"]),
 ("click", {"label": "{btn}"}, ["click the thing that says {btn}", "press the button labelled {btn}", "hit the one marked {btn}", "tap where it says {btn}", "the button called {btn}, press it", "now click {btn}", "then press {btn}"]),
 ("web_search", {"query": "{q}"}, ["I need to find out {q}", "look this up, {q}", "search this, {q}", "find information on {q}", "get me information about {q}", "I want to look up {q}", "do some searching on {q}", "can you search {q}",
   "need to look up {q}", "check the web for {q}"]),
 ("web_search", {"query": "{q}", "site": "google"}, ["do a google search on {q}", "google this, {q}", "run {q} through Google", "put {q} into Google", "look on Google for {q}", "search google, {q}"]),
 ("open_app", {"name": "{app}"}, ["get me {app}", "get into {app}", "take me into {app}", "{app} now", "I'd like {app}", "let me use {app}", "over to {app}", "move to {app}", "let me have {app}", "open {app} please", "I want to see {app}"]),
 ("open_website", {"site": "{site}"}, ["I want to look at {site}", "take a look at {site}", "over to {site}", "get {site} open", "I want to see {site}", "let me check {site}", "pull up the {site} page", "go check {site}"]),
 ("press_keys", {"keys": "{keys}"}, ["give me a {keyname}", "press the {keyname} combination", "use {keyname}", "the shortcut {keyname}, press it", "hit {keyname} on the keyboard", "do the key combo {keyname}"]),
]
MORE_FIXED = {
 ("browser", "action"): {"forward": ["move ahead a page", "ahead one page", "go to the next page in history", "step forward a page", "onward one page", "the next page forward"],
                         "back": ["step back a page", "one page back", "go to the page I was on before", "backward one page"]},
 ("edit", "action"): {"redo": ["put it back the way it was before I undid", "bring my change back", "restore the change I undid", "redo, I want that change back", "reapply my last change"],
                      "undo": ["go back one edit", "take back my last change", "one step back in my edits", "revert my last edit"],
                      "select_all": ["grab everything", "select all of the text here", "take all the text", "pick everything on the page"],
                      "paste": ["put that in here", "drop it in here", "place what I copied here", "stick the clipboard here"]},
 ("press_keys", "keys"): {"up": ["press the up arrow", "hit up arrow", "tap the up arrow key", "up arrow key"], "down": ["press the down arrow", "hit down arrow", "tap the down arrow key"],
                          "left": ["press the left arrow", "hit left arrow"], "right": ["press the right arrow", "hit right arrow"]},
 ("system", "action"): {"lock_screen": ["I'm leaving, lock the laptop", "lock it, I'm heading out", "keep the Mac safe, lock it", "lock the laptop before I go"]},
}

WORDS_IN_SENTENCES = [
 "that's a {adj} move on their part", "it was a bold decision to {v}", "the bold text in the report stood out", "her reminder about the {o} was useful", "the reminder {s} sent was kind",
 "my calendar is full until the {o}", "the calendar on the wall is from last year", "{s} opened the {o} and read it carefully", "{s} read the {o} out loud at dinner", "the tab for the {o} was expensive",
 "there's a tab on the folder for the {o}", "the window in the {o} room faces east", "{s} closed the window because of the rain", "the volume of the {o} surprised everyone", "turn out {s} was right about the {o}",
 "the search for the {o} is still going", "{s} was searching for a new {o}", "the copy of the {o} is on your desk", "{s} made a copy for the {o}", "the paste on the {o} dried quickly",
 "{s} had to cut the {o} short", "cut the cake after the {o}", "the save by the goalkeeper won the {o}", "{s} tried to save money for the {o}", "the print on the {o} is too small",
 "{s} undid the knot on the {o}", "they muted the {o} discussion for now", "{s} played the {o} at the wedding", "the next {o} starts in the spring", "the previous {o} was much better",
 "{s} skipped breakfast before the {o}", "the screen at the {o} was huge", "{s} locked the {o} before leaving", "the brightness of the {o} was stunning", "it gets dark early near the {o}",
 "the light in the {o} is perfect", "{s} minimized the risk in the {o}", "the full screen version of the {o} was better", "the center of the {o} is crowded", "{s} moved to the left side of the {o}",
 "the timer went off during the {o}", "{s} timed the {o} at ten minutes", "the note on the {o} was sweet", "{s} noted that the {o} was late", "the email about the {o} never arrived",
 "{s} emailed me about the {o} last week", "the directions to the {o} were unclear", "{s} translated the {o} for the guests", "the reply to the {o} was rude", "{s} replied about the {o} already",
 "the shortcut through the {o} saves time", "{s} transcribed the {o} by hand", "the file on the {o} is thick", "{s} filed the {o} under taxes", "the button on my {o} fell off",
 "{s} clicked with the {o} right away", "the keys to the {o} are missing", "{s} pressed the {o} for details", "typing the {o} took all night", "the scroll in the {o} is ancient",
 "{s} zoomed past the {o}", "the page about the {o} was torn", "refresh my memory about the {o}", "back in the day the {o} was cheaper", "going forward the {o} will change",
 "{s} quit the {o} last month", "the app for the {o} is confusing", "the website for the {o} is down again", "the multi {o} setup is not working", "that command about the {o} made no sense",
 "nothing about the {o} is working", "the {o} feature is not working today", "{s} asked me to open up about the {o}", "{s} is open to the {o} idea", "{s} set the {o} on the table",
 "remind {s} that the {o} matters", "I was reminded of the {o} again", "schedule wise the {o} is tight", "{s} booked the {o} months ago", "I think {s} should look into the {o}",
 "what I meant was the {o}", "it's about the {o} not the money", "can we talk about the {o} later", "why did {s} bring up the {o}", "I wonder how the {o} is going"]
ADJS = ["bold", "smart", "risky", "strange", "generous", "clever"]
VERBS_NEG = ["leave early", "sell the house", "start over", "say no", "move abroad", "change teams"]
def more_negatives():
    out = set()
    for f in WORDS_IN_SENTENCES:
        for _ in range(22):
            out.add(f.format(s=rng.choice(SUBJ), o=rng.choice(NEG_OBJ), adj=rng.choice(ADJS), v=rng.choice(VERBS_NEG)))
    # Two ordinary sentences in a row are still not a command.
    plain = list(out)
    for _ in range(300):
        a, b = rng.sample(plain, 2)
        out.add(f"{a}{rng.choice([' and ', ', and ', '. ', ' but '])}{b}")
    return sorted(out)

def extend3(g):
    test_values = {v.lower() for name in ("QUERIES_TEST", "REPLIES_TEST", "NOTES_TEST", "TEXTS_TEST", "PHRASES_TEST") for v in g[name]}
    g["QUERIES"] += [q for q in long_queries() if q.lower() not in test_values]
    longer = [s for s in long_sentences() if s.lower() not in test_values]
    g["REPLIES"] += longer[:260]; g["NOTES"] += longer[260:520]; g["TEXTS"] += longer[520:780]
    test_phrasings = {p.lower() for p, _, _ in g["TEST"]} | {n.lower() for n in g["NEGATIVES_TEST"]}
    seen = {(p.lower(), t) for p, t, _ in g["TRAIN"]}
    def add(phrasing, tool, args):
        if phrasing.lower() in test_phrasings or (phrasing.lower(), tool) in seen: return
        seen.add((phrasing.lower(), tool)); g["TRAIN"].append((phrasing, tool, dict(args)))
    for tool, args, phrasings in MORE_SLOTS:
        for p in phrasings: add(p, tool, args)
    for (tool, key), table in MORE_FIXED.items():
        for value, phrasings in table.items():
            for p in phrasings: add(p, tool, {key: value})
    have = {n.lower() for n in g["NEGATIVES"]}
    g["NEGATIVES"] += [n for n in more_negatives() if n.lower() not in test_phrasings and n.lower() not in have]
