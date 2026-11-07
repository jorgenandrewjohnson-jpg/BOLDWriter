#!/usr/bin/env python3
"""Opt-in installed-GUI regression. Navigate an already open disposable proof.

Uses authorized System Events and local screenshots; never changes TCC settings.
This test does not edit manuscript text, open/close documents, or simulate handlers.
"""
import argparse
import json
import pathlib
import re
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--window", required=True, help="Exact open proof window title")
    parser.add_argument("--page-count", required=True, type=int)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    args = parser.parse_args()
    if args.page_count < 4:
        parser.error("Use a proof with at least four pages")
    args.output.mkdir(parents=True, exist_ok=False)
    quote = lambda value: json.dumps(value, ensure_ascii=False)
    window = "window " + quote(args.window)

    def ui(body):
        script = ('tell application "/Applications/BOLD Writer.app" to activate\n'
                  'tell application "System Events" to tell process "BOLD Writer"\n'
                  'set frontmost to true\n' + body + '\nend tell')
        return subprocess.check_output(["osascript", "-e", script], text=True, timeout=20).strip()

    pid = subprocess.check_output(
        ["pgrep", "-f", "^/Applications/BOLD Writer.app/Contents/MacOS/BOLD Writer$"],
        text=True).strip()
    if ui("get unix id") != pid:
        raise RuntimeError("The GUI process is not the installed executable")
    if ui("get name of window 1") != args.window:
        raise RuntimeError("The requested proof must already be the front window")
    ui('click button 3 of group 1 of group 1 of ' + window)
    ui('click menu bar item "3D Studio" of menu bar 1\n'
       'click menu item "Camera" of menu 1 of menu bar item "3D Studio" of menu bar 1\n'
       'click menu item "Reading" of menu 1 of menu item "Camera" of menu 1 of menu bar item "3D Studio" of menu bar 1')
    time.sleep(1)
    field = 'text field 1 of group 1 of ' + window
    rows = []

    def check(label, expected):
        actual = ui('get value of ' + field)
        spread = ui('get value of every static text of group 1 of ' + window)
        if not re.search(r'\bof ' + str(args.page_count) + r'\b', spread):
            raise RuntimeError("Unexpected manuscript page count: " + spread)
        rect = ui('get {position,size} of ' + window).replace(' ', '')
        subprocess.run(['screencapture', '-x', '-R' + rect,
                        str(args.output / (label + '.png'))], check=True)
        rows.append(dict(case=label, expected=str(expected), actual=actual,
                         passed=actual == str(expected), spread=spread))
        (args.output / 'results.json').write_text(json.dumps(rows, indent=2) + '\n')

    for page in [1, args.page_count // 2, args.page_count]:
        ui('set focused of ' + field + ' to true\nkeystroke "a" using command down\n'
           'keystroke ' + quote(str(page)) + '\nkey code 36')
        time.sleep(0.7)
        check(str(page) + '-submitted', page)
        ui('click button 3 of group 1 of ' + window)
        time.sleep(0.7)
        next_spread = min(args.page_count // 2, page // 2 + 1)
        next_page = page if next_spread == page // 2 else min(args.page_count, next_spread * 2 + 1)
        check(str(page) + '-next', next_page)
        ui('click button 2 of group 1 of ' + window)
        time.sleep(0.7)
        check(str(page) + '-previous', max(1, (next_spread - 1) * 2 + 1))
    report = json.dumps(dict(window=args.window, installedPID=pid,
                             passed=all(row['passed'] for row in rows), checks=rows), indent=2) + '\n'
    (args.output / 'REPORT.txt').write_text(report)
    subprocess.run(['/usr/bin/pbcopy'], input=report, text=True, check=True)
    copied = subprocess.check_output(['/usr/bin/pbpaste'])
    if copied != report.encode():
        raise RuntimeError('Clipboard verification failed')
    print(report)
    return 0 if all(row['passed'] for row in rows) else 1


if __name__ == '__main__':
    raise SystemExit(main())
