#!/usr/bin/env python3
"""Read-only structural dump of a Canvas Common Cartridge (.imscc).

Usage: dump_imscc.py <cartridge.imscc> <out.txt> [<cartridge2.imscc> <out2.txt>]
Writes a full module/item listing to out.txt and prints a compact summary.
Never touches the cartridge.
"""
import re
import sys
import zipfile
import xml.etree.ElementTree as ET
from collections import Counter


def strip_ns(tag):
    return tag.split('}')[-1]


def parse(z, name):
    root = ET.fromstring(z.read(name))
    for el in root.iter():
        el.tag = strip_ns(el.tag)
    return root


def txt(el, tag):
    if el is None:
        return ''
    c = el.find(tag)
    return (c.text or '').strip() if c is not None else ''


def dump(path, out):
    z = zipfile.ZipFile(path)
    names = set(z.namelist())
    lines = [f"# {path}"]

    cs = parse(z, 'course_settings/course_settings.xml')
    for k in ['title', 'course_code', 'start_at', 'conclude_at', 'group_weighting_scheme',
              'default_view', 'restrict_student_future_view', 'restrict_student_past_view']:
        lines.append(f"{k}: {txt(cs, k)}")

    groups = {}
    if 'course_settings/assignment_groups.xml' in names:
        ag = parse(z, 'course_settings/assignment_groups.xml')
        for g in ag.iter('assignmentGroup'):
            groups[g.get('identifier')] = (txt(g, 'title'), txt(g, 'group_weight'))

    quizzes = {}
    for n in names:
        if n.endswith('/assessment_meta.xml'):
            q = parse(z, n)
            qid = q.get('identifier')
            base = n.split('/')[0]
            qti = f"non_cc_assessments/{base}.xml.qti"
            items = ngroups = draws = 0
            if qti in names:
                x = parse(z, qti)
                items = sum(1 for _ in x.iter('item'))
                secs = [s for s in x.iter('section') if s.get('ident') != 'root_section']
                ngroups = len(secs)
                for s in secs:
                    sn = s.find('.//selection_number')
                    if sn is not None and (sn.text or '').strip().isdigit():
                        draws += int(sn.text)
            a = q.find('assignment')
            gref = txt(a, 'assignment_group_identifierref') if a is not None else ''
            quizzes[qid] = dict(title=txt(q, 'title'), type=txt(q, 'quiz_type'),
                                points=txt(q, 'points_possible'), due=txt(q, 'due_at'),
                                attempts=txt(q, 'allowed_attempts'),
                                group=groups.get(gref, ('?', ''))[0],
                                items=items, groups=ngroups, draws=draws)

    assigns = {}
    for n in names:
        if n.endswith('/assignment_settings.xml'):
            a = parse(z, n)
            assigns[a.get('identifier')] = dict(
                title=txt(a, 'title'), points=txt(a, 'points_possible'), due=txt(a, 'due_at'),
                group=groups.get(txt(a, 'assignment_group_identifierref'), ('?', ''))[0],
                sub=txt(a, 'submission_types'))

    wiki = sorted(n for n in names if n.startswith('wiki_content/') and n.endswith('.html'))
    iframe = {}
    for w in wiki:
        h = z.read(w).decode('utf8', 'ignore')
        m = re.search(r'<iframe[^>]*src="([^"]+)"', h)
        t = re.search(r'<title>([^<]*)</title>', h)
        iframe[w] = (t.group(1) if t else w, m.group(1) if m else None, len(h))

    lines.append(f"\nassignment_groups ({len(groups)}):")
    for gid, (t, w) in groups.items():
        nq = sum(1 for q in quizzes.values() if q['group'] == t)
        na = sum(1 for a in assigns.values() if a['group'] == t)
        lines.append(f"  - {t}: weight {w}  ({nq} quizzes, {na} assignments)")

    mm = parse(z, 'course_settings/module_meta.xml')
    typecount = Counter()
    modsum = []
    lines.append("\nmodules:")
    for m in mm.iter('module'):
        its = list(m.iter('item'))
        title = txt(m, 'title')
        state = txt(m, 'workflow_state')
        lines.append(f"\n## [{txt(m, 'position')}] {title} ({state}, {len(its)} items, "
                     f"seq={txt(m, 'require_sequential_progress')})")
        tc = Counter()
        for it in its:
            ct = txt(it, 'content_type')
            typecount[ct] += 1
            tc[ct] += 1
            ref = txt(it, 'identifierref')
            extra = ''
            if ct == 'Quizzes::Quiz' and ref in quizzes:
                q = quizzes[ref]
                extra = (f" [{q['type']}, {q['points']}pt, due {q['due'][:10] or '-'}, "
                         f"{q['items']} items/{q['groups']} groups/{q['draws']} draws, "
                         f"attempts {q['attempts']}, grp={q['group']}]")
            elif ct == 'Assignment' and ref in assigns:
                a = assigns[ref]
                extra = f" [{a['points']}pt, due {a['due'][:10] or '-'}, grp={a['group']}, {a['sub']}]"
            elif ct == 'ExternalUrl':
                extra = f" [{txt(it, 'url')}]"
            unpub = '' if txt(it, 'workflow_state') == 'active' else ' (UNPUBLISHED)'
            indent = '  ' * int(txt(it, 'indent') or 0)
            lines.append(f"  {txt(it, 'position'):>3}. {indent}{ct:<24} {txt(it, 'title')}{unpub}{extra}")
        modsum.append((title, state, len(its), dict(tc)))

    lines.append("\nitem type counts: " + ", ".join(f"{k}={v}" for k, v in typecount.most_common()))
    inmod = {txt(i, 'identifierref') for i in mm.iter('item')}
    oq = [q['title'] for k, q in quizzes.items() if k not in inmod]
    oa = [a['title'] for k, a in assigns.items() if k not in inmod]
    lines.append(f"quizzes total {len(quizzes)}, not in any module: {len(oq)}"
                 + (": " + "; ".join(sorted(oq)[:20]) if oq else ''))
    lines.append(f"assignments total {len(assigns)}, not in any module: {len(oa)}"
                 + (": " + "; ".join(sorted(oa)[:20]) if oa else ''))
    with_if = sum(1 for v in iframe.values() if v[1])
    lines.append(f"wiki pages {len(wiki)}, with iframe {with_if}, without {len(wiki) - with_if}")
    noif = [v[0] for v in iframe.values() if not v[1]]
    if noif:
        lines.append("  no-iframe pages: " + "; ".join(sorted(noif)[:25]))
    hosts = Counter(re.sub(r'^(https?://[^/]+/[^/]+/).*', r'\1', v[1]) for v in iframe.values() if v[1])
    lines.append("  iframe src prefixes: " + ", ".join(f"{k} x{v}" for k, v in hosts.most_common(5)))
    lines.append(f"zip entries: {len(names)}; web_resources: {sum(1 for n in names if n.startswith('web_resources/'))}")

    with open(out, 'w') as f:
        f.write("\n".join(lines) + "\n")
    # compact summary to stdout: everything except item rows
    print("\n".join(l for l in lines if not re.match(r'^\s+\d+\.', l)))
    return modsum


def main():
    args = sys.argv[1:]
    results = []
    for i in range(0, len(args), 2):
        results.append((args[i], dump(args[i], args[i + 1])))
        print("\n" + "=" * 70 + "\n")
    if len(results) == 2:
        (pa, a), (pb, b) = results
        print(f"MODULE COMPARISON: A={pa}  B={pb}")
        ta = {t: (s, n, tc) for t, s, n, tc in a}
        tb = {t: (s, n, tc) for t, s, n, tc in b}
        for t in list(ta) + [t for t in tb if t not in ta]:
            xa = ta.get(t)
            xb = tb.get(t)
            if xa and xb:
                print(f"  BOTH   {t!r:<60} A {xa[1]:>3} items  B {xb[1]:>3} items")
            elif xa:
                print(f"  A-ONLY {t!r:<60} {xa[1]} items")
            else:
                print(f"  B-ONLY {t!r:<60} {xb[1]} items")


if __name__ == '__main__':
    main()
