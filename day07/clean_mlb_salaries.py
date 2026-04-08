"""
MLB salary cleaner — Baseball Reference team salary pages
Format: Name, Age, Yrs, Acquired, SrvTm, Agent, Contract Status, 2026, 2027...

Instructions:
1. For each team go to: baseball-reference.com/teams/{ABBR}/{slug}-salaries-and-contracts.shtml
   e.g. baseball-reference.com/teams/NYY/new-york-yankees-salaries-and-contracts.shtml
2. Click Share & Export → Get table as CSV
3. Save as a .txt or .csv file named after the team (e.g. NYY.csv)
4. Put all files in a folder called mlb_raw/
5. Run: python clean_mlb_salaries.py

Output: mlb_salaries.csv (player, team, salary, league)
"""

import pandas as pd
import os
import re

# Team name mapping from abbreviation
TEAM_NAMES = {
    "ARI": "Arizona Diamondbacks",
    "ATL": "Atlanta Braves",
    "BAL": "Baltimore Orioles",
    "BOS": "Boston Red Sox",
    "CHC": "Chicago Cubs",
    "CHW": "Chicago White Sox",
    "CIN": "Cincinnati Reds",
    "CLE": "Cleveland Guardians",
    "COL": "Colorado Rockies",
    "DET": "Detroit Tigers",
    "HOU": "Houston Astros",
    "KCR": "Kansas City Royals",
    "LAA": "Los Angeles Angels",
    "LAD": "Los Angeles Dodgers",
    "MIA": "Miami Marlins",
    "MIL": "Milwaukee Brewers",
    "MIN": "Minnesota Twins",
    "NYM": "New York Mets",
    "NYY": "New York Yankees",
    "OAK": "Athletics",
    "PHI": "Philadelphia Phillies",
    "PIT": "Pittsburgh Pirates",
    "SDP": "San Diego Padres",
    "SFG": "San Francisco Giants",
    "SEA": "Seattle Mariners",
    "STL": "St. Louis Cardinals",
    "TBR": "Tampa Bay Rays",
    "TEX": "Texas Rangers",
    "TOR": "Toronto Blue Jays",
    "WSN": "Washington Nationals",
}

# MLB divisions for multiscale viz
DIVISIONS = {
    "AL East":   ["BAL","BOS","NYY","TBR","TOR"],
    "AL Central":["CHW","CLE","DET","KCR","MIN"],
    "AL West":   ["HOU","LAA","OAK","SEA","TEX"],
    "NL East":   ["ATL","MIA","NYM","PHI","WSN"],
    "NL Central":["CHC","CIN","MIL","PIT","STL"],
    "NL West":   ["ARI","COL","LAD","SDP","SFG"],
}
# Build reverse lookup: abbr → division
PLAYER_DIVISION = {}
for div, teams in DIVISIONS.items():
    for t in teams:
        PLAYER_DIVISION[t] = div

def parse_salary(s):
    s = str(s).strip()
    if not s or s in ('FA', 'Arb', '', 'nan'):
        return None
    # Arb estimate like "Arb (~$2.2M)"
    m = re.search(r'\$([\d.]+)M', s)
    if m:
        return int(float(m.group(1)) * 1_000_000)
    # Plain dollar amount
    m = re.match(r'\$([\d,]+)$', s.replace(',', ''))
    if m:
        return int(m.group(1).replace(',', ''))
    return None

raw_dir = "mlb_raw"
if not os.path.exists(raw_dir):
    print(f"Create a folder called '{raw_dir}' and put your team CSV files in it.")
    print("Files should be named by team abbreviation, e.g. NYY.csv, LAD.csv, etc.")
    exit(1)

all_rows = []
seen_players = set()

for filename in sorted(os.listdir(raw_dir)):
    if not filename.endswith(('.csv', '.txt')):
        continue

    abbr = filename.split('.')[0].upper()
    team_name = TEAM_NAMES.get(abbr, abbr)
    division  = PLAYER_DIVISION.get(abbr, "Unknown")

    filepath = os.path.join(raw_dir, filename)
    try:
        df = pd.read_csv(filepath, skiprows=1)  # skip the first header row
    except Exception as e:
        print(f"  ✗ {filename}: {e}")
        continue

    # Find Name and 2026 columns
    name_col   = None
    salary_col = None
    for col in df.columns:
        if col.strip().lower() in ('name', 'player'):
            name_col = col
        if '2026' in str(col):
            salary_col = col

    if not name_col:
        name_col = df.columns[0]
    if not salary_col:
        # Try column index 7
        salary_col = df.columns[7] if len(df.columns) > 7 else None

    if not salary_col:
        print(f"  ✗ {team_name}: couldn't find salary column")
        continue

    count = 0
    for _, row in df.iterrows():
        name   = str(row[name_col]).strip()
        if not name or name in ('Name', 'nan', ''):
            continue
        # Skip rows that are totals/spacers
        if any(x in name for x in ['Total', 'Totals', '---']):
            continue

        salary = parse_salary(row[salary_col])
        if not salary or salary < 100_000:
            continue

        # Dedup — keep first appearance (highest salary team)
        if name in seen_players:
            continue
        seen_players.add(name)

        all_rows.append({
            'player':   name,
            'team':     team_name,
            'division': division,
            'salary':   salary,
            'league':   'MLB',
        })
        count += 1

    print(f"  {team_name}: {count} players")

if not all_rows:
    print("\nNo data found. Check your mlb_raw/ folder has the right CSV files.")
else:
    out = pd.DataFrame(all_rows).sort_values('salary', ascending=False).reset_index(drop=True)
    out.to_csv('mlb_salaries.csv', index=False)
    print(f"\n✓ {len(out)} players saved to mlb_salaries.csv")
    print(f"  Salary range: ${out['salary'].min():,} – ${out['salary'].max():,}")
    print(f"  Median: ${out['salary'].median():,.0f}")
    print(f"\nBy division:")
    print(out.groupby('division')['salary'].agg(['count','median']).to_string())
