import argparse
from pathlib import Path, PureWindowsPath
import re
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--vm', default='Windows 11')
parser.add_argument('--snapshot', required=True)
parser.add_argument('--script', help='Guest path to check-network-recovery.ps1 when the checkout is outside the shared home folder')
args = parser.parse_args()

if args.script:
    script = args.script
else:
    try:
        relative = Path(__file__).resolve().with_name('check-network-recovery.ps1').relative_to(Path.home())
    except ValueError:
        raise SystemExit('Use --script with the guest path when the checkout is outside the shared home folder.')
    script = str(PureWindowsPath(r'\\Mac\Home').joinpath(*relative.parts))

def run(command):
    return subprocess.run(command, check=True, text=True, capture_output=True).stdout

info = run(['prlctl', 'list', args.vm, '-i'])
network = next((line for line in info.splitlines() if re.match(r'\s*net0 \(\+\)', line)), None)
if not network or 'state=disconnected' in network:
    raise SystemExit('The VM net0 adapter must already be connected; its state was preserved.')
guest = ['prlctl', 'exec', args.vm, '--current-user', 'powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File']
prepared = run([*guest, script, '-Action', 'prepare', '-Snapshot', args.snapshot])
driver = next((line.removeprefix('DRIVER=') for line in prepared.splitlines() if line.startswith('DRIVER=')), None)
if not driver:
    raise SystemExit('The guest-local verifier was not prepared; the network remains connected.')
try:
    print('Disconnecting the test VM adapter for the native recovery check.', flush=True)
    run(['prlctl', 'set', args.vm, '--device-disconnect', 'net0'])
    print(run([*guest, driver, '-Action', 'offline']), end='', flush=True)
finally:
    print('Restoring the test VM adapter.', flush=True)
    run(['prlctl', 'set', args.vm, '--device-connect', 'net0'])
print(run([*guest, driver, '-Action', 'recovered']), end='', flush=True)
