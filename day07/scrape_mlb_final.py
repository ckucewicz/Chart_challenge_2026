"""
MLB salary scraper — all 30 teams from baseball-reference.com
Strictly grabs the 2026 salary column only. No fallback dollar scanning.

Usage:
    python scrape_mlb_final.py
Output: mlb_salaries.csv
"""

import requests
from bs4 import BeautifulSoup
import pandas as pd
import time, re, sys

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/123.0 Safari/537.36",
    "Accept-Language": "en-US,en;q=0.9",
    "Referer": "https://www.baseball-reference.com/",
}

TEAMS = [
    ("ARI","arizona-diamondbacks",  "Arizona Diamondbacks",  "NL West"),
    ("ATL","atlanta-braves",        "Atlanta Braves",         "NL East"),
    ("BAL","baltimore-orioles",     "Baltimore Orioles",      "AL East"),
    ("BOS","boston-red-sox",        "Boston Red Sox",         "AL East"),
    ("CHC","chicago-cubs",          "Chicago Cubs",           "NL Central"),
    ("CHW","chicago-white-sox",     "Chicago White Sox",      "AL Central"),
    ("CIN","cincinnati-reds",       "Cincinnati Reds",        "NL Central"),
    ("CLE","cleveland-guardians",   "Cleveland Guardians",    "AL Central"),
    ("COL","colorado-rockies",      "Colorado Rockies",       "NL West"),
    ("DET","detroit-tigers",        "Detroit Tigers",         "AL Central"),
    ("HOU","houston-astros",        "Houston Astros",         "AL West"),
    ("KCR","kansas-city-royals",    "Kansas City Royals",     "AL Central"),
    ("ANA","los-angeles-angels",    "Los Angeles Angels",     "AL West"),
    ("LAD","los-angeles-dodgers",   "Los Angeles Dodgers",    "NL West"),
    ("FLA","miami-marlins",         "Miami Marlins",          "NL East"),
    ("MIL","milwaukee-brewers",     "Milwaukee Brewers",      "NL Central"),
    ("MIN","minnesota-twins",       "Minnesota Twins",        "AL Central"),
    ("NYM","new-york-mets",         "New York Mets",          "NL East"),
    ("NYY","new-york-yankees",      "New York Yankees",       "AL East"),
    ("OAK","athletics",             "Athletics",              "AL West"),
    ("PHI","philadelphia-phillies", "Philadelphia Phillies",  "NL East"),
    ("PIT","pittsburgh-pirates",    "Pittsburgh Pirates",     "NL Central"),
    ("SDP","san-diego-padres",      "San Diego Padres",       "NL West"),
    ("SFG","san-francisco-giants",  "San Francisco Giants",   "NL West"),
    ("SEA","seattle-mariners",      "Seattle Mariners",       "AL West"),
    ("STL","st-louis-cardinals",    "St. Louis Cardinals",    "NL Central"),
    ("TBD","tampa-bay-rays",        "Tampa Bay Rays",         "AL East"),
    ("TEX","texas-rangers",         "Texas Rangers",          "AL West"),
    ("TOR","toronto-blue-jays",     "Toronto Blue Jays",      "AL East"),
    ("WSN","washington-nationals",  "Washington Nationals",   "NL East"),
]

def parse_salary(s):
    """Parse $40M, $14.5M, $2.16M, $894,000 etc. Returns None if not a salary."""
    s = str(s).strip()
    # Skip non-salary values
    if not s or s in ('FA', 'Arb', 'nan', '', '-', 'N/A'):
        return None
    # Skip anything that looks like an arbitration estimate label
    if s.lower().startswith('arb'):
        return None
    # "$40M" or "$14.5M"
    m = re.match(r'^\$?([\d.]+)M$', s)
    if m:
        return int(float(m.group(1)) * 1_000_000)
    # "$894,000" or "$1,200,000"
    m = re.match(r'^\$?([\d,]+)$', s.replace(',', ''))
    if m:
        v = int(m.group(1).replace(',', ''))
        # Sanity check: MLB salary must be between $500K and $50M for a single year
        if 500_000 <= v <= 50_000_000:
            return v
    return None

def scrape_team(abbr, slug, team_name, division):
    url = f"https://www.baseball-reference.com/teams/{abbr}/{slug}-salaries-and-contracts.shtml"
    try:
        r = requests.get(url, headers=HEADERS, timeout=25)
        r.raise_for_status()
    except Exception as e:
        print(f"  ✗ {team_name}: {e}")
        return []

    soup = BeautifulSoup(r.text, "lxml")
    table = (soup.find("table", id=re.compile("salary", re.I))
             or soup.find("table", id=re.compile("contract", re.I))
             or soup.find("table"))
    if not table:
        print(f"  ✗ {team_name}: no table found")
        return []

    # Find header row and locate EXACTLY the 2026 column
    header_row = None
    for tr in table.find_all('tr'):
        cells = tr.find_all(['th', 'td'])
        texts = [c.get_text(strip=True) for c in cells]
        if '2026' in texts:
            header_row = texts
            break

    if not header_row:
        print(f"  ✗ {team_name}: no 2026 column found in headers: {header_row}")
        return []

    # Get the index of the FIRST occurrence of '2026'
    sal_col = header_row.index('2026')
    print(f"      Found '2026' at column {sal_col}", end=" ")

    rows = []
    tbody = table.find("tbody") or table
    for tr in tbody.find_all("tr"):
        cls = tr.get("class", [])
        if any(c in cls for c in ["thead", "spacer", "partial_table"]):
            continue

        cells = tr.find_all(["th", "td"])
        if len(cells) < sal_col + 1:
            continue

        # Player name — find link to a player page
        player = None
        for cell in cells:
            a = cell.find("a")
            if a and "/players/" in a.get("href", ""):
                player = a.get_text(strip=True)
                break
        if not player:
            player = cells[0].get_text(strip=True)
        if not player or player in ("Name", "Player", "Totals", ""):
            continue

        # Salary — ONLY from the exact 2026 column, no fallback
        raw = cells[sal_col].get_text(strip=True)
        salary = parse_salary(raw)
        if salary:
            rows.append({
                "player":   player,
                "team":     team_name,
                "division": division,
                "salary":   salary,
                "league":   "MLB"
            })

    return rows

# ── Run ──────────────────────────────────────────────────────────
print(f"Scraping {len(TEAMS)} MLB teams (2026 salary column only)...\n")

all_rows = []
seen = set()

for i, (abbr, slug, name, div) in enumerate(TEAMS):
    print(f"[{i+1:2d}/30] {name}...", end=" ", flush=True)
    rows = scrape_team(abbr, slug, name, div)

    unique = []
    for row in rows:
        if row["player"] not in seen:
            seen.add(row["player"])
            unique.append(row)

    print(f"→ {len(unique)} players")
    all_rows.extend(unique)
    time.sleep(1.5)

if not all_rows:
    print("\n✗ No data collected.")
    sys.exit(1)

df = pd.DataFrame(all_rows).sort_values("salary", ascending=False).reset_index(drop=True)
df.to_csv("mlb_salaries.csv", index=False)

print(f"\n✓ Saved mlb_salaries.csv — {len(df)} players")
print(f"  Range: ${df['salary'].min():,} – ${df['salary'].max():,}")
print(f"  Median: ${df['salary'].median():,.0f}")
print(f"\nTop 10 salaries:")
print(df[['player','team','salary']].head(10).to_string(index=False))
