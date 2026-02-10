# Configuration

## Windows

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; iwr 'https://raw.githubusercontent.com/dyskette/.dotconfigs/master/windows/Bootstrap.ps1' -UseBasicParsing | iex
```

## Linux

```bash
curl -sSL https://raw.githubusercontent.com/dyskette/.dotconfigs/refs/heads/master/linux/install.sh | bash
```
