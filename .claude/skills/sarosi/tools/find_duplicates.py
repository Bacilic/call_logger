"""Ανιχνευτής αντιγράφων για τον φακό «αντίγραφα» της /sarosi.

Βρίσκει κομμάτια κώδικα Dart που υπάρχουν αυτούσια (μετά από κανονικοποίηση
κενών και σχολίων) σε δύο ή περισσότερα σημεία του lib/. Δεν κρίνει τίποτα —
μόνο απαριθμεί ζεύγη. Η κρίση «σκόπιμο ή απόκλιση;» είναι δουλειά του γύρου.

Χρήση (από τη ρίζα του έργου):
    python -I .claude/skills/sarosi/tools/find_duplicates.py [--min N] [--top N] [--path lib/core]

--min   ελάχιστο πλήθος ουσιαστικών γραμμών ανά κοινό κομμάτι (προεπιλογή 8)
--top   πόσα ζεύγη να τυπωθούν, μεγαλύτερα πρώτα (προεπιλογή 40)
--path  φάκελος/αρχείο προς σάρωση (προεπιλογή lib); επαναλαμβανόμενο
"""

import argparse
import hashlib
import os
import re
import sys
from collections import defaultdict

EXCLUDED_PARTS = (
    os.sep + 'old_database' + os.sep,
    'database_v1_schema.dart',
    'lamp_migration_service.dart',
    'database_schema_migrations.dart',
    '.g.dart',
    '.freezed.dart',
)

# Γραμμές χωρίς πληροφορία: κλεισίματα, σκέτες παρενθέσεις, λέξεις-κλειδιά.
_TRIVIAL = re.compile(r'^[\s\)\]\}\(\[\{,;:]*$|^(else|try|return;|break;|continue;|const|final)$')


def _normalize(line):
    line = line.strip()
    if not line or line.startswith('//') or line.startswith('///'):
        return None
    line = re.sub(r'\s+', ' ', line)
    if _TRIVIAL.match(line) or len(line) < 4:
        return None
    return line


def _collect(paths):
    files = []
    for root in paths:
        if os.path.isfile(root):
            files.append(root)
            continue
        for dirpath, _, names in os.walk(root):
            for n in names:
                if n.endswith('.dart'):
                    files.append(os.path.join(dirpath, n))
    out = []
    for f in sorted(files):
        if any(part in f for part in EXCLUDED_PARTS):
            continue
        meaningful = []
        with open(f, encoding='utf-8', errors='replace') as fh:
            for no, raw in enumerate(fh, 1):
                norm = _normalize(raw)
                if norm is not None:
                    meaningful.append((no, norm))
        out.append((f, meaningful))
    return out


def find(paths, min_lines):
    data = _collect(paths)
    index = defaultdict(list)
    for fi, (_, lines) in enumerate(data):
        for i in range(len(lines) - min_lines + 1):
            key = hashlib.md5(
                '\n'.join(t for _, t in lines[i:i + min_lines]).encode('utf-8')
            ).digest()
            index[key].append((fi, i))

    seen = set()
    pairs = []
    for occ in index.values():
        if len(occ) < 2:
            continue
        for a in range(len(occ)):
            for b in range(a + 1, len(occ)):
                (fa, ia), (fb, ib) = occ[a], occ[b]
                if (fa, ia, fb, ib) in seen:
                    continue
                if fa == fb and abs(ia - ib) < min_lines:
                    continue
                la, lb = data[fa][1], data[fb][1]
                # Πίσω στην αρχή του κοινού κομματιού, για να μη μετρηθεί δύο φορές.
                while ia > 0 and ib > 0 and la[ia - 1][1] == lb[ib - 1][1]:
                    ia -= 1
                    ib -= 1
                if (fa, ia, fb, ib) in seen:
                    continue
                n = 0
                while ia + n < len(la) and ib + n < len(lb) and la[ia + n][1] == lb[ib + n][1]:
                    seen.add((fa, ia + n, fb, ib + n))
                    n += 1
                if fa == fb and ia + n > ib:
                    continue
                pairs.append((n, fa, ia, fb, ib))
    pairs.sort(key=lambda p: (-p[0], data[p[1]][0], p[2]))
    return data, pairs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--min', type=int, default=8)
    ap.add_argument('--top', type=int, default=40)
    ap.add_argument('--path', action='append')
    args = ap.parse_args()
    sys.stdout.reconfigure(encoding='utf-8')
    paths = args.path or ['lib']
    data, pairs = find(paths, args.min)
    print(f'Αρχεία: {len(data)} · ζεύγη με >= {args.min} κοινές ουσιαστικές γραμμές: {len(pairs)}')
    for n, fa, ia, fb, ib in pairs[:args.top]:
        la, lb = data[fa][1], data[fb][1]
        a0, a1 = la[ia][0], la[ia + n - 1][0]
        b0, b1 = lb[ib][0], lb[ib + n - 1][0]
        fa_name = data[fa][0].replace(os.sep, '/')
        fb_name = data[fb][0].replace(os.sep, '/')
        print(f'{n:4d}  {fa_name}:{a0}-{a1}  <->  {fb_name}:{b0}-{b1}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
