"""
MLB salary scraper — scrapes all 30 team pages from baseball-reference.com
No manual steps needed. Run from any directory.

Usage:
    python scrape_mlb_final.py

Output: mlb_salaries.csv in the current directory
"""

import requests
from bs4 import BeautifulSoup
import pandas as pd
import time
import re
import sys

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
    s = str(s).strip()
    if not s or s in ('FA','Arb','nan',''):
        return None
    # "$40M", "$14.5M", "$2.16M"
    m = re.search(r'\$([\d.]+)M', s)
    if m:
        return int(float(m.group(1)) * 1_000_000)
    # "$40,000,000" or "$758,750"
    m = re.match(r'\$?([\d,]+)$', s.replace(',',''))
    if m:
        v = int(m.group(1).replace(',',''))
        return v if v > 10000 else None
    return None

def scrape_team(abbr, slug, team_name, division):
    url = f"https://www.baseball-reference.com/teams/{abbr}/{slug}-salaries-and-contracts.shtml"
    try:
        r = requests.get(url, headers=HEADERS, timeout=25)
        r.raise_for_status()
    except Exception as e:
        print(f"  ✗ {team_name}: fetch error — {e}")
        return []

    soup = BeautifulSoup(r.text, "lxml")

    # Find the salary table
    table = (soup.find("table", id=re.compile("salary", re.I))
             or soup.find("table", id=re.compile("contract", re.I))
             or soup.find("table"))
    if not table:
        print(f"  ✗ {team_name}: no table found")
        return []

    # Identify header row to find salary column
    headers = []
    for tr in table.find_all("tr"):
        ths = tr.find_all(["th","td"])
        if ths and len(ths) > 5:
            headers = [th.get_text(strip=True) for th in ths]
            break

    # Find current year salary column (2025 or 2026)
    sal_col = None
    for i, h in enumerate(headers):
        if h in ("2026","2025"):
            sal_col = i
            break
    if sal_col is None:
        sal_col = 7  # fallback — typically 8th column

    rows = []
    tbody = table.find("tbody") or table
    for tr in tbody.find_all("tr"):
        cls = tr.get("class", [])
        if any(c in cls for c in ["thead","spacer","partial_table"]):
            continue

        cells = tr.find_all(["th","td"])
        if len(cells) < 4:
            continue

        # Player name — look for a link first
        player = None
        for cell in cells:
            a = cell.find("a")
            if a and a.get("href","").startswith("/players/"):
                player = a.get_text(strip=True)
                break
        if not player:
            player = cells[0].get_text(strip=True)

        if not player or player in ("Name","Player","Totals",""):
            continue
        if re.match(r'^-+$', player):
            continue

        # Salary from detected column
        salary = None
        if sal_col < len(cells):
            salary = parse_salary(cells[sal_col].get_text(strip=True))

        # Fallback: scan all cells for a dollar amount
        if not salary:
            for cell in cells:
                txt = cell.get_text(strip=True)
                s = parse_salary(txt)
                if s and s > 500_000:
                    salary = s
                    break

        if salary and salary > 100_000:
            rows.append({
                "player":   player,
                "team":     team_name,
                "division": division,
                "salary":   salary,
                "league":   "MLB"
            })

    return rows

# ── Run ───────────────────────────────────────────────────────────
print(f"Scraping {len(TEAMS)} MLB teams from baseball-reference.com...")
print("This will take ~1 minute (polite 1.5s delay between requests)\n")

all_rows = []
seen = set()

for i, (abbr, slug, name, div) in enumerate(TEAMS):
    print(f"[{i+1:2d}/30] {name}...", end=" ", flush=True)
    rows = scrape_team(abbr, slug, name, div)

    # Dedup players who appear on multiple teams
    unique = []
    for row in rows:
        if row["player"] not in seen:
            seen.add(row["player"])
            unique.append(row)

    print(f"{len(unique)} players")
    all_rows.extend(unique)
    time.sleep(1.5)

if not all_rows:
    print("\n✗ No data collected — Baseball Reference may have blocked requests.")
    print("  Try running again, or reduce the number of requests.")
    sys.exit(1)

df = pd.DataFrame(all_rows).sort_values("salary", ascending=False).reset_index(drop=True)
df.to_csv("mlb_salaries.csv", index=False)

print(f"\n✓ Saved mlb_salaries.csv — {len(df)} players across {df['team'].nunique()} teams")
print(f"  Salary range: ${df['salary'].min():,} – ${df['salary'].max():,}")
print(f"  Median: ${df['salary'].median():,.0f}")
print(f"\nTop 10 salaries:")
print(df[['player','team','salary']].head(10).to_string(index=False))
print(f"\nTotal payroll by team (top 10):")
print(df.groupby('team')['salary'].sum().sort_values(ascending=False).head(10).apply(lambda x: f"${x/1e6:.1f}M").to_string())
