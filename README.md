# Configuration

## Windows

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-RestMethod https://raw.githubusercontent.com/dyskette/.dotconfigs/refs/heads/master/windows/Install-WindowsEnvironment.ps1 | Invoke-Expression
```

## Linux

```bash
curl -sSL https://raw.githubusercontent.com/dyskette/.dotconfigs/refs/heads/master/linux/install.sh | bash
```
