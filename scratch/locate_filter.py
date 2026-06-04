import sys
sys.stdout.reconfigure(encoding='utf-8')

with open("c:/Users/kumar/combined/SILENCE_V6/lib/screens/reservations/qr_scanner_screen.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()

for j in range(320, 370):
    print(f"{j+1}: {lines[j].rstrip()}")
