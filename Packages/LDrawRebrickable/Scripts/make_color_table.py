#!/usr/bin/env python3
"""Makes Resources/rebrickable-colors.json: Rebrickable color id -> LDraw color codes.

From the API (the right way; needs a Rebrickable API key in REBRICKABLE_API_KEY):
    python3 make_color_table.py --api

From names, when no key is at hand (a first table; check what it reports):
    python3 make_color_table.py --names colors.csv.gz LDConfig.ldr

colors.csv.gz is Rebrickable's download. Data from Rebrickable.com.
"""

import argparse, csv, datetime, gzip, io, json, os, re, sys, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
OUTPUT = os.path.join(HERE, "..", "Sources", "LDrawRebrickable", "Resources", "rebrickable-colors.json")
API_URL = "https://rebrickable.com/api/v3/lego/colors/?page_size=1000"


def from_api():
    key = os.environ.get("REBRICKABLE_API_KEY")
    if not key:
        sys.exit("Set REBRICKABLE_API_KEY first.")
    links, url = {}, API_URL
    while url:
        if not url.startswith("https://rebrickable.com/"):
            sys.exit("The next page is on another server: " + url)
        request = urllib.request.Request(url, headers={"Authorization": "key " + key, "Accept": "application/json"})
        with urllib.request.urlopen(request) as response:
            page = json.load(response)
        for color in page.get("results", []):
            ldraw = (color.get("external_ids") or {}).get("LDraw") or {}
            codes = [int(code) for code in ldraw.get("ext_ids") or []]
            if codes and color["id"] >= 0:
                links[str(color["id"])] = codes
        url = page.get("next")
    return links, "api", []


def normalized(name):
    name = name.lower().replace("_", " ").replace("-", " ")
    name = name.replace("grey", "gray")
    return re.sub(r"\s+", " ", name).strip()


def from_names(colors_path, ldconfig_path):
    """Links by name first, then by an RGB value only one LDraw color has."""
    opener = gzip.open if colors_path.endswith(".gz") else open
    with opener(colors_path, "rt", encoding="utf-8") as file:
        rebrickable = [(int(row["id"]), row["name"], row["rgb"].upper(), row["is_trans"].lower() == "true")
                       for row in csv.DictReader(file)]

    ldraw = []
    with open(ldconfig_path, encoding="utf-8", errors="replace") as file:
        for line in file:
            match = re.match(r"\s*0\s+!COLOUR\s+(\S+)\s+CODE\s+(\d+)\s+VALUE\s+#([0-9A-Fa-f]{6})(.*)", line)
            if match:
                is_trans = re.search(r"\bALPHA\s+(\d+)", match.group(4)) is not None
                ldraw.append((int(match.group(2)), match.group(1), match.group(3).upper(), is_trans))

    by_name, by_rgb = {}, {}
    for code, name, rgb, is_trans in ldraw:
        # 16 and 24 are the main and edge colors, not real colors.
        if code in (16, 24):
            continue
        by_name.setdefault(normalized(name), []).append(code)
        by_rgb.setdefault((rgb, is_trans), []).append(code)
        # Rebrickable has no rubber colors; a tire is plain Black there.
        if name.lower().startswith("rubber_"):
            by_name.setdefault(normalized(name[len("rubber_"):]), []).append(code)

    links, by_value, unmatched = {}, [], []
    used = set()
    pending = []
    for color_id, name, rgb, is_trans in rebrickable:
        # -1 is Unknown and 9999 is Any Color; neither is an LDraw color.
        if color_id < 0 or color_id == 9999:
            continue
        codes = by_name.get(normalized(name))
        if codes:
            # The code with the same number first, then the rest in order.
            codes = sorted(set(codes), key=lambda code: (code != color_id, code))
            links[str(color_id)] = codes
            used.update(codes)
        else:
            pending.append((color_id, name, rgb, is_trans))

    for color_id, name, rgb, is_trans in pending:
        codes = [code for code in by_rgb.get((rgb, is_trans), []) if code not in used]
        if len(by_rgb.get((rgb, is_trans), [])) == 1 and codes:
            links[str(color_id)] = codes
            used.update(codes)
            ldraw_name = next(entry[1] for entry in ldraw if entry[0] == codes[0])
            by_value.append("%d %s = %d %s" % (color_id, name, codes[0], ldraw_name))
        else:
            unmatched.append("%d %s" % (color_id, name))

    notes = ["by value: " + line for line in by_value] + ["no match: " + line for line in unmatched]
    return links, "names", notes


def main():
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--api", action="store_true")
    group.add_argument("--names", nargs=2, metavar=("COLORS_CSV", "LDCONFIG"))
    arguments = parser.parse_args()

    links, source, notes = from_api() if arguments.api else from_names(*arguments.names)
    table = {
        "version": 1,
        "source": source,
        "made": datetime.date.today().isoformat(),
        "credit": "Color data from Rebrickable.com",
        "colors": dict(sorted(links.items(), key=lambda item: int(item[0]))),
    }
    with open(OUTPUT, "w", encoding="utf-8") as file:
        json.dump(table, file, indent=1)
        file.write("\n")

    print("%d colors linked, from %s." % (len(links), source))
    for line in notes:
        print("  " + line)


if __name__ == "__main__":
    main()
